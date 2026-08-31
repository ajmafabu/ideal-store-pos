-- ============================================
-- CREDIT/DEBT TRACKING SETUP
-- Run this in: Supabase Dashboard → SQL Editor
-- ============================================

-- 1. CREATE CUSTOMERS TABLE
-- ============================================

CREATE TABLE customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  phone TEXT,
  address TEXT,
  total_credit NUMERIC(10,2) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_customers_phone ON customers(phone);
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin full access customers" ON customers FOR ALL USING (true);

-- 2. ADD CREDIT FIELDS TO SALES
-- ============================================

ALTER TABLE sales ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES customers(id);
ALTER TABLE sales ADD COLUMN IF NOT EXISTS is_credit BOOLEAN DEFAULT false;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS amount_paid NUMERIC(10,2) DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS due_amount NUMERIC(10,2) DEFAULT 0;

CREATE INDEX idx_sales_customer ON sales(customer_id);
CREATE INDEX idx_sales_credit ON sales(is_credit);

-- 3. CREATE PAYMENTS TABLE (track partial payments)
-- ============================================

CREATE TABLE payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
  sale_id UUID REFERENCES sales(id) ON DELETE CASCADE,
  amount NUMERIC(10,2) NOT NULL,
  payment_method TEXT DEFAULT 'cash',
  notes TEXT,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_payments_customer ON payments(customer_id);
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin full access payments" ON payments FOR ALL USING (true);

-- 4. FUNCTION: Update customer total credit
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_sale_credit_update
  AFTER INSERT OR UPDATE ON sales
  FOR EACH ROW EXECUTE FUNCTION update_customer_credit();

-- 5. FUNCTION: Update credit after payment
-- ============================================

CREATE OR REPLACE FUNCTION update_credit_after_payment()
RETURNS trigger AS $$
BEGIN
  -- Update sale amount_paid and due_amount
  UPDATE sales
  SET amount_paid = amount_paid + NEW.amount,
      due_amount = due_amount - NEW.amount
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_payment_insert
  AFTER INSERT ON payments
  FOR EACH ROW EXECUTE FUNCTION update_credit_after_payment();
