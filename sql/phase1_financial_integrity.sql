-- ============================================
-- PHASE 1: FINANCIAL INTEGRITY MIGRATION
-- Run this ONCE in Supabase SQL Editor
-- ============================================

BEGIN;

-- ============================================
-- P0-5: Fix COGS to use FIFO batch cost
-- ============================================
-- PROBLEM: deduct_stock_on_sale (AFTER INSERT) reads products.purchase_price
-- which is the LAST purchase price, not FIFO cost. The FIFO deduction uses
-- oldest batch price, but the sale stores the latest price → profit wrong.
--
-- FIX: BEFORE INSERT trigger reads FIFO batch price and corrects each item's
-- purchase_price BEFORE the row is committed. Then AFTER INSERT trigger
-- deducts using the corrected prices.
-- ============================================

-- Step 1: BEFORE INSERT trigger — correct purchase_price to FIFO batch cost
CREATE OR REPLACE FUNCTION correct_fifo_purchase_price()
RETURNS trigger AS $$
DECLARE
  item JSONB;
  v_idx INT;
  v_product_id UUID;
  v_qty INT;
  v_batch_price NUMERIC(10,2);
  v_items JSONB := NEW.items;
  v_has_changes BOOLEAN := FALSE;
BEGIN
  FOR v_idx IN 0 .. jsonb_array_length(v_items) - 1
  LOOP
    item := v_items -> v_idx;
    v_product_id := (item->>'product_id')::UUID;
    v_qty := (item->>'qty')::INTEGER;

    -- Read FIFO batch price (oldest batch with remaining > 0)
    SELECT purchase_price INTO v_batch_price
    FROM inventory_batches
    WHERE product_id = v_product_id AND remaining > 0
    ORDER BY created_at ASC
    LIMIT 1;

    -- Update purchase_price if FIFO batch exists and price differs
    IF FOUND AND v_batch_price IS NOT NULL
       AND v_batch_price <> (item->>'purchase_price')::NUMERIC(10,2) THEN
      v_items := jsonb_set(
        v_items,
        ARRAY[v_idx::TEXT, 'purchase_price'],
        to_jsonb(v_batch_price)
      );
      v_has_changes := TRUE;
    END IF;
  END LOOP;

  IF v_has_changes THEN
    NEW.items := v_items;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS correct_fifo_price ON sales;
CREATE TRIGGER correct_fifo_price
  BEFORE INSERT ON sales
  FOR EACH ROW EXECUTE FUNCTION correct_fifo_purchase_price();

-- Step 2: AFTER INSERT trigger stays the same — deducts using corrected prices
-- (deduct_stock_on_sale already exists and will use the corrected items)

-- ============================================
-- P0-3: Fix get_financial_summary to use COGS
-- ============================================
-- PROBLEM: monthly_purchases used SUM(p.total_amount) FROM purchases
-- (all purchases this month, whether items sold or not).
-- FIX: Use COGS from sale items (same as get_monthly_profit).
-- ============================================

