-- Safe transaction editing RPCs
-- Run after transaction_edit_migration.sql.

CREATE OR REPLACE FUNCTION public.edit_sale_atomic(
  p_sale_id UUID,
  p_items JSONB,
  p_total_amount NUMERIC,
  p_discount NUMERIC,
  p_final_amount NUMERIC,
  p_customer_id UUID,
  p_is_credit BOOLEAN,
  p_amount_paid NUMERIC,
  p_due_amount NUMERIC,
  p_payment_method TEXT,
  p_cash_amount NUMERIC,
  p_digital_amount NUMERIC,
  p_reason TEXT
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  old_sale JSONB;
  old_items JSONB;
  old_cash NUMERIC;
  old_digital NUMERIC;
  old_credit BOOLEAN;
  old_method TEXT;
  old_customer UUID;
  old_paid NUMERIC;
  old_due NUMERIC;
  account RECORD;
  delta NUMERIC;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin permission required'; END IF;
  IF COALESCE(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'Edit reason is required'; END IF;

  SELECT to_jsonb(s), s.items, COALESCE(s.cash_amount, 0), COALESCE(s.digital_amount, 0),
         COALESCE(s.is_credit, false), COALESCE(s.payment_method, 'cash'), s.customer_id,
         COALESCE(s.amount_paid, 0), COALESCE(s.due_amount, 0)
    INTO old_sale, old_items, old_cash, old_digital, old_credit, old_method,
         old_customer, old_paid, old_due
  FROM sales s WHERE s.id = p_sale_id FOR UPDATE;
  IF old_sale IS NULL THEN RAISE EXCEPTION 'Sale not found'; END IF;

  -- Restore/reduce or deduct/increase stock by product quantity difference.
  FOR account IN
    SELECT COALESCE(o.product_id, n.product_id) AS product_id,
           COALESCE(o.qty, 0) AS old_qty, COALESCE(n.qty, 0) AS new_qty
    FROM (
      SELECT (x->>'product_id')::uuid product_id, SUM((x->>'qty')::int) qty
      FROM jsonb_array_elements(old_items) x GROUP BY 1
    ) o FULL JOIN (
      SELECT (x->>'product_id')::uuid product_id, SUM((x->>'qty')::int) qty
      FROM jsonb_array_elements(p_items) x GROUP BY 1
    ) n USING (product_id)
  LOOP
    IF account.new_qty > account.old_qty THEN
      UPDATE products SET stock = GREATEST(stock - (account.new_qty - account.old_qty), 0)
       WHERE id = account.product_id;
    ELSIF account.old_qty > account.new_qty THEN
      UPDATE products SET stock = stock + (account.old_qty - account.new_qty)
       WHERE id = account.product_id;
    END IF;
  END LOOP;

  UPDATE sales SET
    items = p_items, total_amount = p_total_amount, discount = p_discount,
    total_discount = COALESCE((SELECT SUM((x->>'discount_amount')::numeric) FROM jsonb_array_elements(p_items) x), 0),
    final_amount = p_final_amount, customer_id = p_customer_id, is_credit = p_is_credit,
    amount_paid = p_amount_paid, due_amount = p_due_amount, payment_method = p_payment_method,
    cash_amount = p_cash_amount, digital_amount = p_digital_amount
  WHERE id = p_sale_id;

  -- Reconcile money received per account. Credit sales contribute no cash/digital amount.
  FOR account IN SELECT id, account_type FROM accounts WHERE account_type IN ('cash', 'bank') LOOP
    IF account.account_type = 'cash' THEN
      delta := COALESCE(p_cash_amount, 0) - old_cash;
    ELSE
      delta := COALESCE(p_digital_amount, 0) - old_digital;
    END IF;
    IF delta > 0 THEN
      PERFORM add_account_transaction(account.id, 'in', delta, 'sale_edit', p_reason, auth.uid());
    ELSIF delta < 0 THEN
      PERFORM add_account_transaction(account.id, 'out', abs(delta), 'sale_edit', p_reason, auth.uid());
    END IF;
  END LOOP;

  INSERT INTO transaction_edits(transaction_type, transaction_id, reason, old_data, new_data, edited_by)
  VALUES ('sale', p_sale_id, p_reason, old_sale,
          jsonb_build_object('items', p_items, 'total_amount', p_total_amount, 'final_amount', p_final_amount,
                             'customer_id', p_customer_id, 'is_credit', p_is_credit, 'amount_paid', p_amount_paid,
                             'due_amount', p_due_amount, 'payment_method', p_payment_method), auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.edit_purchase_atomic(
  p_purchase_id UUID,
  p_items JSONB,
  p_total_amount NUMERIC,
  p_supplier_id UUID,
  p_supplier_name TEXT,
  p_is_credit BOOLEAN,
  p_amount_paid NUMERIC,
  p_due_amount NUMERIC,
  p_payment_method TEXT,
  p_reason TEXT
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  old_purchase JSONB;
  old_items JSONB;
  old_total NUMERIC;
  old_credit BOOLEAN;
  old_method TEXT;
  account RECORD;
  delta NUMERIC;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin permission required'; END IF;
  IF COALESCE(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'Edit reason is required'; END IF;

  SELECT to_jsonb(p), p.items, p.total_amount, COALESCE(p.is_credit, false), COALESCE(p.payment_method, 'cash')
    INTO old_purchase, old_items, old_total, old_credit, old_method
  FROM purchases p WHERE p.id = p_purchase_id FOR UPDATE;
  IF old_purchase IS NULL THEN RAISE EXCEPTION 'Purchase not found'; END IF;

  IF EXISTS (SELECT 1 FROM inventory_batches WHERE purchase_id = p_purchase_id AND remaining <> quantity) THEN
    RAISE EXCEPTION 'Cannot edit purchase after its stock batches were partially sold';
  END IF;

  FOR account IN
    SELECT COALESCE(o.product_id, n.product_id) AS product_id,
           COALESCE(o.qty, 0) AS old_qty, COALESCE(n.qty, 0) AS new_qty
    FROM (
      SELECT (x->>'product_id')::uuid product_id, SUM((x->>'qty')::int) qty
      FROM jsonb_array_elements(old_items) x GROUP BY 1
    ) o FULL JOIN (
      SELECT (x->>'product_id')::uuid product_id, SUM((x->>'qty')::int) qty
      FROM jsonb_array_elements(p_items) x GROUP BY 1
    ) n USING (product_id)
  LOOP
    IF account.new_qty > account.old_qty THEN
      UPDATE products SET stock = stock + (account.new_qty - account.old_qty) WHERE id = account.product_id;
    ELSIF account.old_qty > account.new_qty THEN
      UPDATE products SET stock = GREATEST(stock - (account.old_qty - account.new_qty), 0) WHERE id = account.product_id;
    END IF;
  END LOOP;

  DELETE FROM inventory_batches WHERE purchase_id = p_purchase_id;
  INSERT INTO inventory_batches(product_id, purchase_id, quantity, remaining, purchase_price, batch_number, expiry_date)
  SELECT (x->>'product_id')::uuid, p_purchase_id, (x->>'qty')::int, (x->>'qty')::int,
         (x->>'price')::numeric, x->>'batch_number', NULLIF(x->>'expiry_date', '')::date
  FROM jsonb_array_elements(p_items) x;

  UPDATE purchases SET items = p_items, total_amount = p_total_amount, supplier_id = p_supplier_id,
    supplier_name = p_supplier_name, is_credit = p_is_credit, amount_paid = p_amount_paid,
    due_amount = p_due_amount, payment_method = p_payment_method
  WHERE id = p_purchase_id;

  FOR account IN SELECT id, account_type FROM accounts WHERE account_type IN ('cash', 'bank') LOOP
    -- Purchase money is an account outflow. Positive delta means additional outflow.
    delta := CASE WHEN account.account_type = 'bank' AND p_payment_method IN ('upi', 'digital', 'bank')
                  THEN p_total_amount - CASE WHEN old_method IN ('upi', 'digital', 'bank') THEN old_total ELSE 0 END
                  ELSE p_total_amount - CASE WHEN old_method NOT IN ('upi', 'digital', 'bank') THEN old_total ELSE 0 END END;
    IF delta > 0 THEN
      PERFORM add_account_transaction(account.id, 'out', delta, 'purchase_edit', p_reason, auth.uid());
    ELSIF delta < 0 THEN
      PERFORM add_account_transaction(account.id, 'in', abs(delta), 'purchase_edit', p_reason, auth.uid());
    END IF;
  END LOOP;

  INSERT INTO transaction_edits(transaction_type, transaction_id, reason, old_data, new_data, edited_by)
  VALUES ('purchase', p_purchase_id, p_reason, old_purchase,
          jsonb_build_object('items', p_items, 'total_amount', p_total_amount, 'supplier_id', p_supplier_id,
                             'supplier_name', p_supplier_name, 'is_credit', p_is_credit,
                             'amount_paid', p_amount_paid, 'due_amount', p_due_amount,
                             'payment_method', p_payment_method), auth.uid());
END;
$$;
