-- ============================================
-- SALES + FULL PROJECT FIX MIGRATION (v1.0.5)
-- Run this ONCE in: Supabase Dashboard → SQL Editor
-- ============================================

-- 1. ADD MISSING COLUMNS TO SALES TABLE
-- The app sends these fields; without them the INSERT fails
-- and every sale gets stuck in the offline pending queue.
-- ============================================

ALTER TABLE sales ADD COLUMN IF NOT EXISTS total_discount NUMERIC(10,2) DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS cash_amount NUMERIC(10,2) DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS digital_amount NUMERIC(10,2) DEFAULT 0;

-- 2. STOCK FUNCTIONS → SECURITY DEFINER
-- Without SECURITY DEFINER the trigger runs with the caller's RLS
-- privileges. Staff only have SELECT on products, so the trigger's
-- UPDATE silently affects 0 rows → stock never deducted for staff sales.
-- ============================================

CREATE OR REPLACE FUNCTION deduct_stock_fifo(
  p_product_id UUID,
  p_qty INTEGER
)
RETURNS void AS $$
DECLARE
  remaining_to_deduct INTEGER := p_qty;
  batch RECORD;
BEGIN
  FOR batch IN
    SELECT id, remaining
    FROM inventory_batches
    WHERE product_id = p_product_id AND remaining > 0
    ORDER BY created_at ASC
  LOOP
    EXIT WHEN remaining_to_deduct <= 0;

    IF batch.remaining >= remaining_to_deduct THEN
      UPDATE inventory_batches SET remaining = remaining - remaining_to_deduct WHERE id = batch.id;
      remaining_to_deduct := 0;
    ELSE
      remaining_to_deduct := remaining_to_deduct - batch.remaining;
      UPDATE inventory_batches SET remaining = 0 WHERE id = batch.id;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION deduct_stock_on_sale()
RETURNS trigger AS $$
DECLARE
  item JSONB;
BEGIN
  FOR item IN SELECT * FROM jsonb_array_elements(NEW.items)
  LOOP
    -- Deduct from product total
    UPDATE products
    SET stock = GREATEST(stock - (item->>'qty')::INTEGER, 0)
    WHERE id = (item->>'product_id')::UUID;

    -- Deduct FIFO from batches
    PERFORM deduct_stock_fifo(
      (item->>'product_id')::UUID,
      (item->>'qty')::INTEGER
    );
  END LOOP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION decrement_stock(p_product_id UUID, p_qty INTEGER)
RETURNS void AS $$
BEGIN
  UPDATE products
  SET stock = GREATEST(stock - p_qty, 0)
  WHERE id = p_product_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION increment_stock(p_product_id UUID, p_qty INTEGER)
RETURNS void AS $$
BEGIN
  UPDATE products
  SET stock = stock + p_qty
  WHERE id = p_product_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION restore_stock_fifo(
  p_product_id UUID,
  p_qty INTEGER,
  p_price NUMERIC(10,2)
)
RETURNS void AS $$
DECLARE
  remaining_to_restore INTEGER := p_qty;
  batch RECORD;
BEGIN
  FOR batch IN
    SELECT id, remaining, quantity
    FROM inventory_batches
    WHERE product_id = p_product_id AND purchase_price = p_price AND remaining < quantity
    ORDER BY created_at DESC
  LOOP
    EXIT WHEN remaining_to_restore <= 0;

    DECLARE
      can_add INTEGER;
    BEGIN
      can_add := batch.quantity - batch.remaining;
      IF can_add >= remaining_to_restore THEN
        UPDATE inventory_batches SET remaining = remaining + remaining_to_restore WHERE id = batch.id;
        remaining_to_restore := 0;
      ELSE
        remaining_to_restore := remaining_to_restore - can_add;
        UPDATE inventory_batches SET remaining = quantity WHERE id = batch.id;
      END IF;
    END;
  END LOOP;

  IF remaining_to_restore > 0 THEN
    INSERT INTO inventory_batches (product_id, quantity, remaining, purchase_price)
    VALUES (p_product_id, remaining_to_restore, remaining_to_restore, p_price);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. RE-ENSURE THE STOCK TRIGGER EXISTS (single source of truth)