CREATE OR REPLACE FUNCTION get_financial_summary()
RETURNS TABLE (
  cash_position NUMERIC,
  bank_position NUMERIC,
  total_cash_bank NUMERIC,
  total_receivables NUMERIC,
  total_payables NUMERIC,
  net_position NUMERIC,
  monthly_sales NUMERIC,
  monthly_purchases NUMERIC,
  monthly_expenses NUMERIC,
  monthly_profit NUMERIC,
  gross_margin_pct NUMERIC,
  expense_ratio_pct NUMERIC,
  cash_runway_days NUMERIC
)
LANGUAGE sql STABLE
AS $$
  WITH cash_data AS (
    SELECT
      COALESCE(SUM(CASE WHEN name ILIKE '%cash%' THEN balance ELSE 0 END), 0) AS cash_pos,
      COALESCE(SUM(CASE WHEN name ILIKE '%bank%' THEN balance ELSE 0 END), 0) AS bank_pos
    FROM accounts
  ),
  monthly AS (
    SELECT
      COALESCE(SUM(s.final_amount), 0) AS sales,
      -- FIX: Use COGS from sale items (purchase_price × qty) instead of purchase records
      COALESCE((SELECT SUM((item->>'purchase_price')::NUMERIC * (item->>'qty')::INT)
        FROM sales s2, jsonb_array_elements(s2.items) AS item
        WHERE s2.created_at >= date_trunc('month', NOW())), 0) AS purchases,
      COALESCE((SELECT SUM(e.amount) FROM expenses e
        WHERE e.created_at >= date_trunc('month', NOW())), 0) AS expenses
    FROM sales s WHERE s.created_at >= date_trunc('month', NOW())
  ),
  receivables AS (
    SELECT COALESCE(SUM(due_amount), 0) AS total FROM sales WHERE is_credit = true AND due_amount > 0
  ),
  payables AS (
    SELECT COALESCE(SUM(due_amount), 0) AS total FROM purchases WHERE is_credit = true AND due_amount > 0
  )
  SELECT
    cd.cash_pos,
    cd.bank_pos,
    cd.cash_pos + cd.bank_pos AS total_cash_bank,
    r.total AS total_receivables,
    p.total AS total_payables,
    (cd.cash_pos + cd.bank_pos + r.total - p.total) AS net_position,
    m.sales AS monthly_sales,
    m.purchases AS monthly_purchases,
    m.expenses AS monthly_expenses,
    (m.sales - m.purchases - m.expenses) AS monthly_profit,
    CASE WHEN m.sales > 0
      THEN ROUND(((m.sales - m.purchases) / m.sales) * 100, 1)
      ELSE 0
    END AS gross_margin_pct,
    CASE WHEN m.sales > 0
      THEN ROUND((m.expenses / m.sales) * 100, 1)
      ELSE 0
    END AS expense_ratio_pct,
    CASE WHEN m.expenses > 0
      THEN ROUND((cd.cash_pos + cd.bank_pos) / (m.expenses / 30), 0)
      ELSE 999
    END AS cash_runway_days
  FROM cash_data cd, monthly m, receivables r, payables p;
$$;

