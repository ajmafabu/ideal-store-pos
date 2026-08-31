-- ============================================
-- SUPPLIER MANAGEMENT SETUP
-- Run this in: Supabase Dashboard → SQL Editor
-- ============================================

-- 1. CREATE SUPPLIERS TABLE
-- ============================================

CREATE TABLE suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  phone TEXT,
  address TEXT,
  gst_number TEXT,
  total_dues NUMERIC(10,2) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_suppliers_phone ON suppliers(phone);
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin full access suppliers" ON suppliers FOR ALL USING (true);

-- 2. ADD SUPPLIER_ID TO PURCHASES
-- ============================================

ALTER TABLE purchases ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES suppliers(id);
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS is_credit BOOLEAN DEFAULT false;
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS amount_paid NUMERIC(10,2) DEFAULT 0;
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS due_amount NUMERIC(10,2) DEFAULT 0;

CREATE INDEX idx_purchases_supplier ON purchases(supplier_id);

-- 3. CREATE SUPPLIER PAYMENTS TABLE
-- ============================================

CREATE TABLE supplier_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id UUID REFERENCES suppliers(id) ON DELETE CASCADE,
  purchase_id UUID REFERENCES purchases(id) ON DELETE CASCADE,
  amount NUMERIC(10,2) NOT NULL,
  payment_method TEXT DEFAULT 'cash',
  notes TEXT,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_supplier_payments_supplier ON supplier_payments(supplier_id);
ALTER TABLE supplier_payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin full access supplier_payments" ON supplier_payments FOR ALL USING (true);

-- 4. FUNCTION: Update supplier total dues
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_purchase_dues_update
  AFTER INSERT OR UPDATE ON purchases
  FOR EACH ROW EXECUTE FUNCTION update_supplier_dues();

-- 5. FUNCTION: Update dues after payment
-- ============================================

CREATE OR REPLACE FUNCTION update_supplier_dues_after_payment()
RETURNS trigger AS $$
BEGIN
  -- Update purchase amount_paid and due_amount
  UPDATE purchases
  SET amount_paid = amount_paid + NEW.amount,
      due_amount = due_amount - NEW.amount
  WHERE id = NEW.purchase_id;

  -- Update supplier total dues
  UPDATE suppliers
  SET total_dues = (
    SELECT COALESCE(SUM(due_amount), 0)
    FROM purchases
    WHERE supplier_id = NEW.supplier_id AND due_amount > 0
  )
  WHERE id = NEW.supplier_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_supplier_payment_insert
  AFTER INSERT ON supplier_payments
  FOR EACH ROW EXECUTE FUNCTION update_supplier_dues_after_payment();
