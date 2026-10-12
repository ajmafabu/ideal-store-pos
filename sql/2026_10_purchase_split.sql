-- =====================================================================
-- 2026_10_purchase_split.sql  —  pay a supplier bill partly cash, partly UPI
--
-- Sales could already be split between cash and UPI; purchases could not:
-- a purchase was paid from ONE place (cash, or UPI/bank, or credit). The
-- owner asked for Cash / UPI / Split / Credit on the purchase screen too
-- (12 Oct 2026).
--
-- What changes:
--   * purchases.cash_amount / purchases.digital_amount: how the money paid
--     at purchase time was split. Both 0 = the old way (payment_method
--     decides the account).
--   * purchases_before_write keeps the two amounts consistent with what was
--     paid at purchase (UPI part never more than paid; cash = the rest).
--   * purchase_postings uses them, so the cash book gets the cash part and
--     the bank book the UPI part (the same money_split rule as sales).
--   * edit_purchase_atomic takes p_cash_amount / p_digital_amount (both
--     optional: older apps that do not send them keep working).
--
-- Apply in Supabase → SQL Editor: back up, run verify_schema.sql, run this
-- file, run verify_schema.sql again (check 19 must say OK).
-- Safe to run more than once. If 2026_10_audit_fixes.sql is ever run again,
-- run this file again after it.
-- =====================================================================
BEGIN;

ALTER TABLE purchases ADD COLUMN IF NOT EXISTS cash_amount NUMERIC(12,2) DEFAULT 0;
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS digital_amount NUMERIC(12,2) DEFAULT 0;

CREATE OR REPLACE FUNCTION public.purchases_before_write() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t record; v_paid_now numeric;
BEGIN
  IF public.app_bulk_mode() THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND NEW.items IS DISTINCT FROM OLD.items
     AND coalesce(current_setting('app.doc_rpc', true), '') <> 'on' THEN
    RAISE EXCEPTION 'Purchase items can only be changed with edit_purchase_atomic';
  END IF;
  NEW.payment_method := public.norm_payment_method(NEW.payment_method);
  NEW.total_amount := greatest(round(coalesce(NEW.total_amount, 0), 2), 0);
  NEW.is_credit := coalesce(NEW.is_credit, false) OR NEW.payment_method = 'credit';
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := coalesce(auth.uid(), NEW.created_by);
    IF NEW.is_credit THEN
      NEW.amount_paid := least(greatest(coalesce(NEW.amount_paid, 0), 0), NEW.total_amount);
      NEW.due_amount := NEW.total_amount - NEW.amount_paid;
      NEW.due_date := coalesce(NEW.due_date, public.ist_today() + 30);
    ELSE
      NEW.amount_paid := NEW.total_amount;
      NEW.due_amount := 0;
    END IF;
    NEW.paid_at_purchase := coalesce(NEW.paid_at_purchase, NEW.amount_paid);
  END IF;

  -- cash / UPI split of the money paid at purchase time
  NEW.cash_amount := greatest(coalesce(NEW.cash_amount, 0), 0);
  NEW.digital_amount := greatest(coalesce(NEW.digital_amount, 0), 0);
  IF NEW.cash_amount + NEW.digital_amount > 0.004 THEN
    v_paid_now := greatest(coalesce(NEW.paid_at_purchase,
                    CASE WHEN NEW.is_credit THEN NEW.amount_paid ELSE NEW.total_amount END, 0), 0);
    NEW.digital_amount := round(least(NEW.digital_amount, v_paid_now), 2);
    NEW.cash_amount := round(v_paid_now - NEW.digital_amount, 2);
  END IF;

  -- money paid at purchase time goes out of cash/bank, never "credit"
  IF NEW.payment_method IN ('credit','split') THEN NEW.payment_method := 'cash'; END IF;
  SELECT * INTO t FROM public.purchase_compute_itc(NEW);
  NEW.cgst_amount := t.cgst; NEW.sgst_amount := t.sgst; NEW.igst_amount := t.igst; NEW.taxable_amount := t.taxable;
  NEW.due_amount := greatest(coalesce(NEW.due_amount, 0), 0);
  NEW.updated_at := now();
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.purchase_postings(p public.purchases) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.money_split(
    coalesce(p.paid_at_purchase, CASE WHEN p.is_credit THEN p.amount_paid ELSE p.total_amount END),
    p.cash_amount, p.digital_amount, p.payment_method, -1)
$$;

-- old signature (11 arguments) → new one with two optional amounts
DROP FUNCTION IF EXISTS public.edit_purchase_atomic(uuid, jsonb, numeric, uuid, text, boolean, numeric, numeric, text, text, numeric);

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
  PERFORM public.purchase_reverse_items(p);

  v_total := greatest(round(coalesce(p_total_amount, 0), 2), 0);
  v_credit := coalesce(p_is_credit, false) OR public.norm_payment_method(p_payment_method) = 'credit';
  SELECT coalesce(sum(amount), 0) INTO v_paid_later FROM supplier_payments WHERE purchase_id = p_purchase_id;
  v_paid := CASE WHEN v_credit THEN least(greatest(coalesce(p_amount_paid, 0), v_paid_later), v_total) ELSE v_total END;

  UPDATE purchases SET
    items = p_items, total_amount = v_total, supplier_id = p_supplier_id,
    supplier_name = coalesce(p_supplier_name, supplier_name), is_credit = v_credit,
    amount_paid = v_paid, due_amount = v_total - v_paid,
    paid_at_purchase = v_paid - CASE WHEN v_credit THEN v_paid_later ELSE 0 END,
    payment_method = p_payment_method, round_off = coalesce(p_round_off, round_off),
    -- not sent (older app) = not a split: the method decides the account
    cash_amount = coalesce(p_cash_amount, 0), digital_amount = coalesce(p_digital_amount, 0)
  WHERE id = p_purchase_id
  RETURNING * INTO n;

  PERFORM public.purchase_apply_items(n);

  INSERT INTO transaction_edits (transaction_type, transaction_id, reason, old_data, new_data, edited_by)
  VALUES ('purchase', p_purchase_id, p_reason, to_jsonb(p), to_jsonb(n), auth.uid());
  PERFORM set_config('app.doc_rpc', 'off', true);
  RETURN QUERY SELECT * FROM purchases WHERE id = p_purchase_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.edit_purchase_atomic(uuid, jsonb, numeric, uuid, text, boolean, numeric, numeric, text, text, numeric, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.edit_purchase_atomic(uuid, jsonb, numeric, uuid, text, boolean, numeric, numeric, text, text, numeric, numeric, numeric) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.purchase_postings(public.purchases) FROM PUBLIC, anon;

NOTIFY pgrst, 'reload schema';

COMMIT;
