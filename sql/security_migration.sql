-- ============================================
-- SECURITY MIGRATION
-- Fixes: RLS USING(true), anon GRANT, role escalation
-- Run this ONCE in Supabase SQL Editor
-- ============================================

-- 1. Revoke GRANT EXECUTE from anon on destructive function
REVOKE EXECUTE ON FUNCTION clear_all_tamil_names() FROM anon;

-- 2. Fix profiles UPDATE policy — prevent staff from changing their own role
-- Drop existing policies on profiles
DROP POLICY IF EXISTS "Users read own profile" ON profiles;
DROP POLICY IF EXISTS "Users update own profile" ON profiles;
DROP POLICY IF EXISTS "Users insert own profile" ON profiles;
DROP POLICY IF EXISTS "Admins read all profiles" ON profiles;
DROP POLICY IF EXISTS "Admins manage profiles" ON profiles;

-- Recreate with role-escalation prevention
CREATE POLICY "Users read own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users update own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id)
  WITH CHECK (role = (SELECT role FROM profiles WHERE id = auth.uid()));

CREATE POLICY "Users insert own profile" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Admins read all profiles" ON profiles
  FOR SELECT USING (is_admin());

CREATE POLICY "Admins manage profiles" ON profiles
  FOR ALL USING (is_admin());

-- 3. Re-apply proper RLS on tables that had USING(true) in legacy SQL
-- Customers: staff can read, admin full access
DROP POLICY IF EXISTS "Anyone can read customers" ON customers;
DROP POLICY IF EXISTS "Admins can manage customers" ON customers;
DROP POLICY IF EXISTS "Admin full access customers" ON customers;
CREATE POLICY "Authenticated can read customers" ON customers
  FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Admins can manage customers" ON customers
  FOR ALL USING (is_admin());

-- Payments: admin only
DROP POLICY IF EXISTS "Admins full access payments" ON payments;
CREATE POLICY "Admins full access payments" ON payments
  FOR ALL USING (is_admin());

-- Suppliers: admin only
DROP POLICY IF EXISTS "Admins full access suppliers" ON suppliers;
DROP POLICY IF EXISTS "Admin full access suppliers" ON suppliers;
CREATE POLICY "Admins full access suppliers" ON suppliers
  FOR ALL USING (is_admin());

-- Supplier payments: admin only
DROP POLICY IF EXISTS "Admins full access supplier_payments" ON supplier_payments;
CREATE POLICY "Admins full access supplier_payments" ON supplier_payments
  FOR ALL USING (is_admin());

-- Inventory batches: staff read, admin manage
DROP POLICY IF EXISTS "Anyone can read inventory_batches" ON inventory_batches;
DROP POLICY IF EXISTS "Admins can manage inventory_batches" ON inventory_batches;
CREATE POLICY "Authenticated can read inventory_batches" ON inventory_batches
  FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Admins can manage inventory_batches" ON inventory_batches
  FOR ALL USING (is_admin());

-- Audit log: admin only (no INSERT for staff — audit entries created via SECURITY DEFINER trigger)
DROP POLICY IF EXISTS "Admin full access audit_log" ON audit_log;
CREATE POLICY "Admins read audit_log" ON audit_log
  FOR SELECT USING (is_admin());

-- Stock reconciliation: admin only
DROP POLICY IF EXISTS "Admin full access stock_reconciliation" ON stock_reconciliation;
CREATE POLICY "Admins manage stock_reconciliation" ON stock_reconciliation
  FOR ALL USING (is_admin());

-- Payment reminders: admin only
DROP POLICY IF EXISTS "Admin full access payment_reminders" ON payment_reminders;
CREATE POLICY "Admins manage payment_reminders" ON payment_reminders
  FOR ALL USING (is_admin());