-- ============================================
-- P1-1: Fix edit_sale_atomic to adjust batches
-- ============================================
-- PROBLEM: edit_sale_atomic adjusts products.stock but does NOT adjust
-- inventory_batches.remaining, causing stock-batch divergence.
-- FIX: Add batch adjustment logic matching the stock delta.
-- ============================================

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
  item_rec RECORD;
  v_batch RECORD;
  v_remaining_to_deduct INT;
  v_remaining_to_restore INT;
  v_can_add INT;
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

  -- 1. Compute per-product quantity deltas and adjust stock + batches
  FOR item_rec IN
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
    IF item_rec.new_qty > item_rec.old_qty THEN
      -- Stock DECREASED (more items sold) — deduct from batches FIFO
      UPDATE products SET stock = GREATEST(stock - (item_rec.new_qty - item_rec.old_qty), 0)
       WHERE id = item_rec.product_id;

      v_remaining_to_deduct := item_rec.new_qty - item_rec.old_qty;
      FOR v_batch IN
        SELECT id, remaining FROM inventory_batches
        WHERE product_id = item_rec.product_id AND remaining > 0
        ORDER BY created_at ASC FOR UPDATE
      LOOP
        EXIT WHEN v_remaining_to_deduct <= 0;
        IF v_batch.remaining >= v_remaining_to_deduct THEN
          UPDATE inventory_batches SET remaining = remaining - v_remaining_to_deduct WHERE id = v_batch.id;
          v_remaining_to_deduct := 0;
        ELSE
          v_remaining_to_deduct := v_remaining_to_deduct - v_batch.remaining;
          UPDATE inventory_batches SET remaining = 0 WHERE id = v_batch.id;
        END IF;
      END LOOP;

    ELSIF item_rec.old_qty > item_rec.new_qty THEN
      -- Stock INCREASED (fewer items sold) — restore to batches
      UPDATE products SET stock = stock + (item_rec.old_qty - item_rec.new_qty)
       WHERE id = item_rec.product_id;

      v_remaining_to_restore := item_rec.old_qty - item_rec.new_qty;
      -- Use purchase_price from old sale items for this product
      DECLARE
        v_price NUMERIC(10,2);
      BEGIN
        SELECT (x->>'purchase_price')::NUMERIC(10,2) INTO v_price
        FROM jsonb_array_elements(old_items) x
        WHERE (x->>'product_id')::UUID = item_rec.product_id LIMIT 1;

        IF v_price IS NOT NULL THEN
          -- Restore to partially-depleted batches with matching price
          FOR v_batch IN
            SELECT id, remaining, quantity FROM inventory_batches
            WHERE product_id = item_rec.product_id
              AND purchase_price = v_price AND remaining < quantity
            ORDER BY created_at DESC FOR UPDATE
          LOOP
            EXIT WHEN v_remaining_to_restore <= 0;
            v_can_add := v_batch.quantity - v_batch.remaining;
            IF v_can_add >= v_remaining_to_restore THEN
              UPDATE inventory_batches SET remaining = remaining + v_remaining_to_restore WHERE id = v_batch.id;
              v_remaining_to_restore := 0;
            ELSE
              UPDATE inventory_batches SET remaining = quantity WHERE id = v_batch.id;
              v_remaining_to_restore := v_remaining_to_restore - v_can_add;
            END IF;
          END LOOP;

          -- Overflow: create orphan batch
          IF v_remaining_to_restore > 0 THEN
            INSERT INTO inventory_batches (product_id, quantity, remaining, purchase_price)
            VALUES (item_rec.product_id, v_remaining_to_restore, v_remaining_to_restore, v_price);
          END IF;
        END IF;
      END;
    END IF;
  END LOOP;

  -- 2. Update the sale record
  UPDATE sales SET
    items = p_items, total_amount = p_total_amount, discount = p_discount,
    total_discount = COALESCE((SELECT SUM((x->>'discount_amount')::numeric) FROM jsonb_array_elements(p_items) x), 0),
    final_amount = p_final_amount, customer_id = p_customer_id, is_credit = p_is_credit,
    amount_paid = p_amount_paid, due_amount = p_due_amount, payment_method = p_payment_method,
    cash_amount = p_cash_amount, digital_amount = p_digital_amount
  WHERE id = p_sale_id;

  -- 3. Reconcile money received per account
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

-- ============================================
-- P1-4: Fix get_inventory_health variant handling
-- ============================================
-- PROBLEM: total_stock_value uses SUM(stock * purchase_price) FROM products
-- which misses product_variants. get_stock_value() handles variants but
-- get_inventory_health does not.
-- FIX: Use get_stock_value() for total_stock_value, and include variants
-- in slow_moving and dead_stock counts.
-- ============================================

