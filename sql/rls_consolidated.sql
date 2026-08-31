-- ============================================
-- CONSOLIDATED RLS POLICIES (ROLE-BASED)
-- Run this ONCE in Supabase SQL Editor
-- Replaces all old RLS files
--
-- ROLES:
--   admin  = full CRUD on all tables
--   staff  = read products/sales/customers, create sales, no access to financials
-- ============================================

-- Helper function to check if user is admin
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean AS $$
DECLARE
  user_role text;
BEGIN
  SELECT role INTO user_role FROM profiles WHERE id = auth.uid();
  RETURN user_role = 'admin';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Drop ALL existing policies
DO $$ DECLARE
  r RECORD;
BEGIN
  FOR r IN (SELECT schemaname, tablename, policyname FROM pg_policies WHERE schemaname = 'public') LOOP
    EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON ' || quote_ident(r.schemaname) || '.' || quote_ident(r.tablename);
  END LOOP;
END $$;

-- ============================================
-- ENABLE RLS ON ALL TABLES
-- ============================================

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE shops ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE damaged_products ENABLE ROW LEVEL SECURITY;

-- ============================================
-- PROFILES
-- ============================================

CREATE POLICY "Users read own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users update own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users insert own profile" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Admins read all profiles" ON profiles
  FOR SELECT USING (is_admin());

CREATE POLICY "Admins manage profiles" ON profiles
  FOR ALL USING (is_admin());

-- ============================================
-- PRODUCTS
-- Staff: read only | Admin: full access
-- ============================================

CREATE POLICY "Anyone can read products" ON products
  FOR SELECT USING (true);

CREATE POLICY "Admins can insert products" ON products
  FOR INSERT WITH CHECK (is_admin());

CREATE POLICY "Admins can update products" ON products
  FOR UPDATE USING (is_admin());

CREATE POLICY "Admins can delete products" ON products
  FOR DELETE USING (is_admin());

-- ============================================
-- SALES
-- Staff: read own + create | Admin: full access
-- ============================================

CREATE POLICY "Admins full access sales" ON sales
  FOR ALL USING (is_admin());

CREATE POLICY "Staff can read sales" ON sales
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Staff can create sales" ON sales
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- ============================================
-- PURCHASES
-- Staff: NO access | Admin: full access
-- ============================================

CREATE POLICY "Admins full access purchases" ON purchases
  FOR ALL USING (is_admin());

-- ============================================
-- EXPENSES
-- Staff: NO access | Admin: full access
-- ============================================

CREATE POLICY "Admins full access expenses" ON expenses
  FOR ALL USING (is_admin());

-- ============================================
-- SHOPS
-- Staff: read only | Admin: full access
-- ============================================

CREATE POLICY "Anyone can read shops" ON shops
  FOR SELECT USING (true);

CREATE POLICY "Admins can manage shops" ON shops
  FOR ALL USING (is_admin());

-- ============================================
-- CUSTOMERS
-- Staff: read only | Admin: full access
-- ============================================

CREATE POLICY "Anyone can read customers" ON customers
  FOR SELECT USING (true);

CREATE POLICY "Admins can manage customers" ON customers
  FOR ALL USING (is_admin());

-- ============================================
-- SUPPLIERS
-- Staff: NO access | Admin: full access
-- ============================================

CREATE POLICY "Admins full access suppliers" ON suppliers
  FOR ALL USING (is_admin());

-- ============================================
-- PAYMENTS
-- Staff: NO access | Admin: full access
-- ============================================

CREATE POLICY "Admins full access payments" ON payments
  FOR ALL USING (is_admin());

-- ============================================
-- SUPPLIER_PAYMENTS
-- Staff: NO access | Admin: full access
-- ============================================

CREATE POLICY "Admins full access supplier_payments" ON supplier_payments
  FOR ALL USING (is_admin());

-- ============================================
-- INVENTORY_BATCHES
-- Staff: read only | Admin: full access
-- ============================================

CREATE POLICY "Anyone can read inventory_batches" ON inventory_batches
  FOR SELECT USING (true);

CREATE POLICY "Admins can manage inventory_batches" ON inventory_batches
  FOR ALL USING (is_admin());

-- ============================================
-- ACCOUNTS
-- Staff: NO access | Admin: full access
-- ============================================

CREATE POLICY "Admins full access accounts" ON accounts
  FOR ALL USING (is_admin());

-- ============================================
-- ACCOUNT_TRANSACTIONS
-- Staff: NO access | Admin: full access
-- ============================================

CREATE POLICY "Admins full access account_transactions" ON account_transactions
  FOR ALL USING (is_admin());

-- ============================================
-- PRODUCT_RETURNS
-- Staff: NO access | Admin: full access
-- ============================================

CREATE POLICY "Admins full access product_returns" ON product_returns
  FOR ALL USING (is_admin());

-- ============================================
-- DAMAGED_PRODUCTS
-- Staff: NO access | Admin: full access
-- ============================================

CREATE POLICY "Admins full access damaged_products" ON damaged_products
  FOR ALL USING (is_admin());