-- ============================================

DROP TRIGGER IF EXISTS on_sale_created ON sales;
CREATE TRIGGER on_sale_created
  AFTER INSERT ON sales
  FOR EACH ROW EXECUTE FUNCTION deduct_stock_on_sale();

-- 4. CREDIT TRIGGER → SECURITY DEFINER
-- Staff credit sales also need to update the customer's total_credit.
-- ============================================

CREATE OR REPLACE FUNCTION update_customer_credit()
RETURNS trigger AS $$
BEGIN
  UPDATE customers
  SET total_credit = (
    SELECT COALESCE(SUM(due_amount), 0)
    FROM sales
    WHERE customer_id = NEW.customer_id AND due_amount > 0
  )
  WHERE id = NEW.customer_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. FIX get_monthly_profit
-- Profit was hardcoded to 0. Now computed as:
--   profit = sales_total - purchase_cost(COGS of items sold) - expenses_total
-- Always returns exactly one row.
-- ============================================

CREATE OR REPLACE FUNCTION get_monthly_profit(p_start TIMESTAMPTZ, p_end TIMESTAMPTZ)
RETURNS TABLE(sales_total NUMERIC, purchase_cost NUMERIC, expenses_total NUMERIC, profit NUMERIC) AS $$
  SELECT
    (SELECT COALESCE(SUM(s.final_amount), 0) FROM sales s WHERE s.created_at >= p_start AND s.created_at < p_end)::NUMERIC AS sales_total,
    (SELECT COALESCE(SUM((item->>'purchase_price')::NUMERIC * (item->>'qty')::INT), 0) FROM sales s2, jsonb_array_elements(s2.items) AS item WHERE s2.created_at >= p_start AND s2.created_at < p_end)::NUMERIC AS purchase_cost,
    (SELECT COALESCE(SUM(e.amount), 0) FROM expenses e WHERE e.created_at >= p_start AND e.created_at < p_end)::NUMERIC AS expenses_total,
    (
      (SELECT COALESCE(SUM(s.final_amount), 0) FROM sales s WHERE s.created_at >= p_start AND s.created_at < p_end)
      - (SELECT COALESCE(SUM((item->>'purchase_price')::NUMERIC * (item->>'qty')::INT), 0) FROM sales s2, jsonb_array_elements(s2.items) AS item WHERE s2.created_at >= p_start AND s2.created_at < p_end)
      - (SELECT COALESCE(SUM(e.amount), 0) FROM expenses e WHERE e.created_at >= p_start AND e.created_at < p_end)
    )::NUMERIC AS profit;
$$ LANGUAGE sql SECURITY DEFINER;

-- 10. FIX get_stock_value — include variant stock
-- ============================================

CREATE OR REPLACE FUNCTION get_stock_value()
RETURNS NUMERIC AS $$
  SELECT COALESCE(
    (SELECT SUM(stock * purchase_price) FROM products WHERE has_variants = false)
    +
    (SELECT COALESCE(SUM(pv.stock * pv.purchase_price), 0)
     FROM product_variants pv
     JOIN products p ON p.id = pv.product_id
     WHERE p.has_variants = true AND pv.is_active = true),
  0)::NUMERIC;
$$ LANGUAGE sql SECURITY DEFINER;

-- 6. CREDIT PAYMENT TRIGGER → SECURITY DEFINER
-- ============================================

