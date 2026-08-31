-- ============================================
-- WHOLESALE MARKET APP - SUPABASE SETUP
-- Run this in: Supabase Dashboard → SQL Editor
-- ============================================

-- 1. CREATE TABLES
-- ============================================

-- Shops table
CREATE TABLE shops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  address TEXT,
  phone TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Profiles (users) table
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  role TEXT CHECK (role IN ('admin','staff')) DEFAULT 'staff',
  pin TEXT,
  shop_id UUID REFERENCES shops(id),
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Products table
CREATE TABLE products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  barcode TEXT UNIQUE,
  category TEXT,
  purchase_price NUMERIC(10,2) DEFAULT 0,
  selling_price NUMERIC(10,2) DEFAULT 0,
  stock INTEGER DEFAULT 0,
  unit TEXT DEFAULT 'pcs',
  low_stock_alert INTEGER DEFAULT 10,
  shop_id UUID REFERENCES shops(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Sales table
CREATE TABLE sales (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  items JSONB NOT NULL DEFAULT '[]',
  total_amount NUMERIC(10,2) DEFAULT 0,
  discount NUMERIC(10,2) DEFAULT 0,
  final_amount NUMERIC(10,2) DEFAULT 0,
  payment_method TEXT DEFAULT 'cash',
  created_by UUID REFERENCES profiles(id),
  shop_id UUID REFERENCES shops(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Purchases table
CREATE TABLE purchases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_name TEXT,
  items JSONB NOT NULL DEFAULT '[]',
  total_amount NUMERIC(10,2) DEFAULT 0,
  created_by UUID REFERENCES profiles(id),
  shop_id UUID REFERENCES shops(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Expenses table
CREATE TABLE expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category TEXT NOT NULL,
  description TEXT,
  amount NUMERIC(10,2) DEFAULT 0,
  created_by UUID REFERENCES profiles(id),
  shop_id UUID REFERENCES shops(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. CREATE INDEXES
-- ============================================

CREATE INDEX idx_products_barcode ON products(barcode);
CREATE INDEX idx_products_shop ON products(shop_id);
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_sales_created ON sales(created_at);
CREATE INDEX idx_sales_shop ON sales(shop_id);
CREATE INDEX idx_purchases_created ON purchases(created_at);
CREATE INDEX idx_expenses_created ON expenses(created_at);
CREATE INDEX idx_profiles_shop ON profiles(shop_id);

-- 3. ENABLE ROW LEVEL SECURITY
-- ============================================

ALTER TABLE shops ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;

-- 4. RLS POLICIES
-- ============================================

-- PROFILES: Users can read their own profile
CREATE POLICY "Users read own profile" ON profiles
  FOR SELECT USING (id = auth.uid());

-- PROFILES: Admins can do everything
CREATE POLICY "Admins full access profiles" ON profiles
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- PRODUCTS: Everyone can read, admin can modify
CREATE POLICY "All read products" ON products
  FOR SELECT USING (true);

CREATE POLICY "Admin manage products" ON products
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- SALES: Admin full access, staff can insert and read own
CREATE POLICY "Admin full access sales" ON sales
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "Staff insert sales" ON sales
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'staff')
    AND created_by = auth.uid()
  );

CREATE POLICY "Staff read own sales" ON sales
  FOR SELECT USING (
    created_by = auth.uid()
  );

-- PURCHASES: Admin only
CREATE POLICY "Admin full access purchases" ON purchases
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- EXPENSES: Admin only
CREATE POLICY "Admin full access expenses" ON expenses
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- SHOPS: Admin only
CREATE POLICY "Admin full access shops" ON shops
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- 5. CREATE DEFAULT SHOP (run after first admin signup)
-- ============================================

-- INSERT INTO shops (name, address, phone) VALUES ('Your Shop Name', 'Address', 'Phone');

-- 6. FUNCTION: Auto-create profile on signup
-- ============================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, name, role)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'name', new.email),
    COALESCE(new.raw_user_meta_data->>'role', 'staff')
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to auto-create profile
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 7. FUNCTION: Auto-deduct stock on sale (optional trigger)
-- ============================================

CREATE OR REPLACE FUNCTION deduct_stock_on_sale()
RETURNS trigger AS $$
DECLARE
  item JSONB;
BEGIN
  FOR item IN SELECT * FROM jsonb_array_elements(NEW.items)
  LOOP
    UPDATE products
    SET stock = stock - (item->>'qty')::INTEGER
    WHERE id = (item->>'product_id')::UUID;
  END LOOP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_sale_created
  AFTER INSERT ON sales
  FOR EACH ROW EXECUTE FUNCTION deduct_stock_on_sale();

-- 8. FUNCTION: Increment stock (for sale deletion)
-- ============================================

CREATE OR REPLACE FUNCTION increment_stock(p_product_id UUID, p_qty INTEGER)
RETURNS void AS $$
BEGIN
  UPDATE products
  SET stock = stock + p_qty
  WHERE id = p_product_id;
END;
$$ LANGUAGE plpgsql;

-- 9. INVENTORY BATCHES TABLE (FIFO tracking)
-- ============================================

CREATE TABLE inventory_batches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID REFERENCES products(id) ON DELETE CASCADE,
  purchase_id UUID REFERENCES purchases(id) ON DELETE CASCADE,
  quantity INTEGER NOT NULL,
  remaining INTEGER NOT NULL,
  purchase_price NUMERIC(10,2) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_batches_product ON inventory_batches(product_id);
CREATE INDEX idx_batches_purchase ON inventory_batches(purchase_id);

ALTER TABLE inventory_batches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin full access batches" ON inventory_batches
  FOR ALL USING (true);

-- 10. FUNCTION: Add batch on purchase
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
$$ LANGUAGE plpgsql;

-- 11. FUNCTION: Deduct stock FIFO (from oldest batches)
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
$$ LANGUAGE plpgsql;

-- 12. Updated trigger: deduct stock + FIFO on sale
-- ============================================

CREATE OR REPLACE FUNCTION deduct_stock_on_sale()
RETURNS trigger AS $$
DECLARE
  item JSONB;
BEGIN
  FOR item IN SELECT * FROM jsonb_array_elements(NEW.items)
  LOOP
    -- Deduct from product total
    UPDATE products
    SET stock = stock - (item->>'qty')::INTEGER
    WHERE id = (item->>'product_id')::UUID;
    
    -- Deduct FIFO from batches
    PERFORM deduct_stock_fifo(
      (item->>'product_id')::UUID,
      (item->>'qty')::INTEGER
    );
  END LOOP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 13. Restore batch on sale deletion
-- ============================================

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
  -- Try to add back to existing batches with same price first
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
  
  -- If still remaining, create new batch
  IF remaining_to_restore > 0 THEN
    INSERT INTO inventory_batches (product_id, quantity, remaining, purchase_price)
    VALUES (p_product_id, remaining_to_restore, remaining_to_restore, p_price);
  END IF;
END;
$$ LANGUAGE plpgsql;
