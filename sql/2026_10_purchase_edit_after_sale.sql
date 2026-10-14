-- =====================================================================
-- 2026_10_purchase_edit_after_sale.sql  —  edit a purchase after some of
-- its stock was sold
--
-- The owner could not add a forgotten item to a purchase, or fix a qty or
-- price, once ANY unit of that purchase had been sold (14 Oct 2026):
-- editing took the whole purchase's stock out and put it back, and the
-- database refused to take out stock that was already sold.
--
-- Now an edit changes only what changed, product by product:
--   * added items / higher qty  -> stock and batches go up
--   * lower qty                 -> allowed down to what is already sold;
--                                  below that: a clear message
--   * removed item              -> allowed only if none of it was sold
--   * new price / discount      -> the unsold stock of this purchase gets
--                                  the new landed cost (sold units keep the
--                                  cost they were sold at)
-- Deleting a whole purchase after its stock was sold stays blocked.
--
-- Also fixed: editing a split purchase that had a later supplier payment
-- treated that payment as unpaid again.
--
-- Needs 2026_10_purchase_split.sql (edit_purchase_atomic with the cash/UPI
-- amounts) to have been run first.
--
-- Apply in Supabase → SQL Editor: back up, run verify_schema.sql, run this
-- file, run verify_schema.sql again (check 20 must say OK).
-- Safe to run more than once.
-- =====================================================================
BEGIN;

-- Moves a purchase's stock from what p_old said to what p_new says,
-- touching only the products whose quantity or cost changed.
CREATE OR REPLACE FUNCTION public.purchase_rebalance_items(p_old public.purchases, p_new public.purchases)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_gross numeric; v_k numeric; r record; b record;
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
    PERFORM 1 FROM products WHERE id = r.pid FOR UPDATE;
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
      UPDATE products SET stock = greatest(stock + v_delta, 0), updated_at = now() WHERE id = r.pid;
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

-- same as 2026_10_purchase_split.sql, but stock moves by the difference
CREATE OR REPLACE FUNCTION public.edit_purchase_atomic(
  p_purchase_id uuid, p_items jsonb, p_total_amount numeric, p_supplier_id uuid,
  p_supplier_name text, p_is_credit boolean, p_amount_paid numeric, p_due_amount numeric,
  p_payment_method text, p_reason text, p_round_off numeric DEFAULT NULL,
  p_cash_amount numeric DEFAULT NULL, p_digital_amount numeric DEFAULT NULL)
RETURNS SETOF public.purchases
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE p public.purchases; n public.purchases; v_paid numeric; v_paid_later numeric; v_credit boolean; v_total numeric;
BEGIN
  PERFORM public.assert_admin();
  IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'Edit reason is required'; END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'A purchase needs at least one item';
  END IF;
  SELECT * INTO p FROM purchases WHERE id = p_purchase_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Purchase not found' USING ERRCODE = 'P0002'; END IF;

  PERFORM set_config('app.doc_rpc', 'on', true);

  v_total := greatest(round(coalesce(p_total_amount, 0), 2), 0);
  v_credit := coalesce(p_is_credit, false) OR public.norm_payment_method(p_payment_method) = 'credit';
  SELECT coalesce(sum(amount), 0) INTO v_paid_later FROM supplier_payments WHERE purchase_id = p_purchase_id;
  -- A split's cash + UPI is what was paid AT purchase time; payments made
  -- later (Pay button) come on top. Using the split alone as "paid" undid
  -- those later payments (due back up, cash/bank off by that much).
  v_paid := CASE
    WHEN v_credit AND coalesce(p_cash_amount, 0) + coalesce(p_digital_amount, 0) > 0.004
      THEN least(p_cash_amount + p_digital_amount + v_paid_later, v_total)
    WHEN v_credit THEN least(greatest(coalesce(p_amount_paid, 0), v_paid_later), v_total)
    ELSE v_total END;

  UPDATE purchases SET
    items = p_items, total_amount = v_total, supplier_id = p_supplier_id,
    supplier_name = coalesce(p_supplier_name, supplier_name), is_credit = v_credit,
    amount_paid = v_paid, due_amount = v_total - v_paid,
    paid_at_purchase = v_paid - CASE WHEN v_credit THEN v_paid_later ELSE 0 END,
    payment_method = p_payment_method, round_off = coalesce(p_round_off, round_off),
    cash_amount = coalesce(p_cash_amount, 0), digital_amount = coalesce(p_digital_amount, 0)
  WHERE id = p_purchase_id
  RETURNING * INTO n;

  -- only the difference moves (was: all out, all back in — refused once sold)
  PERFORM public.purchase_rebalance_items(p, n);

  INSERT INTO transaction_edits (transaction_type, transaction_id, reason, old_data, new_data, edited_by)
  VALUES ('purchase', p_purchase_id, p_reason, to_jsonb(p), to_jsonb(n), auth.uid());
  PERFORM set_config('app.doc_rpc', 'off', true);
  RETURN QUERY SELECT * FROM purchases WHERE id = p_purchase_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.edit_purchase_atomic(uuid, jsonb, numeric, uuid, text, boolean, numeric, numeric, text, text, numeric, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.edit_purchase_atomic(uuid, jsonb, numeric, uuid, text, boolean, numeric, numeric, text, text, numeric, numeric, numeric) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
