-- =====================================================================
-- 2026_10_stock_negative.sql — sell before the purchase bill is entered
-- (owner, 18 Oct 2026)
--
-- Goods arrive, but the purchase bill is entered a day or two later. Sales
-- made meanwhile were billed while the app showed 0 stock, and the stock
-- was CLAMPED at 0 (rule products_stock_non_negative + sale_apply_items),
-- so those sales were forgotten: sell 12 at 0 -> 0, then purchase 100 ->
-- 100 instead of 88.
--
-- Now:
--   * a sale takes stock below zero:            0 - 12 = -12,  5 - 8 = -3
--   * a purchase adds on top:                  -12 + 100 = 88
--   * the units already sold are taken out of the new purchase's batch,
--     so batches (FIFO cost) still equal the stock and nothing is
--     deducted twice;
--   * the same for every other way stock goes up while it is below zero:
--     sales return, deleting / editing a sale, editing a purchase,
--     receiving a purchase order, deleting a damaged entry, Stock In,
--     physical count.
-- Unchanged: Stock Out and damaged stock still cannot go below zero, a
-- purchase whose stock was sold still cannot be deleted, and the batch rule
-- (remaining >= 0) stays.
--
-- Nothing is deleted and no stored figure is rewritten. Products whose
-- stock was clamped in the past are listed (read only) by
-- sql/stock_negative_report.sql; correct them with a physical count.
--
-- Idempotent; one transaction. Apply in Supabase -> SQL Editor:
--   back up, run verify_schema.sql, run this file, run verify_schema.sql.
-- =====================================================================
BEGIN;

-- 1. stock may go below zero (batches may not)
ALTER TABLE products DROP CONSTRAINT IF EXISTS products_stock_non_negative;