CREATE OR REPLACE FUNCTION update_credit_after_payment()
RETURNS trigger AS $$
BEGIN
  UPDATE sales
  SET amount_paid = amount_paid + NEW.amount,
      due_amount = due_amount - NEW.amount
  WHERE id = NEW.sale_id;

  UPDATE customers
  SET total_credit = (
    SELECT COALESCE(SUM(due_amount), 0)
    FROM sales
    WHERE customer_id = NEW.customer_id AND due_amount > 0
  )
  WHERE id = NEW.customer_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. SUPPLIER DUES TRIGGERS → SECURITY DEFINER
-- ============================================

CREATE OR REPLACE FUNCTION update_supplier_dues()
RETURNS trigger AS $$
BEGIN
  UPDATE suppliers
  SET total_dues = (
    SELECT COALESCE(SUM(due_amount), 0)
    FROM purchases
    WHERE supplier_id = NEW.supplier_id AND due_amount > 0
  )
  WHERE id = NEW.supplier_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION update_supplier_dues_after_payment()
RETURNS trigger AS $$
BEGIN
  UPDATE purchases
  SET amount_paid = amount_paid + NEW.amount,
      due_amount = due_amount - NEW.amount
  WHERE id = NEW.purchase_id;

  UPDATE suppliers
  SET total_dues = (
    SELECT COALESCE(SUM(due_amount), 0)
    FROM purchases
    WHERE supplier_id = NEW.supplier_id AND due_amount > 0
  )
  WHERE id = NEW.supplier_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. INVENTORY BATCH → SECURITY DEFINER
-- ============================================

CREATE OR REPLACE FUNCTION add_inventory_batch(
  p_product_id UUID,
  p_purchase_id UUID,
  p_quantity INTEGER,
  p_purchase_price NUMERIC(10,2)
)
RETURNS void AS $$
BEGIN
  INSERT INTO inventory_batches (product_id, purchase_id, quantity, remaining, purchase_price)
  VALUES (p_product_id, p_purchase_id, p_quantity, p_quantity, p_purchase_price);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9. ANALYTICS RPCs → SECURITY DEFINER + fix profit
-- ============================================

CREATE OR REPLACE FUNCTION get_monthly_sales_summary()
RETURNS TABLE(month TEXT, total_sales NUMERIC, total_purchases NUMERIC, total_expenses NUMERIC, profit NUMERIC)
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  WITH months AS (
    SELECT generate_series(
      date_trunc('month', NOW() - INTERVAL '11 months'),
      date_trunc('month', NOW()),
      INTERVAL '1 month'
    ) AS month
  )
  SELECT
    TO_CHAR(m.month, 'Mon YYYY') AS month,
    COALESCE((SELECT SUM(final_amount) FROM sales WHERE date_trunc('month', created_at) = m.month), 0) AS total_sales,
    COALESCE((SELECT SUM(total_amount) FROM purchases WHERE date_trunc('month', created_at) = m.month), 0) AS total_purchases,
    COALESCE((SELECT SUM(amount) FROM expenses WHERE date_trunc('month', created_at) = m.month), 0) AS total_expenses,
    COALESCE((SELECT SUM(final_amount) FROM sales WHERE date_trunc('month', created_at) = m.month), 0)
    - COALESCE((SELECT SUM((item->>'purchase_price')::NUMERIC * (item->>'qty')::INT) FROM sales s, jsonb_array_elements(s.items) AS item WHERE date_trunc('month', s.created_at) = m.month), 0)
    - COALESCE((SELECT SUM(amount) FROM expenses WHERE date_trunc('month', created_at) = m.month), 0) AS profit
  FROM months m
  ORDER BY m.month;
$$;

CREATE OR REPLACE FUNCTION get_category_sales()
RETURNS TABLE(category TEXT, total_qty BIGINT, total_revenue NUMERIC)
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  SELECT
    COALESCE(p.category, 'Uncategorized') AS category,
    SUM((item->>'qty')::int) AS total_qty,
    SUM((item->>'total')::numeric) AS total_revenue
  FROM sales s,
  jsonb_array_elements(s.items) AS item
  LEFT JOIN products p ON p.id = (item->>'product_id')::uuid
  GROUP BY p.category
  ORDER BY total_revenue DESC;