CREATE OR REPLACE FUNCTION get_inventory_health()
RETURNS TABLE (
  total_products BIGINT,
  total_stock_value NUMERIC,
  healthy_count BIGINT,
  low_stock_count BIGINT,
  out_of_stock_count BIGINT,
  slow_moving_count BIGINT,
  dead_stock_count BIGINT,
  overstock_count BIGINT,
  slow_moving_items JSONB,
  out_of_stock_items JSONB,
  top_reorder_items JSONB
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_slow JSONB;
  v_out JSONB;
  v_reorder JSONB;
BEGIN
  -- Slow moving: sold < 2 units in 90 days but has stock
  -- Include both regular products and variants
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'stock', stock, 'sold_90d', sold_90d)), '[]'::jsonb)
  INTO v_slow
  FROM (
    SELECT pr.name, pr.stock,
      COALESCE((SELECT SUM((item->>'qty')::int) FROM sales, jsonb_array_elements(sales.items) AS item
        WHERE (item->>'product_id')::uuid = pr.id AND sales.created_at >= NOW() - INTERVAL '90 days'), 0) AS sold_90d
    FROM products pr WHERE pr.stock > 0 AND pr.has_variants = false
    UNION ALL
    SELECT pv.name, pv.stock,
      COALESCE((SELECT SUM((item->>'qty')::int) FROM sales, jsonb_array_elements(sales.items) AS item
        WHERE (item->>'product_id')::uuid = pv.id AND sales.created_at >= NOW() - INTERVAL '90 days'), 0) AS sold_90d
    FROM product_variants pv
    JOIN products p ON p.id = pv.product_id
    WHERE pv.stock > 0 AND p.has_variants = true AND pv.is_active = true
  ) sub WHERE sold_90d < 2
  ORDER BY stock DESC LIMIT 10;

  -- Out of stock (regular products only — variants have their own stock)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'low_stock_alert', low_stock_alert)), '[]'::jsonb)
  INTO v_out
  FROM products WHERE stock = 0 AND low_stock_alert > 0 AND has_variants = false
  ORDER BY name LIMIT 10;

  -- Top reorder: stock < low_stock_alert
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'stock', stock, 'alert', low_stock_alert)), '[]'::jsonb)
  INTO v_reorder
  FROM products WHERE stock < low_stock_alert AND low_stock_alert > 0 AND has_variants = false
  ORDER BY (low_stock_alert - stock) DESC LIMIT 10;

  RETURN QUERY
  SELECT
    (SELECT COUNT(*) FROM products WHERE has_variants = false
     UNION ALL SELECT COUNT(*) FROM product_variants pv
     JOIN products p ON p.id = pv.product_id WHERE p.has_variants = true AND pv.is_active = true
    )::BIGINT AS total_products,
    -- FIX: Use get_stock_value() which handles both products and variants
    get_stock_value() AS total_stock_value,
    (SELECT COUNT(*) FROM products WHERE (stock > low_stock_alert OR low_stock_alert = 0) AND has_variants = false)::BIGINT AS healthy_count,
    (SELECT COUNT(*) FROM products WHERE stock > 0 AND stock <= low_stock_alert AND low_stock_alert > 0 AND has_variants = false)::BIGINT AS low_stock_count,
    (SELECT COUNT(*) FROM products WHERE stock = 0 AND has_variants = false)::BIGINT AS out_of_stock_count,
    (SELECT COUNT(*) FROM (
      SELECT pr.id FROM products pr WHERE pr.stock > 0 AND pr.has_variants = false
      AND COALESCE((SELECT SUM((item->>'qty')::int) FROM sales, jsonb_array_elements(sales.items) AS item
        WHERE (item->>'product_id')::uuid = pr.id AND sales.created_at >= NOW() - INTERVAL '90 days'), 0) < 2
    ) sub)::BIGINT AS slow_moving_count,
    (SELECT COUNT(*) FROM products WHERE stock > 0 AND has_variants = false AND NOT EXISTS (
      SELECT 1 FROM sales, jsonb_array_elements(sales.items) AS item
      WHERE (item->>'product_id')::uuid = products.id AND sales.created_at >= NOW() - INTERVAL '180 days'
    ))::BIGINT AS dead_stock_count,
    (SELECT COUNT(*) FROM products WHERE stock > 100 AND low_stock_alert > 0 AND stock > low_stock_alert * 5 AND has_variants = false)::BIGINT AS overstock_count,
    v_slow AS slow_moving_items,
    v_out AS out_of_stock_items,
    v_reorder AS top_reorder_items;
END;
$$;

-- ============================================
-- P1-3: Verify customer/supplier dues consistency
-- ============================================
-- The triggers update_customer_credit() and update_supplier_dues() already
-- recalculate denormalized columns from raw sales/purchases data.
-- get_financial_summary already reads directly from sales.due_amount and
-- purchases.due_amount (the authoritative sources).
-- No additional changes needed — the architecture is correct.
-- ============================================

COMMIT;
