-- =====================================================================
-- 2026_10_inventory_tools.sql — the last pieces for 10/10 stock
-- (owner, 23 Oct 2026: "i want 10/10 please fix all")
--
--   1. save_stock_count: a shelf count in one step. Sales (or purchases)
--      made while the shelf was being counted are kept: counted 40, 2 sold
--      meanwhile -> 38. The count, the stock and the batches change
--      together, with the history line.
--   2. Stock In / Stock Out are written down (stock_adjustments), with a
--      reason, through adjust_stock_logged.
--   3. Return to supplier (supplier_returns): goods go back to the agency.
--      The stock comes out at its real (FIFO) cost; the value first
--      reduces what the shop owes that supplier (oldest bill first), the
--      rest is money received back (cash / UPI / bank), posted by the
--      database like every other document. A return can be deleted:
--      stock, dues and money go back.
--   4. get_stock_history: every movement of one product, newest first,
--      with the stock after each one.
--
-- Nothing existing is changed or deleted.
-- Idempotent; one transaction. Apply in Supabase -> SQL Editor:
--   back up, run verify_schema.sql, run this file, run verify_schema.sql.
-- =====================================================================
BEGIN;

-- 1. a count that keeps the sales made while counting -------------------
CREATE OR REPLACE FUNCTION public.save_stock_count(p_product uuid, p_counted numeric, p_app_qty numeric,
                                                   p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cur numeric; v_moved numeric; v_final numeric; v_app numeric;
BEGIN
  PERFORM public.assert_admin();
  IF p_counted IS NULL OR p_counted < 0 THEN RAISE EXCEPTION 'Enter what is on the shelf (0 or more)'; END IF;
  SELECT stock INTO v_cur FROM products WHERE id = p_product FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product not found' USING ERRCODE = 'P0002'; END IF;
  v_app := coalesce(p_app_qty, v_cur);       -- what the app said when counting began
  v_moved := v_cur - v_app;                  -- sold (-) or bought (+) since then
  v_final := round(p_counted + v_moved, 3);
  IF v_final >= 0 THEN
    PERFORM public.reconcile_stock_with_batches(p_product, v_final);
  ELSE
    PERFORM public.reconcile_stock_with_batches(p_product, 0);
    UPDATE products SET stock = v_final, updated_at = now() WHERE id = p_product;
  END IF;
  INSERT INTO stock_reconciliation (product_id, system_qty, physical_qty, notes, performed_by)
  VALUES (p_product, v_app, p_counted, coalesce(nullif(trim(p_reason), ''), 'Counted'), auth.uid());
  RETURN jsonb_build_object('stock', v_final, 'moved', v_moved, 'difference', p_counted - v_app);
END $$;
REVOKE EXECUTE ON FUNCTION public.save_stock_count(uuid, numeric, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_stock_count(uuid, numeric, numeric, text) TO authenticated;

-- 2. Stock In / Stock Out, written down -----------------------------------
CREATE TABLE IF NOT EXISTS stock_adjustments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID,                 -- no foreign key: Factory Reset / Restore empty
                                   -- tables by a fixed list (see 5. below)
  delta NUMERIC(14,3) NOT NULL,
  stock_after NUMERIC(14,3),
  reason TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_stock_adjustments_product ON stock_adjustments(product_id, created_at);
ALTER TABLE stock_adjustments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS stock_adjustments_admin_read ON stock_adjustments;
CREATE POLICY stock_adjustments_admin_read ON stock_adjustments FOR SELECT TO authenticated USING (public.is_admin());

CREATE OR REPLACE FUNCTION public.adjust_stock_logged(p_product uuid, p_delta numeric, p_reason text)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_after numeric;
BEGIN
  v_after := public.adjust_stock(p_product, p_delta);       -- checks admin and the limits
  INSERT INTO stock_adjustments (product_id, delta, stock_after, reason, created_by)
  VALUES (p_product, p_delta, v_after,
          coalesce(nullif(trim(p_reason), ''), CASE WHEN p_delta > 0 THEN 'Stock In' ELSE 'Stock Out' END),
          auth.uid());
  RETURN v_after;
END $$;
REVOKE EXECUTE ON FUNCTION public.adjust_stock_logged(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.adjust_stock_logged(uuid, numeric, text) TO authenticated;

-- 3. return to supplier ----------------------------------------------------
CREATE TABLE IF NOT EXISTS supplier_returns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id UUID,                -- no foreign key (see 5. below)
  supplier_name TEXT,
  items JSONB NOT NULL DEFAULT '[]',
  total_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  credit_amount NUMERIC(12,2) NOT NULL DEFAULT 0,   -- taken off what the shop owes
  credit_allocs JSONB NOT NULL DEFAULT '[]',        -- [{purchase_id, amount}]
  refund_amount NUMERIC(12,2) NOT NULL DEFAULT 0,   -- money received back
  refund_method TEXT NOT NULL DEFAULT 'cash',
  cost_amount NUMERIC(12,2) NOT NULL DEFAULT 0,     -- FIFO cost of the goods
  reason TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_supplier_returns_supplier ON supplier_returns(supplier_id, created_at);
ALTER TABLE supplier_returns ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS supplier_returns_admin_read ON supplier_returns;
CREATE POLICY supplier_returns_admin_read ON supplier_returns FOR SELECT TO authenticated USING (public.is_admin());

-- money received back: posted to cash / bank like every document
CREATE OR REPLACE FUNCTION public.supplier_return_postings_trigger() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.supplier_returns; v_desc text;
BEGIN
  IF public.app_bulk_mode() THEN RETURN NULL; END IF;
  r := CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  v_desc := 'Returned to ' || coalesce(nullif(r.supplier_name, ''), 'supplier') || ' #' || left(r.id::text, 8)
            || CASE TG_OP WHEN 'DELETE' THEN ' (deleted)' WHEN 'UPDATE' THEN ' (edited)' ELSE '' END;
  PERFORM public.reconcile_postings(
    'supplier_returns', r.id,
    CASE WHEN TG_OP = 'DELETE' THEN '{}'::jsonb
         ELSE public.money_split(r.refund_amount, 0, 0, r.refund_method, 1) END,
    'supplier_refund' || CASE TG_OP WHEN 'INSERT' THEN '' WHEN 'UPDATE' THEN '_edit' ELSE '_reversal' END,
    v_desc, coalesce(auth.uid(), r.created_by),
    CASE WHEN TG_OP = 'INSERT' THEN coalesce(r.created_at, now()) ELSE now() END);
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.supplier_return_postings_trigger() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS b_supplier_returns_postings ON supplier_returns;
CREATE TRIGGER b_supplier_returns_postings AFTER INSERT OR UPDATE OR DELETE ON supplier_returns
  FOR EACH ROW EXECUTE FUNCTION public.supplier_return_postings_trigger();

-- p_items: [{product_id, name, qty, price, stock_factor?}] — price per line unit
CREATE OR REPLACE FUNCTION public.create_supplier_return(p_id uuid, p_supplier_id uuid, p_supplier_name text,
                                                        p_items jsonb, p_refund_method text, p_reason text)
RETURNS SETOF public.supplier_returns LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_items jsonb := coalesce(p_items, '[]'::jsonb); v_item jsonb; i int;
  v_prod record; v_qty numeric; v_factor numeric; v_base numeric; t record;
  v_total numeric := 0; v_cost numeric := 0; v_left numeric; v_take numeric;
  v_allocs jsonb := '[]'::jsonb; v_credit numeric := 0; v_method text; v_name text; b record;
BEGIN
  PERFORM public.assert_admin();
  IF p_id IS NULL THEN RAISE EXCEPTION 'Return id missing'; END IF;
  -- a retried save: the first one already went through
  IF EXISTS (SELECT 1 FROM supplier_returns WHERE id = p_id) THEN
    RETURN QUERY SELECT * FROM supplier_returns WHERE id = p_id; RETURN;
  END IF;
  IF jsonb_typeof(v_items) <> 'array' OR jsonb_array_length(v_items) = 0 THEN
    RAISE EXCEPTION 'Add at least one item to return';
  END IF;
  v_name := nullif(trim(p_supplier_name), '');
  IF p_supplier_id IS NOT NULL THEN
    SELECT coalesce(v_name, name) INTO v_name FROM suppliers WHERE id = p_supplier_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supplier not found' USING ERRCODE = 'P0002'; END IF;
  END IF;

  FOR i IN 0 .. jsonb_array_length(v_items) - 1 LOOP
    v_item := v_items -> i;
    v_qty := public.jnum(v_item, 'qty', 0);
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Item % has an invalid quantity', coalesce(v_item->>'name', i::text); END IF;
    BEGIN
      SELECT id, name, stock, unit_type, purchase_price INTO v_prod
      FROM products WHERE id = (v_item->>'product_id')::uuid FOR UPDATE;
    EXCEPTION WHEN invalid_text_representation THEN v_prod := NULL;
    END;
    IF v_prod.id IS NULL THEN RAISE EXCEPTION 'Product not found: %', coalesce(v_item->>'name', '?'); END IF;
    v_factor := public.item_stock_factor(v_item, v_prod.unit_type);
    v_base := round(v_qty * v_factor, 3);
    IF v_prod.stock + 0.0005 < v_base THEN
      RAISE EXCEPTION 'Only % of % in stock — cannot return %', v_prod.stock, v_prod.name, v_base;
    END IF;
    UPDATE products SET stock = stock - v_base WHERE id = v_prod.id;
    SELECT * INTO t FROM public.fifo_take(v_prod.id, v_base, coalesce(v_prod.purchase_price, 0));
    v_item := v_item || jsonb_build_object('name', coalesce(v_item->>'name', v_prod.name), 'stock_factor', v_factor,
                                           'base_qty', v_base, 'allocs', t.allocs, 'cost_total', round(t.cost, 2));
    v_items := jsonb_set(v_items, ARRAY[i::text], v_item);
    v_total := v_total + v_qty * public.jnum(v_item, 'price', 0);
    v_cost := v_cost + t.cost;
  END LOOP;
  v_total := round(v_total, 2);

  -- first off what the shop owes this supplier, oldest bill first
  v_left := v_total;
  IF p_supplier_id IS NOT NULL THEN
    FOR b IN SELECT id, due_amount FROM purchases
             WHERE supplier_id = p_supplier_id AND due_amount > 0
             ORDER BY created_at, id FOR UPDATE
    LOOP
      EXIT WHEN v_left < 0.005;
      v_take := least(b.due_amount, v_left);
      UPDATE purchases SET due_amount = due_amount - v_take WHERE id = b.id;
      v_allocs := v_allocs || jsonb_build_array(jsonb_build_object('purchase_id', b.id, 'amount', v_take));
      v_credit := v_credit + v_take;
      v_left := v_left - v_take;
    END LOOP;
  END IF;

  v_method := coalesce(public.norm_payment_method(nullif(p_refund_method, '')), 'cash');
  IF v_method IN ('credit', 'split') THEN v_method := 'cash'; END IF;

  RETURN QUERY INSERT INTO supplier_returns (id, supplier_id, supplier_name, items, total_amount, credit_amount,
                                            credit_allocs, refund_amount, refund_method, cost_amount, reason, created_by)
  VALUES (p_id, p_supplier_id, v_name, v_items, v_total, round(v_credit, 2), v_allocs,
          round(v_total - v_credit, 2), v_method, round(v_cost, 2), nullif(trim(p_reason), ''), auth.uid())
  RETURNING *;
END $$;
REVOKE EXECUTE ON FUNCTION public.create_supplier_return(uuid, uuid, text, jsonb, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_supplier_return(uuid, uuid, text, jsonb, text, text) TO authenticated;

-- undo a return entered by mistake: stock, dues and money go back
CREATE OR REPLACE FUNCTION public.delete_supplier_return(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.supplier_returns; v_item jsonb; a jsonb; v_base numeric; v_stock numeric; v_pid uuid;
BEGIN
  PERFORM public.assert_admin();
  SELECT * INTO r FROM supplier_returns WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;          -- already gone
  FOR v_item IN SELECT * FROM jsonb_array_elements(r.items) LOOP
    v_pid := (v_item->>'product_id')::uuid;
    v_base := public.jnum(v_item, 'base_qty', 0);
    CONTINUE WHEN v_base <= 0;
    SELECT stock INTO v_stock FROM products WHERE id = v_pid FOR UPDATE;
    CONTINUE WHEN NOT FOUND;
    UPDATE products SET stock = stock + v_base WHERE id = v_pid;
    PERFORM public.restore_stock_fifo(v_pid, v_base, public.jnum(v_item, 'cost_total', 0) / v_base);
    PERFORM public.settle_stock_deficit(v_pid, v_stock, v_base);
  END LOOP;
  FOR a IN SELECT * FROM jsonb_array_elements(r.credit_allocs) LOOP
    UPDATE purchases SET due_amount = due_amount + public.jnum(a, 'amount', 0)
    WHERE id = (a->>'purchase_id')::uuid;
  END LOOP;
  DELETE FROM supplier_returns WHERE id = p_id;
END $$;
REVOKE EXECUTE ON FUNCTION public.delete_supplier_return(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_supplier_return(uuid) TO authenticated;

-- 4. every movement of one product, newest first ---------------------------
CREATE OR REPLACE FUNCTION public.get_stock_history(p_product uuid, p_limit integer DEFAULT 300)
RETURNS TABLE (at timestamptz, kind text, qty numeric, stock_after numeric, ref text, note text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE v_unit text; v_stock numeric;
BEGIN
  PERFORM public.assert_member();
  SELECT unit_type, stock INTO v_unit, v_stock FROM products WHERE id = p_product;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product not found' USING ERRCODE = 'P0002'; END IF;
  RETURN QUERY
  WITH moves AS (
    SELECT s.created_at AS at, 'Sale'::text AS kind,
           -coalesce(public.jnum(x, 'base_qty', NULL), public.jnum(x, 'qty', 0) * public.item_stock_factor(x, v_unit)) AS qty,
           'Bill #' || coalesce(s.invoice_no::text, left(s.id::text, 8)) AS ref,
           CASE WHEN x ? 'oversold_qty' THEN public.jnum(x, 'oversold_qty', 0)::text || ' sold before the purchase was entered' END AS note
    FROM sales s, jsonb_array_elements(s.items) x
    WHERE x->>'product_id' = p_product::text
    UNION ALL
    SELECT p.created_at, 'Purchase', public.jnum(x, 'qty', 0) * public.item_stock_factor(x, v_unit),
           coalesce(nullif(p.supplier_name, ''), 'Purchase') || ' #' || left(p.id::text, 8), NULL
    FROM purchases p, jsonb_array_elements(p.items) x
    WHERE x->>'product_id' = p_product::text
    UNION ALL
    SELECT pr.created_at, 'Customer return',
           pr.quantity * coalesce((SELECT public.item_base_qty(x) / nullif(public.jnum(x, 'qty', 0), 0)
                                   FROM sales s, jsonb_array_elements(s.items) x
                                   WHERE s.id = coalesce(pr.original_sale_id, pr.sale_id)
                                     AND x->>'product_id' = p_product::text LIMIT 1), 1),
           'Bill #' || coalesce((SELECT invoice_no::text FROM sales WHERE id = coalesce(pr.original_sale_id, pr.sale_id)), '?'),
           pr.reason
    FROM product_returns pr WHERE pr.product_id = p_product
    UNION ALL
    SELECT d.created_at, 'Damaged', -d.quantity, NULL, d.reason
    FROM damaged_products d WHERE d.product_id = p_product
    UNION ALL
    SELECT r.created_at,
           CASE WHEN coalesce(r.notes, '') LIKE '2026-10 upgrade%' THEN 'Correction' ELSE 'Count' END,
           r.physical_qty - r.system_qty, 'shelf ' || trim(to_char(r.physical_qty, 'FM999999990.###')), r.notes
    FROM stock_reconciliation r WHERE r.product_id = p_product
    UNION ALL
    SELECT a.created_at, CASE WHEN a.delta > 0 THEN 'Stock In' ELSE 'Stock Out' END, a.delta, NULL, a.reason
    FROM stock_adjustments a WHERE a.product_id = p_product
    UNION ALL
    SELECT sr.created_at, 'Returned to supplier', -public.jnum(x, 'base_qty', 0),
           coalesce(sr.supplier_name, 'Supplier') || ' #' || left(sr.id::text, 8), sr.reason
    FROM supplier_returns sr, jsonb_array_elements(sr.items) x
    WHERE x->>'product_id' = p_product::text
  ), ordered AS (
    SELECT m.*, row_number() OVER (ORDER BY m.at DESC) AS n FROM moves m WHERE m.qty IS NOT NULL
  )
  SELECT o.at, o.kind, round(o.qty, 3),
         round(v_stock - coalesce(sum(o.qty) OVER (ORDER BY o.n ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0), 3),
         o.ref, o.note
  FROM ordered o ORDER BY o.n LIMIT greatest(coalesce(p_limit, 300), 1);
END $$;
REVOKE EXECUTE ON FUNCTION public.get_stock_history(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_stock_history(uuid, integer) TO authenticated;

-- 5. backups and resets ------------------------------------------------------
-- the new tables are saved in a backup and restored from it (after the
-- products, suppliers and purchases they point to) ...
CREATE OR REPLACE FUNCTION public.backup_table_list() RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY['shop_settings','app_config','customers','suppliers','products','product_variants',
               'accounts','sales','purchase_orders','purchases','inventory_batches','payments',
               'supplier_payments','expenses','account_transactions','legacy_postings','product_returns',
               'damaged_products','stock_reconciliation','payment_reminders','transaction_edits',
               'stock_adjustments','supplier_returns']
$$;
-- ... and Factory Reset, which empties the products, empties them too
CREATE OR REPLACE FUNCTION public.clear_inventory_logs() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- DELETE, not TRUNCATE: Restore truncates these in the same statement.
  -- Both callers run in bulk mode, so nothing is posted to the cash book.
  DELETE FROM public.stock_adjustments;
  DELETE FROM public.supplier_returns;
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.clear_inventory_logs() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS z_clear_inventory_logs ON products;
CREATE TRIGGER z_clear_inventory_logs AFTER TRUNCATE ON products
  FOR EACH STATEMENT EXECUTE FUNCTION public.clear_inventory_logs();

COMMIT;