-- 2. the units already sold while the stock was below zero come out of
--    whatever was just added, oldest batch first
CREATE OR REPLACE FUNCTION public.settle_stock_deficit(p_product uuid, p_old_stock numeric, p_added numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cover numeric;
BEGIN
  v_cover := round(least(greatest(-coalesce(p_old_stock, 0), 0), greatest(coalesce(p_added, 0), 0)), 3);
  IF v_cover > 0 THEN
    PERFORM public.fifo_take(p_product, v_cover, 0);
  END IF;
END $$;
REVOKE EXECUTE ON FUNCTION public.settle_stock_deficit(uuid, numeric, numeric) FROM PUBLIC, anon, authenticated;

-- 3. sale: no clamping
CREATE OR REPLACE FUNCTION public.sale_apply_items(p_items jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_items jsonb := coalesce(p_items, '[]'::jsonb);
  v_item jsonb; i int; v_prod record; v_qty numeric; v_factor numeric; v_base numeric;
  v_over numeric; v_fb numeric; t record;
BEGIN
  IF jsonb_typeof(v_items) <> 'array' THEN RAISE EXCEPTION 'Sale items must be a list'; END IF;
  FOR i IN 0 .. jsonb_array_length(v_items) - 1 LOOP
    v_item := v_items -> i;
    v_qty := public.jnum(v_item, 'qty', 0);
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Item % has an invalid quantity', coalesce(v_item->>'name', i::text); END IF;
    BEGIN
      SELECT id, stock, unit_type, purchase_price INTO v_prod
      FROM products WHERE id = (v_item->>'product_id')::uuid FOR UPDATE;
    EXCEPTION WHEN invalid_text_representation THEN
      v_prod := NULL;
    END;
    IF v_prod.id IS NULL THEN
      CONTINUE;          -- product deleted or a free-text line: nothing to deduct
    END IF;

    v_factor := public.item_stock_factor(v_item, v_prod.unit_type);
    v_base := round(v_qty * v_factor, 3);

    -- the stock goes below zero when the goods were sold before their
    -- purchase was entered; the purchase, when entered, makes it up
    v_over := greatest(v_base - greatest(v_prod.stock, 0), 0);
    UPDATE products SET stock = stock - v_base WHERE id = v_prod.id;

    -- fallback cost per stock unit for anything not covered by batches
    v_fb := coalesce(nullif(v_prod.purchase_price, 0),
                     public.jnum(v_item, 'purchase_price', 0) / nullif(v_factor, 0), 0);
    SELECT * INTO t FROM public.fifo_take(v_prod.id, v_base, v_fb);

    v_item := v_item || jsonb_build_object(
      'stock_factor', v_factor,
      'base_qty', v_base,
      'allocs', t.allocs,
      'cost_total', round(t.cost, 2),
      'purchase_price', round(t.cost / v_qty, 4),
      'returned_base', 0);
    -- units not on hand at the time of the sale (information only)
    IF v_over > 0 THEN v_item := v_item || jsonb_build_object('oversold_qty', v_over); END IF;
    v_items := jsonb_set(v_items, ARRAY[i::text], v_item);
  END LOOP;
  RETURN v_items;
END $$;
REVOKE EXECUTE ON FUNCTION public.sale_apply_items(jsonb) FROM PUBLIC, anon, authenticated;

-- 4. purchase: adds on top of a negative stock
CREATE OR REPLACE FUNCTION public.purchase_apply_items(p_purchase public.purchases) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_item jsonb; v_gross numeric; v_k numeric; v_prod record; v_factor numeric;
  v_base numeric; v_unit_cost numeric;
BEGIN
  SELECT coalesce(sum(public.jnum(x, 'price', 0) * public.jnum(x, 'qty', 0)), 0)
    INTO v_gross FROM jsonb_array_elements(coalesce(p_purchase.items, '[]'::jsonb)) x;
  -- bill discount / extras / round-off are spread over the lines (landed cost)
  v_k := CASE WHEN v_gross > 0 AND coalesce(p_purchase.total_amount, 0) > 0
              THEN p_purchase.total_amount / v_gross ELSE 1 END;

  FOR v_item IN SELECT * FROM jsonb_array_elements(coalesce(p_purchase.items, '[]'::jsonb)) LOOP
    BEGIN
      SELECT id, unit_type, stock INTO v_prod FROM products WHERE id = (v_item->>'product_id')::uuid FOR UPDATE;
    EXCEPTION WHEN invalid_text_representation THEN v_prod := NULL;
    END;
    CONTINUE WHEN v_prod.id IS NULL;
    v_factor := public.item_stock_factor(v_item, v_prod.unit_type);
    v_base := round(public.jnum(v_item, 'qty', 0) * v_factor, 3);
    CONTINUE WHEN v_base <= 0;
    v_unit_cost := public.jnum(v_item, 'price', 0) * v_k / v_factor;

    UPDATE products SET stock = stock + v_base, purchase_price = round(v_unit_cost, 2), updated_at = now()
    WHERE id = v_prod.id;
    INSERT INTO inventory_batches (product_id, purchase_id, quantity, remaining, purchase_price,
                                   batch_number, expiry_date, created_at)
    VALUES (v_prod.id, p_purchase.id, v_base, v_base, round(v_unit_cost, 4),
            nullif(v_item->>'batch_number', ''),
            CASE WHEN coalesce(v_item->>'expiry_date', '') ~ '^\d{4}-\d{2}-\d{2}' THEN left(v_item->>'expiry_date', 10)::date END,
            coalesce(p_purchase.created_at, now()));
    -- sold before this purchase was entered: those units come out of it
    PERFORM public.settle_stock_deficit(v_prod.id, v_prod.stock, v_base);
  END LOOP;
END $$;
REVOKE EXECUTE ON FUNCTION public.purchase_apply_items(public.purchases) FROM PUBLIC, anon, authenticated;

-- 5. purchase taken back out (edit of an old purchase / delete): net
--    position, no clamping (still refused once its stock was sold)
CREATE OR REPLACE FUNCTION public.purchase_reverse_items(p_purchase public.purchases) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b record; v_item jsonb; v_sold numeric;
BEGIN
  SELECT coalesce(sum(quantity - remaining), 0) INTO v_sold FROM inventory_batches WHERE purchase_id = p_purchase.id;
  IF v_sold > 0 THEN
    RAISE EXCEPTION 'Cannot change or delete this purchase: % unit(s) of its stock have already been sold or used', v_sold;
  END IF;
  IF EXISTS (SELECT 1 FROM inventory_batches WHERE purchase_id = p_purchase.id) THEN
    FOR b IN SELECT product_id, quantity FROM inventory_batches WHERE purchase_id = p_purchase.id FOR UPDATE LOOP
      UPDATE products SET stock = stock - b.quantity WHERE id = b.product_id;
    END LOOP;
    DELETE FROM inventory_batches WHERE purchase_id = p_purchase.id;
  ELSE
    -- old purchases synced from the offline queue never got batches
    FOR v_item IN SELECT * FROM jsonb_array_elements(coalesce(p_purchase.items, '[]'::jsonb)) LOOP
      BEGIN
        UPDATE products SET stock = stock - public.jnum(v_item, 'qty', 0)
        WHERE id = (v_item->>'product_id')::uuid;
      EXCEPTION WHEN invalid_text_representation THEN NULL;
      END;
    END LOOP;
  END IF;
END $$;
REVOKE EXECUTE ON FUNCTION public.purchase_reverse_items(public.purchases) FROM PUBLIC, anon, authenticated;

-- 6. purchase edited after a sale (2026_10_purchase_split.sql): more stock
--    first makes up a negative stock
CREATE OR REPLACE FUNCTION public.purchase_rebalance_items(p_old public.purchases, p_new public.purchases)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_gross numeric; v_k numeric; r record; b record; v_stock numeric;
  v_sold numeric; v_delta numeric; v_left numeric; v_take numeric; v_cost numeric;
BEGIN
  -- old purchases synced from the offline queue never got batches: the
  -- old take-out / put-back works for them (nothing to protect)
  IF NOT EXISTS (SELECT 1 FROM inventory_batches WHERE purchase_id = p_old.id) THEN
    PERFORM public.purchase_reverse_items(p_old);
    PERFORM public.purchase_apply_items(p_new);
    RETURN;
  END IF;

  -- bill discount / round-off spread over the lines (landed cost), as on create
  SELECT coalesce(sum(public.jnum(x, 'price', 0) * public.jnum(x, 'qty', 0)), 0)
    INTO v_gross FROM jsonb_array_elements(coalesce(p_new.items, '[]'::jsonb)) x;
  v_k := CASE WHEN v_gross > 0 AND coalesce(p_new.total_amount, 0) > 0
              THEN p_new.total_amount / v_gross ELSE 1 END;

  FOR r IN
    WITH n AS (
      SELECT p.id AS pid,
             sum(round(public.jnum(x, 'qty', 0) * public.item_stock_factor(x, p.unit_type), 3)) AS base,
             sum(public.jnum(x, 'price', 0) * public.jnum(x, 'qty', 0)) * v_k AS cost_total,
             min(nullif(x->>'batch_number', '')) AS batch_no,
             min(CASE WHEN coalesce(x->>'expiry_date', '') ~ '^\d{4}-\d{2}-\d{2}'
                      THEN left(x->>'expiry_date', 10)::date END) AS expiry
      FROM jsonb_array_elements(coalesce(p_new.items, '[]'::jsonb)) x
      JOIN products p ON p.id::text = x->>'product_id'
      GROUP BY p.id
    ), o AS (
      SELECT product_id AS pid, sum(quantity) AS q, sum(remaining) AS rem
      FROM inventory_batches WHERE purchase_id = p_old.id GROUP BY product_id
    )
    SELECT coalesce(n.pid, o.pid) AS pid, coalesce(n.base, 0) AS new_base, n.cost_total,
           n.batch_no, n.expiry, coalesce(o.q, 0) AS old_q, coalesce(o.rem, 0) AS old_rem,
           (SELECT name FROM products WHERE id = coalesce(n.pid, o.pid)) AS pname
    FROM n FULL JOIN o ON n.pid = o.pid
  LOOP
    SELECT stock INTO v_stock FROM products WHERE id = r.pid FOR UPDATE;
    v_sold := r.old_q - r.old_rem;
    IF r.new_base + 0.0005 < v_sold THEN
      RAISE EXCEPTION '%: % already sold from this purchase, so the quantity cannot go below that',
        coalesce(r.pname, 'A product'), round(v_sold, 3);
    END IF;
    v_cost := CASE WHEN r.new_base > 0 THEN r.cost_total / r.new_base END;
    v_delta := round(r.new_base - r.old_q, 3);

    IF r.old_q = 0 THEN
      -- a product added to the purchase
      CONTINUE WHEN r.new_base <= 0;
      INSERT INTO inventory_batches (product_id, purchase_id, quantity, remaining, purchase_price,
                                     batch_number, expiry_date, created_at)
      VALUES (r.pid, p_new.id, r.new_base, r.new_base, round(v_cost, 4), r.batch_no, r.expiry,
              coalesce(p_new.created_at, now()));
      UPDATE products SET stock = stock + r.new_base, purchase_price = round(v_cost, 2), updated_at = now()
      WHERE id = r.pid;
      PERFORM public.settle_stock_deficit(r.pid, v_stock, r.new_base);
      CONTINUE;
    END IF;

    IF v_delta > 0 THEN
      -- more of it: the newest batch of this purchase grows
      UPDATE inventory_batches SET quantity = quantity + v_delta, remaining = remaining + v_delta
      WHERE id = (SELECT id FROM inventory_batches WHERE purchase_id = p_old.id AND product_id = r.pid
                  ORDER BY created_at DESC, id DESC LIMIT 1);
    ELSIF v_delta < 0 THEN
      -- less of it: take it from the unsold part, newest batch first
      v_left := -v_delta;
      FOR b IN SELECT id, remaining FROM inventory_batches
               WHERE purchase_id = p_old.id AND product_id = r.pid
               ORDER BY created_at DESC, id DESC FOR UPDATE LOOP
        EXIT WHEN v_left <= 0;
        v_take := least(b.remaining, v_left);
        UPDATE inventory_batches SET quantity = quantity - v_take, remaining = remaining - v_take WHERE id = b.id;
        v_left := v_left - v_take;
      END LOOP;
      DELETE FROM inventory_batches
      WHERE purchase_id = p_old.id AND product_id = r.pid AND quantity <= 0.0005;
    END IF;

    IF v_delta <> 0 THEN
      UPDATE products SET stock = stock + v_delta, updated_at = now() WHERE id = r.pid;
      IF v_delta > 0 THEN PERFORM public.settle_stock_deficit(r.pid, v_stock, v_delta); END IF;
    END IF;

    -- the unsold units of this purchase carry the new landed cost
    IF r.new_base > 0 THEN
      UPDATE inventory_batches SET purchase_price = round(v_cost, 4)
      WHERE purchase_id = p_old.id AND product_id = r.pid;
      UPDATE products SET purchase_price = round(v_cost, 2), updated_at = now() WHERE id = r.pid;
    END IF;
  END LOOP;
END $$;
REVOKE EXECUTE ON FUNCTION public.purchase_rebalance_items(public.purchases, public.purchases) FROM PUBLIC, anon, authenticated;

-- 7. stock back from a sale (return, delete, edit): makes up a negative
--    stock first
CREATE OR REPLACE FUNCTION public.sale_restore_product(p_items jsonb, p_product uuid, p_base numeric,
  OUT items jsonb, OUT cost numeric, OUT restored numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  i int; a int; v_item jsonb; v_allocs jsonb; v_line_base numeric; v_ret numeric; v_avail numeric;
  v_take numeric; v_left numeric; v_aq numeric; v_t numeric; v_price numeric; v_unit_cost numeric;
  v_need numeric := p_base; v_stock numeric;
BEGIN
  items := coalesce(p_items, '[]'::jsonb); cost := 0; restored := 0;
  IF p_base <= 0 OR jsonb_array_length(items) = 0 THEN RETURN; END IF;
  SELECT stock INTO v_stock FROM products WHERE id = p_product FOR UPDATE;

  FOR i IN REVERSE jsonb_array_length(items) - 1 .. 0 LOOP
    EXIT WHEN v_need <= 0.0005;
    v_item := items -> i;
    CONTINUE WHEN (v_item->>'product_id') IS DISTINCT FROM p_product::text;
    v_line_base := public.item_base_qty(v_item);
    v_ret := public.jnum(v_item, 'returned_base', 0);
    v_avail := v_line_base - v_ret;
    CONTINUE WHEN v_avail <= 0;
    v_take := least(v_avail, v_need);
    v_unit_cost := CASE WHEN v_line_base > 0
                        THEN public.jnum(v_item, 'purchase_price', 0) * public.jnum(v_item, 'qty', 0) / v_line_base
                        ELSE 0 END;
    v_left := v_take;
    IF jsonb_typeof(v_item->'allocs') = 'array' THEN
      v_allocs := v_item->'allocs';
      FOR a IN REVERSE jsonb_array_length(v_allocs) - 1 .. 0 LOOP
        EXIT WHEN v_left <= 0;
        v_aq := public.jnum(v_allocs -> a, 'q', 0);
        CONTINUE WHEN v_aq <= 0;
        v_t := least(v_aq, v_left);
        v_price := public.jnum(v_allocs -> a, 'p', v_unit_cost);
        PERFORM public.restore_to_batch((v_allocs -> a ->> 'b')::uuid, p_product, v_t, v_price);
        cost := cost + v_t * v_price;
        v_left := v_left - v_t;
        v_allocs := jsonb_set(v_allocs, ARRAY[a::text, 'q'], to_jsonb(v_aq - v_t));
      END LOOP;
      v_item := jsonb_set(v_item, '{allocs}', v_allocs);
    END IF;
    IF v_left > 0 THEN                                   -- legacy line or short allocation
      PERFORM public.restore_stock_fifo(p_product, v_left, v_unit_cost);
      cost := cost + v_left * v_unit_cost;
    END IF;
    v_item := v_item || jsonb_build_object('returned_base', v_ret + v_take);
    items := jsonb_set(items, ARRAY[i::text], v_item);
    v_need := v_need - v_take;
    restored := restored + v_take;
  END LOOP;

  IF restored > 0 THEN
    UPDATE products SET stock = stock + restored WHERE id = p_product;
    PERFORM public.settle_stock_deficit(p_product, v_stock, restored);
  END IF;
END $$;
REVOKE EXECUTE ON FUNCTION public.sale_restore_product(jsonb, uuid, numeric) FROM PUBLIC, anon, authenticated;

-- 8. physical count: from a negative stock to the counted quantity
CREATE OR REPLACE FUNCTION public.reconcile_stock_with_batches(p_product_id uuid, p_physical_qty numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cur numeric; v_pp numeric; v_diff numeric; v_avg numeric;
BEGIN
  PERFORM public.assert_admin();
  IF p_physical_qty IS NULL OR p_physical_qty < 0 THEN RAISE EXCEPTION 'Stock cannot be negative'; END IF;
  SELECT stock, purchase_price INTO v_cur, v_pp FROM products WHERE id = p_product_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product not found: %', p_product_id; END IF;
  v_diff := p_physical_qty - v_cur;
  IF v_diff = 0 THEN RETURN; END IF;
  UPDATE products SET stock = p_physical_qty, updated_at = now() WHERE id = p_product_id;
  IF v_diff > 0 THEN
    -- quantity-weighted cost of what is on hand, else the product's cost
    SELECT sum(remaining * purchase_price) / nullif(sum(remaining), 0) INTO v_avg
    FROM inventory_batches WHERE product_id = p_product_id AND remaining > 0;
    PERFORM public.restore_stock_fifo(p_product_id, v_diff, coalesce(v_avg, v_pp, 0));
    PERFORM public.settle_stock_deficit(p_product_id, v_cur, v_diff);
  ELSE
    PERFORM public.fifo_take(p_product_id, -v_diff, 0);
  END IF;
END $$;
REVOKE EXECUTE ON FUNCTION public.reconcile_stock_with_batches(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reconcile_stock_with_batches(uuid, numeric) TO authenticated;

-- 9. Stock In while below zero (Stock Out still cannot go below zero)
CREATE OR REPLACE FUNCTION public.adjust_stock(p_product_id uuid, p_delta numeric)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cur numeric;
BEGIN
  PERFORM public.assert_admin();
  IF p_delta IS NULL OR p_delta = 0 THEN RAISE EXCEPTION 'Enter a quantity'; END IF;
  SELECT stock INTO v_cur FROM products WHERE id = p_product_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product not found' USING ERRCODE = 'P0002'; END IF;
  IF p_delta < 0 AND v_cur + p_delta < 0 THEN
    RAISE EXCEPTION 'Only % in stock — cannot remove %', v_cur, -p_delta;
  END IF;
  IF v_cur + p_delta >= 0 THEN
    PERFORM public.reconcile_stock_with_batches(p_product_id, v_cur + p_delta);
  ELSE
    -- still below zero after Stock In: every unit covers what was sold
    UPDATE products SET stock = stock + p_delta, updated_at = now() WHERE id = p_product_id;
  END IF;
  RETURN v_cur + p_delta;
END $$;
REVOKE EXECUTE ON FUNCTION public.adjust_stock(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.adjust_stock(uuid, numeric) TO authenticated;

-- 10. a damaged entry deleted while the stock is below zero
CREATE OR REPLACE FUNCTION public.delete_damaged_atomic(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE d record; v_stock numeric;
BEGIN
  PERFORM public.assert_admin();
  SELECT * INTO d FROM damaged_products WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;          -- already gone: nothing to undo

  IF d.product_id IS NOT NULL AND coalesce(d.quantity, 0) > 0 THEN
    SELECT stock INTO v_stock FROM products WHERE id = d.product_id FOR UPDATE;
    IF FOUND THEN
      UPDATE products SET stock = stock + d.quantity WHERE id = d.product_id;
      PERFORM public.restore_stock_fifo(d.product_id, d.quantity, d.unit_price);
      PERFORM public.settle_stock_deficit(d.product_id, v_stock, d.quantity);
    END IF;
  END IF;

  DELETE FROM damaged_products WHERE id = p_id;
END $$;
REVOKE EXECUTE ON FUNCTION public.delete_damaged_atomic(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_damaged_atomic(uuid) TO authenticated;

COMMIT;