$$;

CREATE OR REPLACE FUNCTION get_daily_sales_trend()
RETURNS TABLE(day DATE, total_sales NUMERIC, order_count BIGINT)
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  SELECT
    d.day::date,
    COALESCE((SELECT SUM(final_amount) FROM sales WHERE created_at::date = d.day), 0) AS total_sales,
    COALESCE((SELECT COUNT(*) FROM sales WHERE created_at::date = d.day), 0) AS order_count
  FROM generate_series(NOW() - INTERVAL '30 days', NOW(), INTERVAL '1 day') AS d(day)
  ORDER BY d.day;
$$;

-- 11. FIX foreign keys for supplier deletion
-- Without this, deleting a supplier with purchases/POs fails silently
-- ============================================

ALTER TABLE purchases DROP CONSTRAINT IF EXISTS purchases_supplier_id_fkey;
ALTER TABLE purchases ADD CONSTRAINT purchases_supplier_id_fkey
  FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL;

ALTER TABLE purchase_orders DROP CONSTRAINT IF EXISTS purchase_orders_supplier_id_fkey;
ALTER TABLE purchase_orders ADD CONSTRAINT purchase_orders_supplier_id_fkey
  FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL;

-- 12. BATCH TRACKING
-- Add batch_number and expiry_date to inventory_batches
-- ============================================

ALTER TABLE inventory_batches ADD COLUMN IF NOT EXISTS batch_number TEXT;
ALTER TABLE inventory_batches ADD COLUMN IF NOT EXISTS expiry_date DATE;

-- Update add_inventory_batch function to accept batch_number and expiry_date
CREATE OR REPLACE FUNCTION add_inventory_batch(
  p_product_id UUID,
  p_purchase_id UUID,
  p_quantity INTEGER,
  p_purchase_price NUMERIC(10,2),
  p_batch_number TEXT DEFAULT NULL,
  p_expiry_date DATE DEFAULT NULL
)
RETURNS void AS $$
BEGIN
  INSERT INTO inventory_batches (product_id, purchase_id, quantity, remaining, purchase_price, batch_number, expiry_date)
  VALUES (p_product_id, p_purchase_id, p_quantity, p_quantity, p_purchase_price, p_batch_number, p_expiry_date);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get batches for a product
CREATE OR REPLACE FUNCTION get_product_batches(p_product_id UUID)
RETURNS TABLE(
  id UUID,
  batch_number TEXT,
  expiry_date DATE,
  quantity INTEGER,
  remaining INTEGER,
  purchase_price NUMERIC(10,2),
  created_at TIMESTAMPTZ
) AS $$
  SELECT id, batch_number, expiry_date, quantity, remaining, purchase_price, created_at
  FROM inventory_batches
  WHERE product_id = p_product_id AND remaining > 0
  ORDER BY created_at ASC;
$$ LANGUAGE sql SECURITY DEFINER;

-- Function to get expiring batches
CREATE OR REPLACE FUNCTION get_expiring_batches(p_days INTEGER DEFAULT 30)
RETURNS TABLE(
  product_name TEXT,
  batch_number TEXT,
  expiry_date DATE,
  remaining INTEGER,
  days_until_expiry INTEGER
) AS $$
  SELECT 
    p.name AS product_name,
    ib.batch_number,
    ib.expiry_date,
    ib.remaining,
    (ib.expiry_date - CURRENT_DATE)::INTEGER AS days_until_expiry
  FROM inventory_batches ib
  JOIN products p ON p.id = ib.product_id
  WHERE ib.expiry_date IS NOT NULL 
    AND ib.expiry_date <= CURRENT_DATE + (p_days || ' days')::INTERVAL
    AND ib.remaining > 0
  ORDER BY ib.expiry_date ASC;
$$ LANGUAGE sql SECURITY DEFINER;
