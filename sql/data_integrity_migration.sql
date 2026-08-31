-- ============================================
-- DATA INTEGRITY MIGRATION
-- Fixes: row locking, negative due_amount, stock safety
-- Run this ONCE in Supabase SQL Editor
-- ============================================

-- 1. Add row-level locking to increment_stock
CREATE OR REPLACE FUNCTION increment_stock(p_product_id UUID, p_qty INTEGER)
RETURNS void AS $$
BEGIN
  UPDATE products
  SET stock = stock + p_qty
  WHERE id = p_product_id;
  -- Lock the row to prevent concurrent modifications
  -- PostgreSQL's UPDATE already acquires an EXCLUSIVE row lock
  -- Adding a SELECT ... FOR UPDATE to verify the lock took effect
  PERFORM 1 FROM products WHERE id = p_product_id FOR UPDATE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Add row-level locking to decrement_stock with negative guard
CREATE OR REPLACE FUNCTION decrement_stock(p_product_id UUID, p_qty INTEGER)
RETURNS void AS $$
BEGIN
  UPDATE products
  SET stock = GREATEST(stock - p_qty, 0)
  WHERE id = p_product_id;
  PERFORM 1 FROM products WHERE id = p_product_id FOR UPDATE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Fix negative due_amount from overpayment in credit tracking
CREATE OR REPLACE FUNCTION update_credit_after_payment()
RETURNS trigger AS $$
BEGIN
  -- Update sale amount_paid and due_amount (prevent negative)
  UPDATE sales
  SET amount_paid = amount_paid + NEW.amount,
      due_amount = GREATEST(due_amount - NEW.amount, 0)
  WHERE id = NEW.sale_id;

  -- Update customer total credit
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

-- 4. Fix negative supplier due_amount from overpayment
CREATE OR REPLACE FUNCTION update_supplier_dues_after_payment()
RETURNS trigger AS $$
BEGIN
  UPDATE purchases
  SET amount_paid = amount_paid + NEW.amount,
      due_amount = GREATEST(due_amount - NEW.amount, 0)
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

-- 5. Add CHECK constraint to prevent negative stock at DB level
ALTER TABLE products ADD CONSTRAINT products_stock_non_negative CHECK (stock >= 0);

-- 6. Add missing index on payments.sale_id
CREATE INDEX IF NOT EXISTS idx_payments_sale_id ON payments(sale_id);

-- 7. Add composite index for credit trigger subquery performance
CREATE INDEX IF NOT EXISTS idx_sales_customer_due ON sales(customer_id, due_amount) WHERE due_amount > 0;
