-- =====================================================================
-- IDEAL STORE POS — AUDIT FIX MIGRATION  (v2026.10.03, app 1.1.0)
-- ---------------------------------------------------------------------
-- One idempotent script that brings ANY earlier state of this project's
-- database (whichever of the 47 historical sql/*.sql files were applied,
-- in whatever order) to a single, known-good state.
--
--  * Safe to re-run: every statement is IF [NOT] EXISTS / OR REPLACE,
--    and all triggers, RLS policies and app functions are dropped and
--    recreated from this file, so the result never depends on history.
--  * Runs in ONE transaction: if anything fails nothing is changed.
--
-- HOW TO APPLY (see sql/README.md):
--   1. Take a backup (Supabase Dashboard → Database → Backups, or
--      `supabase db dump`), and run sql/verify_schema.sql to see the
--      current state.
--   2. Paste this whole file into the Supabase SQL editor and run it.
--   3. Run sql/verify_schema.sql again — every check should say OK.
--   4. Update EVERY device to app 1.1.0 at the same time (money posting
--      moved from the app into the database; old app versions are
--      blocked from double-posting, but should not stay in use).
-- =====================================================================

BEGIN;

SET LOCAL search_path = public, extensions;
SET LOCAL lock_timeout = '30s';
-- Suppress all app triggers while this script rewrites data.
DO $$ BEGIN PERFORM set_config('app.bulk_mode', 'on', true); END $$;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------
-- 0. Make the result independent of history: drop every app trigger,
--    every RLS policy and every app function, then recreate them below.
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  -- triggers on public tables
  FOR r IN
    SELECT t.tgname, c.relname
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND NOT t.tgisinternal
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', r.tgname, r.relname);
  END LOOP;

  -- the signup trigger lives on auth.users
  IF to_regclass('auth.users') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users';
  END IF;

  -- every policy in public
  FOR r IN SELECT schemaname, tablename, policyname FROM pg_policies WHERE schemaname = 'public'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
  END LOOP;

  -- every overload of every function this project has ever defined
  -- (is_admin is kept: CREATE OR REPLACE below keeps its signature)
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname = ANY (ARRAY[
        'handle_new_user','deduct_stock_on_sale','increment_stock','decrement_stock',
        'add_inventory_batch','deduct_stock_fifo','restore_stock_fifo','correct_fifo_purchase_price',
        'reconcile_stock_with_batches','get_product_batches','get_expiring_batches','get_stock_value',
        'delete_sale_atomic','edit_sale_atomic','edit_purchase_atomic','create_return_atomic',
        'create_damaged_atomic','add_account_transaction','transfer_between_accounts',
        'update_customer_credit','update_credit_after_payment','update_supplier_dues',
        'update_supplier_dues_after_payment','audit_trigger_func','update_product_variants_updated_at',
        'get_monthly_profit','get_monthly_sales_summary','get_category_sales','get_daily_sales_trend',
        'get_customer_insights','get_product_insights','get_inventory_health','get_financial_summary',
        'get_sales_forecast','get_dashboard_summary','get_product_sales_stats','get_reports_summary',
        'get_balance_sheet','get_cash_flow','get_receivables_aging','get_gstr3b_summary',
        'get_trial_balance','get_profit_loss','get_sales_total','get_expenses_total','get_top_products',
        'populate_daily_analytics','backfill_daily_analytics','refresh_today_analytics',
        'get_table_row_counts','create_backup_record','complete_backup','fail_backup',
        'get_backup_history','get_database_size_estimate','clear_all_tamil_names','update_tamil_names'
      ])
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %s CASCADE', r.sig);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 1. Schema: create anything missing, add every column the app uses
-- ---------------------------------------------------------------------

-- core tables (for a database that never ran setup/credit/supplier files)
CREATE TABLE IF NOT EXISTS shops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  address TEXT,
  phone TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  role TEXT CHECK (role IN ('admin','staff')) DEFAULT 'staff',
  pin TEXT,
  shop_id UUID REFERENCES shops(id),
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  barcode TEXT UNIQUE,
  category TEXT,
  purchase_price NUMERIC(10,2) DEFAULT 0,
  selling_price NUMERIC(10,2) DEFAULT 0,
  stock NUMERIC(14,3) DEFAULT 0,
  unit TEXT DEFAULT 'pcs',
  low_stock_alert INTEGER DEFAULT 10,
  shop_id UUID REFERENCES shops(id),
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  phone TEXT,
  address TEXT,
  total_credit NUMERIC(12,2) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  phone TEXT,
  address TEXT,
  gst_number TEXT,
  total_dues NUMERIC(12,2) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS sales (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  items JSONB NOT NULL DEFAULT '[]',
  total_amount NUMERIC(12,2) DEFAULT 0,
  discount NUMERIC(12,2) DEFAULT 0,
  final_amount NUMERIC(12,2) DEFAULT 0,
  payment_method TEXT DEFAULT 'cash',
  created_by UUID REFERENCES profiles(id),
  shop_id UUID REFERENCES shops(id),
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS purchases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_name TEXT,
  items JSONB NOT NULL DEFAULT '[]',
  total_amount NUMERIC(12,2) DEFAULT 0,
  created_by UUID REFERENCES profiles(id),
  shop_id UUID REFERENCES shops(id),
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category TEXT NOT NULL,
  description TEXT,
  amount NUMERIC(12,2) DEFAULT 0,
  created_by UUID REFERENCES profiles(id),
  shop_id UUID REFERENCES shops(id),
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS inventory_batches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID REFERENCES products(id) ON DELETE CASCADE,
  purchase_id UUID REFERENCES purchases(id) ON DELETE CASCADE,
  quantity NUMERIC(14,3) NOT NULL,
  remaining NUMERIC(14,3) NOT NULL,
  purchase_price NUMERIC(14,4) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
  sale_id UUID REFERENCES sales(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL,
  payment_method TEXT DEFAULT 'cash',
  notes TEXT,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS supplier_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id UUID REFERENCES suppliers(id) ON DELETE CASCADE,
  purchase_id UUID REFERENCES purchases(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL,
  payment_method TEXT DEFAULT 'cash',
  notes TEXT,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  account_type TEXT NOT NULL,
  balance NUMERIC DEFAULT 0,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS account_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID REFERENCES accounts(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  amount NUMERIC NOT NULL CHECK (amount > 0),
  category TEXT NOT NULL,
  description TEXT,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS product_returns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id UUID REFERENCES sales(id),
  product_id UUID REFERENCES products(id),
  product_name TEXT NOT NULL,
  quantity NUMERIC(14,3) NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(12,2) DEFAULT 0,
  refund_amount NUMERIC(12,2) DEFAULT 0,
  reason TEXT,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS damaged_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID REFERENCES products(id),
  product_name TEXT NOT NULL,
  quantity NUMERIC(14,3) NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(12,2) DEFAULT 0,
  reason TEXT,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS product_variants (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sku TEXT,
  barcode TEXT,
  price NUMERIC NOT NULL DEFAULT 0,
  purchase_price NUMERIC NOT NULL DEFAULT 0,
  stock INTEGER NOT NULL DEFAULT 0,
  min_stock INTEGER NOT NULL DEFAULT 0,
  attributes JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(product_id, name)
);
CREATE TABLE IF NOT EXISTS purchase_orders (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
  supplier_name TEXT,
  items JSONB NOT NULL DEFAULT '[]',
  total_amount NUMERIC NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending',
  notes TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS app_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now()
);
INSERT INTO app_config (key, value) VALUES ('min_version', '1.0.1') ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS audit_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  table_name TEXT,
  record_id UUID,
  action TEXT NOT NULL,
  old_data JSONB,
  new_data JSONB,
  performed_by UUID,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS stock_reconciliation (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  product_id UUID REFERENCES products(id) ON DELETE CASCADE,
  system_qty NUMERIC(14,3) NOT NULL,
  physical_qty NUMERIC(14,3) NOT NULL,
  notes TEXT,
  performed_by UUID,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS payment_reminders (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
  sale_id UUID REFERENCES sales(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL,
  due_date DATE NOT NULL,
  reminder_date DATE NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS transaction_edits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_type TEXT NOT NULL,
  transaction_id UUID NOT NULL,
  reason TEXT NOT NULL,
  old_data JSONB NOT NULL DEFAULT '{}',
  new_data JSONB NOT NULL DEFAULT '{}',
  edited_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS daily_analytics_summary (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  date DATE NOT NULL UNIQUE,
  total_sales NUMERIC DEFAULT 0,
  total_purchases NUMERIC DEFAULT 0,
  total_expenses NUMERIC DEFAULT 0,
  profit NUMERIC DEFAULT 0,
  orders_count INT DEFAULT 0,
  items_sold NUMERIC DEFAULT 0,
  credit_sales NUMERIC DEFAULT 0,
  cash_sales NUMERIC DEFAULT 0,
  returns_count INT DEFAULT 0,
  returns_amount NUMERIC DEFAULT 0,
  unique_customers INT DEFAULT 0,
  avg_order_value NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS schema_migrations (
  id SERIAL PRIMARY KEY,
  version VARCHAR(255) NOT NULL UNIQUE,
  name VARCHAR(500) NOT NULL,
  applied_at TIMESTAMPTZ DEFAULT now(),
  applied_by VARCHAR(255),
  checksum VARCHAR(64),
  execution_ms INTEGER
);
CREATE TABLE IF NOT EXISTS backups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  backup_type VARCHAR(50) NOT NULL DEFAULT 'full',
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  started_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ,
  file_path TEXT,
  file_size_bytes BIGINT,
  checksum VARCHAR(64),
  tables_included TEXT[],
  row_counts JSONB,
  error_message TEXT,
  created_by VARCHAR(255) DEFAULT current_user
);

-- New: single shop-settings row readable by every member, so staff
-- receipts get the shop header and the print language is per shop (#29).
CREATE TABLE IF NOT EXISTS shop_settings (
  id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  shop_name TEXT,
  shop_name_tamil TEXT,
  address TEXT,
  phone TEXT,
  gstin TEXT,
  state_code TEXT NOT NULL DEFAULT '33',
  print_language TEXT NOT NULL DEFAULT 'english',
  invoice_footer TEXT,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- New: what the old app most likely posted to the cash book for each
-- existing document, so edits/deletes of old documents reverse the right
-- amount (#10, #13). Filled once below; never written by the app.
CREATE TABLE IF NOT EXISTS legacy_postings (
  ref_type TEXT NOT NULL,
  ref_id UUID NOT NULL,
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL,           -- signed: + money in, - money out
  PRIMARY KEY (ref_type, ref_id, account_id)
);

-- ----- column completion (every ADD is idempotent) -----
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS gstin TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS shop_name TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS shop_address TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS shop_phone TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS state_code TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS email TEXT;

ALTER TABLE shops ADD COLUMN IF NOT EXISTS state_code TEXT DEFAULT '33';

ALTER TABLE products ADD COLUMN IF NOT EXISTS has_variants BOOLEAN DEFAULT false;
ALTER TABLE products ADD COLUMN IF NOT EXISTS tamil_name TEXT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS sfw TEXT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS unit_type TEXT DEFAULT 'pieces';
ALTER TABLE products ADD COLUMN IF NOT EXISTS pieces_per_unit INT DEFAULT 1;
ALTER TABLE products ADD COLUMN IF NOT EXISTS gst_rate NUMERIC DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS hsn_code TEXT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS expiry_date DATE;
ALTER TABLE products ADD COLUMN IF NOT EXISTS batch_number TEXT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS selling_price_2 DOUBLE PRECISION;
ALTER TABLE products ADD COLUMN IF NOT EXISTS selling_price_2_label TEXT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE product_variants ADD COLUMN IF NOT EXISTS tamil_name TEXT;

ALTER TABLE customers ADD COLUMN IF NOT EXISTS state_code TEXT DEFAULT '33';
ALTER TABLE customers ADD COLUMN IF NOT EXISTS credit_limit NUMERIC DEFAULT 0;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS gstin TEXT;              -- #23 recipient GSTIN
ALTER TABLE customers ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS portal_token UUID DEFAULT gen_random_uuid();
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS state_code TEXT DEFAULT '33';

ALTER TABLE sales ADD COLUMN IF NOT EXISTS customer_id UUID;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS is_credit BOOLEAN DEFAULT false;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS amount_paid NUMERIC(12,2) DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS due_amount NUMERIC(12,2) DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS total_discount NUMERIC(12,2) DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS cash_amount NUMERIC(12,2) DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS digital_amount NUMERIC(12,2) DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS due_date DATE;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS igst_amount NUMERIC DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS cgst_amount NUMERIC DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS sgst_amount NUMERIC DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS extra_charges NUMERIC(12,2) DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS round_off NUMERIC(12,2) DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS tax_exempt BOOLEAN DEFAULT false;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS taxable_amount NUMERIC(12,2);       -- #15
ALTER TABLE sales ADD COLUMN IF NOT EXISTS place_of_supply TEXT;              -- #15/#23
ALTER TABLE sales ADD COLUMN IF NOT EXISTS paid_at_sale NUMERIC(12,2);         -- money received at the till (#10)
ALTER TABLE sales ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE sales ADD COLUMN IF NOT EXISTS invoice_no BIGINT;                -- #19 printable number

ALTER TABLE purchases ADD COLUMN IF NOT EXISTS supplier_id UUID;
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS is_credit BOOLEAN DEFAULT false;
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS amount_paid NUMERIC(12,2) DEFAULT 0;
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS due_amount NUMERIC(12,2) DEFAULT 0;
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS due_date DATE;
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'cash';  -- #11/#12
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS round_off NUMERIC(12,2) DEFAULT 0;   -- #11
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS paid_at_purchase NUMERIC(12,2);
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS taxable_amount NUMERIC(12,2);
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS cgst_amount NUMERIC DEFAULT 0;      -- input tax credit
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS sgst_amount NUMERIC DEFAULT 0;
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS igst_amount NUMERIC DEFAULT 0;
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS purchase_order_id UUID;
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

ALTER TABLE expenses ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'cash';   -- #12
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

ALTER TABLE inventory_batches ADD COLUMN IF NOT EXISTS batch_number TEXT;
ALTER TABLE inventory_batches ADD COLUMN IF NOT EXISTS expiry_date DATE;

ALTER TABLE product_returns ADD COLUMN IF NOT EXISTS original_sale_id UUID;
ALTER TABLE product_returns ADD COLUMN IF NOT EXISTS return_amount NUMERIC DEFAULT 0;
ALTER TABLE product_returns ADD COLUMN IF NOT EXISTS credit_adjusted NUMERIC(12,2) DEFAULT 0;  -- #14
ALTER TABLE product_returns ADD COLUMN IF NOT EXISTS refund_method TEXT DEFAULT 'cash';        -- #14
ALTER TABLE product_returns ADD COLUMN IF NOT EXISTS cost_amount NUMERIC(12,2) DEFAULT 0;      -- #17
ALTER TABLE product_returns ADD COLUMN IF NOT EXISTS tax_amount NUMERIC(12,2) DEFAULT 0;       -- #15

ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS purchase_id UUID;                         -- #21
ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

ALTER TABLE account_transactions ADD COLUMN IF NOT EXISTS ref_type TEXT;   -- which document posted it
ALTER TABLE account_transactions ADD COLUMN IF NOT EXISTS ref_id UUID;
ALTER TABLE account_transactions ADD COLUMN IF NOT EXISTS source TEXT;     -- system | manual | transfer | legacy

ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS entity_type TEXT;           -- columns the app writes
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS entity_id TEXT;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS user_email TEXT;
ALTER TABLE audit_log ALTER COLUMN table_name DROP NOT NULL;
ALTER TABLE audit_log ALTER COLUMN record_id DROP NOT NULL;

-- ----- type widening: fractional stock for kg/litre items (#22) -----
DO $$
BEGIN
  IF (SELECT data_type FROM information_schema.columns
      WHERE table_schema='public' AND table_name='products' AND column_name='stock') <> 'numeric' THEN
    ALTER TABLE products ALTER COLUMN stock TYPE NUMERIC(14,3) USING stock::numeric;
  END IF;
  IF (SELECT data_type FROM information_schema.columns
      WHERE table_schema='public' AND table_name='inventory_batches' AND column_name='quantity') <> 'numeric' THEN
    ALTER TABLE inventory_batches ALTER COLUMN quantity TYPE NUMERIC(14,3) USING quantity::numeric;
    ALTER TABLE inventory_batches ALTER COLUMN remaining TYPE NUMERIC(14,3) USING remaining::numeric;
  END IF;
  IF (SELECT numeric_scale FROM information_schema.columns
      WHERE table_schema='public' AND table_name='inventory_batches' AND column_name='purchase_price') IS DISTINCT FROM 4 THEN
    ALTER TABLE inventory_batches ALTER COLUMN purchase_price TYPE NUMERIC(14,4);
  END IF;
  IF (SELECT data_type FROM information_schema.columns
      WHERE table_schema='public' AND table_name='product_returns' AND column_name='quantity') <> 'numeric' THEN
    ALTER TABLE product_returns ALTER COLUMN quantity TYPE NUMERIC(14,3) USING quantity::numeric;
  END IF;
  IF (SELECT data_type FROM information_schema.columns
      WHERE table_schema='public' AND table_name='damaged_products' AND column_name='quantity') <> 'numeric' THEN
    ALTER TABLE damaged_products ALTER COLUMN quantity TYPE NUMERIC(14,3) USING quantity::numeric;
  END IF;
  IF (SELECT data_type FROM information_schema.columns
      WHERE table_schema='public' AND table_name='stock_reconciliation' AND column_name='system_qty') <> 'numeric' THEN
    ALTER TABLE stock_reconciliation ALTER COLUMN system_qty TYPE NUMERIC(14,3) USING system_qty::numeric;
    ALTER TABLE stock_reconciliation ALTER COLUMN physical_qty TYPE NUMERIC(14,3) USING physical_qty::numeric;
  END IF;
END $$;

-- ----- constraints & foreign keys (all guarded) -----
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='products_stock_non_negative') THEN
    UPDATE products SET stock = 0 WHERE stock < 0;
    ALTER TABLE products ADD CONSTRAINT products_stock_non_negative CHECK (stock >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='inventory_batches_remaining_non_negative') THEN
    UPDATE inventory_batches SET remaining = 0 WHERE remaining < 0;
    ALTER TABLE inventory_batches ADD CONSTRAINT inventory_batches_remaining_non_negative CHECK (remaining >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payments_amount_positive') THEN
    DELETE FROM payments WHERE amount <= 0;
    ALTER TABLE payments ADD CONSTRAINT payments_amount_positive CHECK (amount > 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='supplier_payments_amount_positive') THEN
    DELETE FROM supplier_payments WHERE amount <= 0;
    ALTER TABLE supplier_payments ADD CONSTRAINT supplier_payments_amount_positive CHECK (amount > 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sales_final_amount_non_negative') THEN
    UPDATE sales SET final_amount = 0 WHERE final_amount < 0;          -- #19
    ALTER TABLE sales ADD CONSTRAINT sales_final_amount_non_negative CHECK (final_amount >= 0);
  END IF;
END $$;

-- FKs with the right ON DELETE behaviour (re-created idempotently)
ALTER TABLE sales DROP CONSTRAINT IF EXISTS sales_customer_id_fkey;
ALTER TABLE sales ADD CONSTRAINT sales_customer_id_fkey
  FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE purchases DROP CONSTRAINT IF EXISTS purchases_supplier_id_fkey;
ALTER TABLE purchases ADD CONSTRAINT purchases_supplier_id_fkey
  FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL;
ALTER TABLE purchase_orders DROP CONSTRAINT IF EXISTS purchase_orders_supplier_id_fkey;
ALTER TABLE purchase_orders ADD CONSTRAINT purchase_orders_supplier_id_fkey
  FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL;
ALTER TABLE purchase_orders DROP CONSTRAINT IF EXISTS purchase_orders_purchase_id_fkey;
ALTER TABLE purchase_orders ADD CONSTRAINT purchase_orders_purchase_id_fkey
  FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE SET NULL DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE purchases DROP CONSTRAINT IF EXISTS purchases_purchase_order_id_fkey;
ALTER TABLE purchases ADD CONSTRAINT purchases_purchase_order_id_fkey
  FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE SET NULL DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE payment_reminders DROP CONSTRAINT IF EXISTS payment_reminders_customer_id_fkey;
ALTER TABLE payment_reminders ADD CONSTRAINT payment_reminders_customer_id_fkey
  FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE;
ALTER TABLE payment_reminders DROP CONSTRAINT IF EXISTS payment_reminders_sale_id_fkey;
ALTER TABLE payment_reminders ADD CONSTRAINT payment_reminders_sale_id_fkey
  FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE;
ALTER TABLE stock_reconciliation DROP CONSTRAINT IF EXISTS stock_reconciliation_product_id_fkey;
ALTER TABLE stock_reconciliation ADD CONSTRAINT stock_reconciliation_product_id_fkey
  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
-- returns are removed together with their sale (#9)
ALTER TABLE product_returns DROP CONSTRAINT IF EXISTS product_returns_original_sale_id_fkey;
ALTER TABLE product_returns ADD CONSTRAINT product_returns_original_sale_id_fkey
  FOREIGN KEY (original_sale_id) REFERENCES sales(id) ON DELETE CASCADE;
ALTER TABLE product_returns DROP CONSTRAINT IF EXISTS product_returns_sale_id_fkey;
ALTER TABLE product_returns ADD CONSTRAINT product_returns_sale_id_fkey
  FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE;
-- products with history can still be deleted
ALTER TABLE product_returns DROP CONSTRAINT IF EXISTS product_returns_product_id_fkey;
ALTER TABLE product_returns ADD CONSTRAINT product_returns_product_id_fkey
  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL;
ALTER TABLE damaged_products DROP CONSTRAINT IF EXISTS damaged_products_product_id_fkey;
ALTER TABLE damaged_products ADD CONSTRAINT damaged_products_product_id_fkey
  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL;

-- sequential, human-readable invoice numbers (#19)
CREATE SEQUENCE IF NOT EXISTS sales_invoice_no_seq;
ALTER TABLE sales ALTER COLUMN invoice_no SET DEFAULT nextval('sales_invoice_no_seq');
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM sales WHERE invoice_no IS NULL) THEN
    WITH numbered AS (
      SELECT id, row_number() OVER (ORDER BY created_at, id)
               + COALESCE((SELECT max(invoice_no) FROM sales), 0) AS n
      FROM sales WHERE invoice_no IS NULL)
    UPDATE sales s SET invoice_no = numbered.n FROM numbered WHERE s.id = numbered.id;
  END IF;
  PERFORM setval('sales_invoice_no_seq', GREATEST(COALESCE((SELECT max(invoice_no) FROM sales), 0), 1),
                 (SELECT max(invoice_no) FROM sales) IS NOT NULL);
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_invoice_no ON sales(invoice_no);

UPDATE customers SET portal_token = gen_random_uuid() WHERE portal_token IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_portal_token ON customers(portal_token);

-- ----- indexes -----
CREATE INDEX IF NOT EXISTS idx_sales_created ON sales(created_at);
CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_id);
CREATE INDEX IF NOT EXISTS idx_sales_customer_due ON sales(customer_id, due_amount) WHERE due_amount > 0;
CREATE INDEX IF NOT EXISTS idx_purchases_created ON purchases(created_at);
CREATE INDEX IF NOT EXISTS idx_purchases_supplier ON purchases(supplier_id);
CREATE INDEX IF NOT EXISTS idx_expenses_created ON expenses(created_at);
CREATE INDEX IF NOT EXISTS idx_batches_product_fifo ON inventory_batches(product_id, created_at, id) WHERE remaining > 0;
CREATE INDEX IF NOT EXISTS idx_batches_purchase ON inventory_batches(purchase_id);
CREATE INDEX IF NOT EXISTS idx_batches_expiry ON inventory_batches(expiry_date) WHERE expiry_date IS NOT NULL AND remaining > 0;
CREATE INDEX IF NOT EXISTS idx_payments_sale_id ON payments(sale_id);
CREATE INDEX IF NOT EXISTS idx_payments_customer ON payments(customer_id);
CREATE INDEX IF NOT EXISTS idx_supplier_payments_purchase ON supplier_payments(purchase_id);
CREATE INDEX IF NOT EXISTS idx_account_tx_account ON account_transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_account_tx_date ON account_transactions(created_at);
CREATE INDEX IF NOT EXISTS idx_account_tx_ref ON account_transactions(ref_type, ref_id);
CREATE INDEX IF NOT EXISTS idx_returns_original_sale ON product_returns(original_sale_id);
CREATE INDEX IF NOT EXISTS idx_returns_sale ON product_returns(sale_id);
CREATE INDEX IF NOT EXISTS idx_returns_date ON product_returns(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON audit_log(created_at DESC);
-- the old GIN index on sales.items never served jsonb_array_elements()
DROP INDEX IF EXISTS idx_sales_items_gin;
DROP INDEX IF EXISTS idx_batches_fifo;

-- ---------------------------------------------------------------------
-- 2. Small helpers
-- ---------------------------------------------------------------------

-- Trigger bypass for restore / factory reset / this migration only.
CREATE OR REPLACE FUNCTION public.app_bulk_mode() RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT coalesce(current_setting('app.bulk_mode', true), '') = 'on'
$$;

-- IST calendar helpers (#18). All app timestamps are timestamptz.
CREATE OR REPLACE FUNCTION public.ist_date(p_ts timestamptz) RETURNS date
LANGUAGE sql IMMUTABLE AS $$ SELECT (p_ts AT TIME ZONE 'Asia/Kolkata')::date $$;

CREATE OR REPLACE FUNCTION public.ist_day_start(p_day date) RETURNS timestamptz
LANGUAGE sql IMMUTABLE AS $$ SELECT p_day::timestamp AT TIME ZONE 'Asia/Kolkata' $$;

CREATE OR REPLACE FUNCTION public.ist_today() RETURNS date
LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'Asia/Kolkata')::date $$;

CREATE OR REPLACE FUNCTION public.ist_month_start(p_day date) RETURNS timestamptz
LANGUAGE sql IMMUTABLE AS $$ SELECT date_trunc('month', p_day::timestamp) AT TIME ZONE 'Asia/Kolkata' $$;

-- Canonical payment methods (#12): cash | upi | bank | credit | split
CREATE OR REPLACE FUNCTION public.norm_payment_method(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p IS NULL OR btrim(p) = '' THEN 'cash'
    WHEN lower(btrim(p)) IN ('cash','cod','cash on delivery') THEN 'cash'
    WHEN lower(btrim(p)) IN ('upi','digital','online','gpay','google pay','phonepe','paytm','qr','wallet') THEN 'upi'
    WHEN lower(btrim(p)) IN ('bank','card','debit card','credit card','neft','imps','rtgs','cheque','check','transfer','bank transfer') THEN 'bank'
    WHEN lower(btrim(p)) IN ('credit','udhaar','due') THEN 'credit'
    WHEN lower(btrim(p)) IN ('split','mixed') THEN 'split'
    ELSE lower(btrim(p))
  END
$$;

-- Which money account a payment method moves.
CREATE OR REPLACE FUNCTION public.account_type_for_method(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE public.norm_payment_method(p) WHEN 'upi' THEN 'bank' WHEN 'bank' THEN 'bank' ELSE 'cash' END
$$;

CREATE OR REPLACE FUNCTION public.jnum(p jsonb, p_key text, p_default numeric DEFAULT 0) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF p IS NULL OR NOT (p ? p_key) OR jsonb_typeof(p -> p_key) = 'null' THEN RETURN p_default; END IF;
  RETURN (p ->> p_key)::numeric;
EXCEPTION WHEN others THEN
  RETURN p_default;
END $$;

-- ---------------------------------------------------------------------
-- 3. Security (#2, #3)
-- ---------------------------------------------------------------------

-- Admin = role admin AND active. Deactivated users lose access at once.
CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM profiles
                 WHERE id = auth.uid() AND role = 'admin' AND coalesce(active, true))
$$;

-- Any signed-in, active member of the shop (admin or staff).
CREATE OR REPLACE FUNCTION public.is_active_member() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM profiles
                 WHERE id = auth.uid() AND coalesce(active, true))
$$;

CREATE OR REPLACE FUNCTION public.assert_admin() RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- auth.uid() is NULL for the SQL editor / service role: allowed.
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin permission required' USING ERRCODE = '42501';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.assert_member() RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_active_member() THEN
    RAISE EXCEPTION 'Your account is not active. Ask the shop admin to activate it.' USING ERRCODE = '42501';
  END IF;
END $$;

-- Signup never trusts client metadata for role (#2).
-- New accounts are inactive staff until an admin activates them; only the
-- very first account of a brand-new shop becomes an active admin.
CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_first boolean;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('handle_new_user'));
  v_first := NOT EXISTS (SELECT 1 FROM profiles WHERE role = 'admin');
  INSERT INTO profiles (id, name, role, active, email)
  VALUES (
    NEW.id,
    coalesce(nullif(NEW.raw_user_meta_data->>'name', ''), NEW.email, 'User'),
    CASE WHEN v_first THEN 'admin' ELSE 'staff' END,
    v_first,
    NEW.email
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END $$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Column guard on profiles instead of the recursive RLS WITH CHECK (#3).
CREATE OR REPLACE FUNCTION public.profiles_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.app_bulk_mode() OR auth.uid() IS NULL THEN
    RETURN NEW;                                   -- SQL editor / service role
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NOT public.is_admin() THEN
      NEW.role := 'staff';
      NEW.active := false;
    END IF;
    RETURN NEW;
  END IF;

  IF NOT public.is_admin() THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.role IS DISTINCT FROM OLD.role
       OR NEW.active IS DISTINCT FROM OLD.active
       OR NEW.shop_id IS DISTINCT FROM OLD.shop_id THEN
      RAISE EXCEPTION 'Only an admin can change role, active status or shop' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- never remove the last active admin
  IF (OLD.role = 'admin' AND coalesce(OLD.active, true))
     AND (NEW.role <> 'admin' OR NOT coalesce(NEW.active, true))
     AND NOT EXISTS (SELECT 1 FROM profiles
                     WHERE role = 'admin' AND coalesce(active, true) AND id <> OLD.id) THEN
    RAISE EXCEPTION 'Cannot demote or deactivate the last active admin';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER profiles_guard
  BEFORE INSERT OR UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_guard();

CREATE OR REPLACE FUNCTION public.profiles_guard_delete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.app_bulk_mode()
     AND OLD.role = 'admin' AND coalesce(OLD.active, true)
     AND NOT EXISTS (SELECT 1 FROM profiles
                     WHERE role = 'admin' AND coalesce(active, true) AND id <> OLD.id) THEN
    RAISE EXCEPTION 'Cannot delete the last active admin';
  END IF;
  RETURN OLD;
END $$;

CREATE TRIGGER profiles_guard_delete
  BEFORE DELETE ON profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_guard_delete();

-- Admin staff management (#2). Creating the auth user still happens from
-- the app with a separate, non-persisted client (or the admin-staff Edge
-- Function); these RPCs do the privileged parts.
CREATE OR REPLACE FUNCTION public.admin_set_staff(
  p_user_id uuid, p_name text DEFAULT NULL, p_role text DEFAULT NULL,
  p_active boolean DEFAULT NULL, p_pin text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_admin();
  IF p_role IS NOT NULL AND p_role NOT IN ('admin','staff') THEN
    RAISE EXCEPTION 'Role must be admin or staff';
  END IF;
  UPDATE profiles SET
    name   = coalesce(nullif(btrim(p_name), ''), name),
    role   = coalesce(p_role, role),
    active = coalesce(p_active, active),
    pin    = coalesce(p_pin, pin)
  WHERE id = p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Staff profile not found'; END IF;
END $$;

-- Removes the profile and (when permitted) the login itself.
CREATE OR REPLACE FUNCTION public.admin_delete_staff(p_user_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_admin();
  IF p_user_id = auth.uid() THEN RAISE EXCEPTION 'You cannot delete your own account'; END IF;
  -- keep history readable: detach authored rows
  UPDATE sales SET created_by = NULL WHERE created_by = p_user_id;
  UPDATE purchases SET created_by = NULL WHERE created_by = p_user_id;
  UPDATE expenses SET created_by = NULL WHERE created_by = p_user_id;
  UPDATE payments SET created_by = NULL WHERE created_by = p_user_id;
  UPDATE supplier_payments SET created_by = NULL WHERE created_by = p_user_id;
  UPDATE account_transactions SET created_by = NULL WHERE created_by = p_user_id;
  UPDATE accounts SET created_by = NULL WHERE created_by = p_user_id;
  UPDATE product_returns SET created_by = NULL WHERE created_by = p_user_id;
  UPDATE damaged_products SET created_by = NULL WHERE created_by = p_user_id;
  UPDATE transaction_edits SET edited_by = NULL WHERE edited_by = p_user_id;
  BEGIN
    DELETE FROM auth.users WHERE id = p_user_id;     -- cascades to profiles
    RETURN 'deleted';
  EXCEPTION WHEN insufficient_privilege OR undefined_table THEN
    -- without rights on auth.users: remove the profile; the login can no
    -- longer read or write anything because every policy needs a profile
    DELETE FROM profiles WHERE id = p_user_id;
    RETURN 'profile_removed';
  END;
END $$;

-- ---------------------------------------------------------------------
-- 4. Money accounts: one balance-maintaining trigger, document postings
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resolve_account(p_type text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v uuid;
BEGIN
  SELECT id INTO v FROM accounts WHERE account_type = p_type ORDER BY created_at, id LIMIT 1;
  IF v IS NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('resolve_account:' || p_type));
    SELECT id INTO v FROM accounts WHERE account_type = p_type ORDER BY created_at, id LIMIT 1;
    IF v IS NULL THEN
      INSERT INTO accounts (name, account_type, balance)
      VALUES (CASE p_type WHEN 'bank' THEN 'Bank Account' ELSE 'Cash in Hand' END, p_type, 0)
      RETURNING id INTO v;
    END IF;
  END IF;
  RETURN v;
END $$;

-- Categories that documents now post by themselves (server-side, #10).
CREATE OR REPLACE FUNCTION public.is_document_category(p text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT p IN ('sale','sale_edit','sale_reversal',
               'purchase','purchase_edit','purchase_reversal',
               'expense','expense_edit','expense_reversal',
               'credit_collection','credit_collection_edit','credit_collection_reversal',
               'credit_payment','credit_payment_edit','credit_payment_reversal',
               'return_refund','return_refund_edit','return_refund_reversal','return_reversal')
$$;

-- BEFORE INSERT on account_transactions: old app versions still try to
-- post sales/purchases/expenses themselves (directly or via the offline
-- queue). Those rows are dropped because the database already posted them.
CREATE OR REPLACE FUNCTION public.account_tx_before_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.app_bulk_mode() THEN RETURN NEW; END IF;
  IF NEW.type NOT IN ('in','out') THEN
    RAISE EXCEPTION 'Transaction type must be in or out';
  END IF;
  IF NEW.ref_type IS NULL
     AND coalesce(NEW.source, '') NOT IN ('manual','transfer','system','import')
     AND public.is_document_category(NEW.category) THEN
    RETURN NULL;     -- duplicate posting from an old client: skip silently
  END IF;
  NEW.created_by := coalesce(NEW.created_by, auth.uid());
  NEW.source := coalesce(NEW.source, 'manual');
  RETURN NEW;
END $$;

-- Every insert/update/delete of a transaction moves the balance, so the
-- balance can never drift from the journal again (#10, #20).
CREATE OR REPLACE FUNCTION public.account_tx_balance() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.app_bulk_mode() THEN RETURN NULL; END IF;   -- restore loads balances as saved
  IF TG_OP IN ('UPDATE','DELETE') THEN
    UPDATE accounts SET balance = coalesce(balance,0)
           - CASE WHEN OLD.type = 'in' THEN OLD.amount ELSE -OLD.amount END
     WHERE id = OLD.account_id;
  END IF;
  IF TG_OP IN ('INSERT','UPDATE') THEN
    UPDATE accounts SET balance = coalesce(balance,0)
           + CASE WHEN NEW.type = 'in' THEN NEW.amount ELSE -NEW.amount END
     WHERE id = NEW.account_id;
  END IF;
  RETURN NULL;
END $$;

-- Manual / legacy entry point. Kept signature-compatible with old apps.
CREATE OR REPLACE FUNCTION public.add_account_transaction(
  p_account_id uuid, p_type text, p_amount numeric, p_category text,
  p_description text DEFAULT NULL, p_created_by uuid DEFAULT NULL,
  p_source text DEFAULT NULL, p_created_at timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_admin();
  IF p_source IS NULL AND public.is_document_category(p_category) THEN
    RETURN;        -- an old app re-posting a document: already done server-side
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
  IF p_type NOT IN ('in','out') THEN RAISE EXCEPTION 'Type must be in or out'; END IF;
  IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = p_account_id) THEN
    RAISE EXCEPTION 'Account not found: %', p_account_id;
  END IF;
  INSERT INTO account_transactions (account_id, type, amount, category, description, created_by, source, created_at)
  VALUES (p_account_id, p_type, round(p_amount, 2), p_category, p_description,
          coalesce(auth.uid(), p_created_by), coalesce(p_source, 'manual'), coalesce(p_created_at, now()));
END $$;

-- Atomic transfer (#20). Was called by the app but never existed.
CREATE OR REPLACE FUNCTION public.transfer_between_accounts(
  p_from_account_id uuid, p_to_account_id uuid, p_amount numeric,
  p_description text DEFAULT 'Transfer', p_created_by uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_ref uuid := gen_random_uuid();
BEGIN
  PERFORM public.assert_admin();
  IF p_from_account_id = p_to_account_id THEN RAISE EXCEPTION 'Choose two different accounts'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
  IF (SELECT count(*) FROM accounts WHERE id IN (p_from_account_id, p_to_account_id)) <> 2 THEN
    RAISE EXCEPTION 'Account not found';
  END IF;
  INSERT INTO account_transactions (account_id, type, amount, category, description, created_by, ref_type, ref_id, source)
  VALUES (p_from_account_id, 'out', round(p_amount,2), 'transfer', coalesce(p_description,'Transfer'), auth.uid(), 'transfer', v_ref, 'transfer'),
         (p_to_account_id,   'in',  round(p_amount,2), 'transfer', coalesce(p_description,'Transfer'), auth.uid(), 'transfer', v_ref, 'transfer');
  RETURN v_ref;
END $$;

-- Bring a document's postings to exactly p_desired = {account_id: signed amount}.
-- "Already posted" = journal rows tagged with this document + the legacy
-- estimate for documents created by old app versions. Idempotent.
CREATE OR REPLACE FUNCTION public.reconcile_postings(
  p_ref_type text, p_ref_id uuid, p_desired jsonb, p_category text,
  p_description text, p_created_by uuid, p_at timestamptz)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  FOR r IN
    WITH want AS (
      SELECT key::uuid AS acc, value::numeric AS amt FROM jsonb_each_text(coalesce(p_desired, '{}'::jsonb))
    ), have AS (
      SELECT acc, sum(amt) AS amt FROM (
        SELECT account_id AS acc, CASE WHEN type = 'in' THEN amount ELSE -amount END AS amt
          FROM account_transactions WHERE ref_type = p_ref_type AND ref_id = p_ref_id
        UNION ALL
        SELECT account_id, amount FROM legacy_postings WHERE ref_type = p_ref_type AND ref_id = p_ref_id
      ) x GROUP BY acc
    )
    SELECT coalesce(w.acc, h.acc) AS acc,
           round(coalesce(w.amt, 0) - coalesce(h.amt, 0), 2) AS delta
    FROM want w FULL JOIN have h ON w.acc = h.acc
  LOOP
    IF abs(r.delta) >= 0.01 AND EXISTS (SELECT 1 FROM accounts WHERE id = r.acc) THEN
      INSERT INTO account_transactions
        (account_id, type, amount, category, description, created_by, created_at, ref_type, ref_id, source)
      VALUES (r.acc, CASE WHEN r.delta > 0 THEN 'in' ELSE 'out' END, abs(r.delta),
              p_category, p_description, p_created_by, coalesce(p_at, now()), p_ref_type, p_ref_id, 'system');
    END IF;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.money_split(p_amount numeric, p_cash numeric, p_digital numeric, p_method text, p_sign int)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_bank numeric := 0; v_cash numeric := 0; v jsonb := '{}'::jsonb;
BEGIN
  IF coalesce(p_amount, 0) < 0.005 THEN RETURN v; END IF;
  IF coalesce(p_cash,0) + coalesce(p_digital,0) > 0.004 THEN
    v_bank := least(greatest(coalesce(p_digital,0),0), p_amount);   -- change is always given in cash
    v_cash := p_amount - v_bank;
  ELSIF public.account_type_for_method(p_method) = 'bank' THEN
    v_bank := p_amount;
  ELSE
    v_cash := p_amount;
  END IF;
  IF v_cash >= 0.005 THEN v := v || jsonb_build_object(public.resolve_account('cash')::text, round(p_sign * v_cash, 2)); END IF;
  IF v_bank >= 0.005 THEN v := v || jsonb_build_object(public.resolve_account('bank')::text, round(p_sign * v_bank, 2)); END IF;
  RETURN v;
END $$;

-- What each document should have moved in the cash book.
CREATE OR REPLACE FUNCTION public.sale_postings(s public.sales) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.money_split(
    coalesce(s.paid_at_sale, CASE WHEN s.is_credit THEN s.amount_paid ELSE s.final_amount END),
    s.cash_amount, s.digital_amount, s.payment_method, 1)
$$;
CREATE OR REPLACE FUNCTION public.purchase_postings(p public.purchases) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.money_split(
    coalesce(p.paid_at_purchase, CASE WHEN p.is_credit THEN p.amount_paid ELSE p.total_amount END),
    0, 0, p.payment_method, -1)
$$;
CREATE OR REPLACE FUNCTION public.expense_postings(e public.expenses) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.money_split(e.amount, 0, 0, e.payment_method, -1)
$$;
CREATE OR REPLACE FUNCTION public.payment_postings(p public.payments) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.money_split(p.amount, 0, 0, p.payment_method, 1)
$$;
CREATE OR REPLACE FUNCTION public.supplier_payment_postings(p public.supplier_payments) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.money_split(p.amount, 0, 0, p.payment_method, -1)
$$;
CREATE OR REPLACE FUNCTION public.return_postings(r public.product_returns) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.money_split(r.refund_amount, 0, 0, r.refund_method, -1)
$$;

-- One AFTER trigger for every document table.
CREATE OR REPLACE FUNCTION public.document_postings_trigger() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row jsonb; v_id uuid; v_desired jsonb := '{}'::jsonb;
  v_base text; v_cat text; v_desc text; v_at timestamptz; v_by uuid;
BEGIN
  IF public.app_bulk_mode() THEN RETURN NULL; END IF;

  v_row := to_jsonb(CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END);
  v_id := (v_row->>'id')::uuid;

  -- separate statements: each is planned only for its own table's row type
  IF TG_OP <> 'DELETE' THEN
    IF TG_TABLE_NAME = 'sales' THEN
      v_desired := public.sale_postings(NEW);
    ELSIF TG_TABLE_NAME = 'purchases' THEN
      v_desired := public.purchase_postings(NEW);
    ELSIF TG_TABLE_NAME = 'expenses' THEN
      v_desired := public.expense_postings(NEW);
    ELSIF TG_TABLE_NAME = 'payments' THEN
      v_desired := public.payment_postings(NEW);
    ELSIF TG_TABLE_NAME = 'supplier_payments' THEN
      v_desired := public.supplier_payment_postings(NEW);
    ELSIF TG_TABLE_NAME = 'product_returns' THEN
      v_desired := public.return_postings(NEW);
    END IF;
  END IF;

  v_base := CASE TG_TABLE_NAME
    WHEN 'sales' THEN 'sale' WHEN 'purchases' THEN 'purchase' WHEN 'expenses' THEN 'expense'
    WHEN 'payments' THEN 'credit_collection' WHEN 'supplier_payments' THEN 'credit_payment'
    WHEN 'product_returns' THEN 'return_refund' END;
  v_cat := v_base || CASE TG_OP WHEN 'INSERT' THEN '' WHEN 'UPDATE' THEN '_edit' ELSE '_reversal' END;
  v_desc := CASE TG_TABLE_NAME
    WHEN 'sales' THEN 'Sale #' || coalesce(v_row->>'invoice_no', left(v_id::text, 8))
    WHEN 'purchases' THEN 'Purchase' || coalesce(' - ' || nullif(v_row->>'supplier_name',''), '') || ' #' || left(v_id::text, 8)
    WHEN 'expenses' THEN coalesce(nullif(v_row->>'category',''), 'Expense') || coalesce(' - ' || nullif(v_row->>'description',''), '')
    WHEN 'payments' THEN 'Credit collection #' || left(v_id::text, 8)
    WHEN 'supplier_payments' THEN 'Supplier payment #' || left(v_id::text, 8)
    WHEN 'product_returns' THEN 'Refund: ' || coalesce(v_row->>'product_name','item') || ' x' || coalesce(v_row->>'quantity','')
  END;
  IF TG_OP <> 'INSERT' THEN v_desc := v_desc || CASE TG_OP WHEN 'UPDATE' THEN ' (edited)' ELSE ' (deleted)' END; END IF;
  -- first posting is dated like the document (back-dated expenses, offline sales)
  v_at := CASE WHEN TG_OP = 'INSERT' THEN coalesce((v_row->>'created_at')::timestamptz, now()) ELSE now() END;
  v_by := coalesce(auth.uid(), (v_row->>'created_by')::uuid);

  PERFORM public.reconcile_postings(TG_TABLE_NAME, v_id, v_desired, v_cat, v_desc, v_by, v_at);
  RETURN NULL;
END $$;

-- Account maintenance (#20)
CREATE OR REPLACE FUNCTION public.merge_duplicate_accounts() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record; v_keep uuid; v_opening numeric; v_merged int := 0;
BEGIN
  PERFORM public.assert_admin();
  FOR r IN
    SELECT a.id, a.account_type, coalesce(a.balance,0) AS balance
    FROM accounts a
    WHERE a.account_type IN ('cash','bank')
      AND a.id <> (SELECT id FROM accounts b WHERE b.account_type = a.account_type ORDER BY created_at, id LIMIT 1)
  LOOP
    v_keep := public.resolve_account(r.account_type);
    -- part of the balance not explained by its journal (opening balance)
    SELECT r.balance - coalesce(sum(CASE WHEN type='in' THEN amount ELSE -amount END),0)
      INTO v_opening FROM account_transactions WHERE account_id = r.id;
    -- moving journal rows moves their effect on balances (trigger)
    UPDATE account_transactions SET account_id = v_keep WHERE account_id = r.id;
    UPDATE legacy_postings lp SET account_id = v_keep
     WHERE lp.account_id = r.id
       AND NOT EXISTS (SELECT 1 FROM legacy_postings x WHERE x.ref_type = lp.ref_type AND x.ref_id = lp.ref_id AND x.account_id = v_keep);
    UPDATE accounts SET balance = coalesce(balance,0) + v_opening WHERE id = v_keep;
    DELETE FROM accounts WHERE id = r.id;
    v_merged := v_merged + 1;
  END LOOP;
  RETURN v_merged;
END $$;

-- balance vs journal per account; difference = opening balance or drift
CREATE OR REPLACE FUNCTION public.get_account_reconciliation()
RETURNS TABLE(account_id uuid, account_name text, account_type text, balance numeric,
              journal_net numeric, difference numeric, transaction_count bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.assert_admin();
  RETURN QUERY
  SELECT a.id, a.name, a.account_type, coalesce(a.balance,0)::numeric,
         coalesce(j.net,0)::numeric, (coalesce(a.balance,0) - coalesce(j.net,0))::numeric,
         coalesce(j.cnt,0)::bigint
  FROM accounts a
  LEFT JOIN (SELECT t.account_id AS aid, sum(CASE WHEN t.type='in' THEN t.amount ELSE -t.amount END) AS net, count(*) AS cnt
             FROM account_transactions t GROUP BY t.account_id) j ON j.aid = a.id
  ORDER BY a.account_type, a.created_at;
END $$;

-- Server-side totals so summaries/exports are never capped at 100 rows (#20).
-- Transfers between own accounts are reported separately, not as in/out.
CREATE OR REPLACE FUNCTION public.get_account_summary(
  p_start timestamptz DEFAULT NULL, p_end timestamptz DEFAULT NULL, p_account_id uuid DEFAULT NULL)
RETURNS TABLE(total_in numeric, total_out numeric, net numeric, transfers_in numeric,
              transfers_out numeric, transaction_count bigint, by_category jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.assert_admin();
  RETURN QUERY
  WITH tx AS (
    SELECT t.* FROM account_transactions t
    WHERE (p_start IS NULL OR t.created_at >= p_start)
      AND (p_end IS NULL OR t.created_at < p_end)
      AND (p_account_id IS NULL OR t.account_id = p_account_id)
  )
  SELECT
    coalesce(sum(amount) FILTER (WHERE type='in'  AND category <> 'transfer'),0),
    coalesce(sum(amount) FILTER (WHERE type='out' AND category <> 'transfer'),0),
    coalesce(sum(CASE WHEN type='in' THEN amount ELSE -amount END) FILTER (WHERE category <> 'transfer'),0),
    coalesce(sum(amount) FILTER (WHERE type='in'  AND category = 'transfer'),0),
    coalesce(sum(amount) FILTER (WHERE type='out' AND category = 'transfer'),0),
    count(*),
    coalesce((SELECT jsonb_object_agg(k, v) FROM (
       SELECT category || '_' || type AS k, sum(amount) AS v FROM tx GROUP BY category, type) c), '{}'::jsonb)
  FROM tx;
END $$;

-- ---------------------------------------------------------------------
-- 5. Stock: units, FIFO allocation and exact restores (#22, #9, #14)
-- ---------------------------------------------------------------------
-- Stock is kept in the PRODUCT'S OWN unit (as before). A sale/purchase
-- line can be in another unit (e.g. a box of 12 of a "pieces" product);
-- new app versions send line.stock_factor = stock units per line unit.
-- Every sale line records which batches it consumed ("allocs"), so
-- deletes, edits and returns put stock back into exactly those batches
-- and cost of goods is true FIFO even when a line spans several batches.

CREATE OR REPLACE FUNCTION public.is_piece_unit(p text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT lower(coalesce(btrim(p), '')) IN ('', 'pieces', 'piece', 'pcs', 'pc', 'nos') $$;

-- stock units consumed by one unit of this line
CREATE OR REPLACE FUNCTION public.item_stock_factor(p_item jsonb, p_product_unit_type text) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v numeric;
BEGIN
  v := public.jnum(p_item, 'stock_factor', NULL);
  IF v IS NOT NULL AND v > 0 THEN RETURN v; END IF;
  -- legacy lines: only a bigger line unit of a piece-based product converts
  IF NOT public.is_piece_unit(p_item->>'unit_type') AND public.is_piece_unit(p_product_unit_type) THEN
    RETURN greatest(public.jnum(p_item, 'pieces_per_unit', 1), 1);
  END IF;
  RETURN 1;
END $$;

CREATE OR REPLACE FUNCTION public.item_line_total(p_item jsonb) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(public.jnum(p_item, 'total', NULL),
                  public.jnum(p_item, 'price', 0) * public.jnum(p_item, 'qty', 0)
                  - public.jnum(p_item, 'discount_amount', 0))
$$;

-- line's quantity in stock units
CREATE OR REPLACE FUNCTION public.item_base_qty(p_item jsonb) RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_ut text;
BEGIN
  IF p_item ? 'base_qty' THEN RETURN public.jnum(p_item, 'base_qty', 0); END IF;
  SELECT unit_type INTO v_ut FROM products WHERE id = (p_item->>'product_id')::uuid;
  RETURN public.jnum(p_item, 'qty', 0) * public.item_stock_factor(p_item, v_ut);
EXCEPTION WHEN invalid_text_representation THEN
  RETURN 0;
END $$;

-- put qty back into one batch; anything that no longer fits becomes an
-- orphan batch at the same unit cost
CREATE OR REPLACE FUNCTION public.restore_to_batch(p_batch uuid, p_product uuid, p_qty numeric, p_price numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_q numeric; v_r numeric; v_take numeric := 0;
BEGIN
  IF p_qty <= 0 THEN RETURN; END IF;
  SELECT quantity, remaining INTO v_q, v_r FROM inventory_batches WHERE id = p_batch FOR UPDATE;
  IF FOUND THEN
    v_take := least(greatest(v_q - v_r, 0), p_qty);
    IF v_take > 0 THEN UPDATE inventory_batches SET remaining = remaining + v_take WHERE id = p_batch; END IF;
  END IF;
  IF p_qty - v_take > 0 AND EXISTS (SELECT 1 FROM products WHERE id = p_product) THEN
    INSERT INTO inventory_batches (product_id, quantity, remaining, purchase_price)
    VALUES (p_product, p_qty - v_take, p_qty - v_take, coalesce(p_price, 0));
  END IF;
END $$;

-- legacy restore (no allocation record): newest partially used batches first
CREATE OR REPLACE FUNCTION public.restore_stock_fifo(p_product_id uuid, p_qty numeric, p_price numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b record; v_left numeric := p_qty; v_take numeric;
BEGIN
  IF p_qty <= 0 THEN RETURN; END IF;
  FOR b IN SELECT id, quantity, remaining FROM inventory_batches
           WHERE product_id = p_product_id AND remaining < quantity
           ORDER BY created_at DESC, id DESC FOR UPDATE
  LOOP
    EXIT WHEN v_left <= 0;
    v_take := least(b.quantity - b.remaining, v_left);
    UPDATE inventory_batches SET remaining = remaining + v_take WHERE id = b.id;
    v_left := v_left - v_take;
  END LOOP;
  IF v_left > 0 AND EXISTS (SELECT 1 FROM products WHERE id = p_product_id) THEN
    INSERT INTO inventory_batches (product_id, quantity, remaining, purchase_price)
    VALUES (p_product_id, v_left, v_left, coalesce(p_price, 0));
  END IF;
END $$;

-- FIFO take of p_qty stock units; returns allocations and their cost
CREATE OR REPLACE FUNCTION public.fifo_take(p_product uuid, p_qty numeric, p_fallback_price numeric,
  OUT allocs jsonb, OUT cost numeric, OUT uncovered numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b record; v_left numeric := p_qty; v_take numeric;
BEGIN
  allocs := '[]'::jsonb; cost := 0; uncovered := 0;
  IF p_qty <= 0 THEN RETURN; END IF;
  FOR b IN SELECT id, remaining, purchase_price FROM inventory_batches
           WHERE product_id = p_product AND remaining > 0
           ORDER BY created_at, id FOR UPDATE
  LOOP
    EXIT WHEN v_left <= 0;
    v_take := least(b.remaining, v_left);
    UPDATE inventory_batches SET remaining = remaining - v_take WHERE id = b.id;
    allocs := allocs || jsonb_build_array(jsonb_build_object('b', b.id, 'q', v_take, 'p', b.purchase_price));
    cost := cost + v_take * b.purchase_price;
    v_left := v_left - v_take;
  END LOOP;
  IF v_left > 0 THEN
    uncovered := v_left;
    cost := cost + v_left * coalesce(p_fallback_price, 0);
  END IF;
END $$;

-- Kept for old callers (damaged entries, reconcile). Batches only.
CREATE OR REPLACE FUNCTION public.deduct_stock_fifo(p_product_id uuid, p_qty numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN PERFORM public.fifo_take(p_product_id, p_qty, 0); END $$;

-- Deduct stock for every line and stamp true FIFO cost + allocations.
CREATE OR REPLACE FUNCTION public.sale_apply_items(p_items jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_items jsonb := coalesce(p_items, '[]'::jsonb);
  v_item jsonb; i int; v_prod record; v_qty numeric; v_factor numeric; v_base numeric;
  v_new_stock numeric; v_over numeric; v_fb numeric; t record;
BEGIN
  IF jsonb_typeof(v_items) <> 'array' THEN RAISE EXCEPTION 'Sale items must be a list'; END IF;
  FOR i IN 0 .. jsonb_array_length(v_items) - 1 LOOP
    v_item := v_items -> i;
    v_qty := public.jnum(v_item, 'qty', 0);
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Item % has an invalid quantity', coalesce(v_item->>'name', i::text); END IF;
    BEGIN
      SELECT id, stock, unit_type, purchase_price INTO v_prod
      FROM products WHERE id = (v_item->>'product_id')::uuid FOR UPDATE;
    EXCEPTION WHEN invalid_text_representation THEN
      v_prod := NULL;
    END;
    IF v_prod.id IS NULL THEN
      CONTINUE;          -- product deleted or a free-text line: nothing to deduct
    END IF;

    v_factor := public.item_stock_factor(v_item, v_prod.unit_type);
    v_base := round(v_qty * v_factor, 3);

    v_new_stock := v_prod.stock - v_base;
    v_over := 0;
    IF v_new_stock < 0 THEN v_over := -v_new_stock; v_new_stock := 0; END IF;
    UPDATE products SET stock = v_new_stock WHERE id = v_prod.id;

    -- fallback cost per stock unit for anything not covered by batches
    v_fb := coalesce(nullif(v_prod.purchase_price, 0),
                     public.jnum(v_item, 'purchase_price', 0) / nullif(v_factor, 0), 0);
    SELECT * INTO t FROM public.fifo_take(v_prod.id, v_base, v_fb);

    v_item := v_item || jsonb_build_object(
      'stock_factor', v_factor,
      'base_qty', v_base,
      'allocs', t.allocs,
      'cost_total', round(t.cost, 2),
      'purchase_price', round(t.cost / v_qty, 4),
      'returned_base', 0);
    IF v_over > 0 THEN v_item := v_item || jsonb_build_object('oversold_qty', v_over); END IF;
    v_items := jsonb_set(v_items, ARRAY[i::text], v_item);
  END LOOP;
  RETURN v_items;
END $$;

-- Put back up to p_base stock units of one product from a sale's lines
-- (last line, last allocation first). Returns updated items + cost restored.
CREATE OR REPLACE FUNCTION public.sale_restore_product(p_items jsonb, p_product uuid, p_base numeric,
  OUT items jsonb, OUT cost numeric, OUT restored numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  i int; a int; v_item jsonb; v_allocs jsonb; v_line_base numeric; v_ret numeric; v_avail numeric;
  v_take numeric; v_left numeric; v_aq numeric; v_t numeric; v_price numeric; v_unit_cost numeric;
  v_need numeric := p_base;
BEGIN
  items := coalesce(p_items, '[]'::jsonb); cost := 0; restored := 0;
  IF p_base <= 0 OR jsonb_array_length(items) = 0 THEN RETURN; END IF;

  FOR i IN REVERSE jsonb_array_length(items) - 1 .. 0 LOOP
    EXIT WHEN v_need <= 0.0005;
    v_item := items -> i;
    CONTINUE WHEN (v_item->>'product_id') IS DISTINCT FROM p_product::text;
    v_line_base := public.item_base_qty(v_item);
    v_ret := public.jnum(v_item, 'returned_base', 0);
    v_avail := v_line_base - v_ret;
    CONTINUE WHEN v_avail <= 0;
    v_take := least(v_avail, v_need);
    v_unit_cost := CASE WHEN v_line_base > 0
                        THEN public.jnum(v_item, 'purchase_price', 0) * public.jnum(v_item, 'qty', 0) / v_line_base
                        ELSE 0 END;
    v_left := v_take;
    IF jsonb_typeof(v_item->'allocs') = 'array' THEN
      v_allocs := v_item->'allocs';
      FOR a IN REVERSE jsonb_array_length(v_allocs) - 1 .. 0 LOOP
        EXIT WHEN v_left <= 0;
        v_aq := public.jnum(v_allocs -> a, 'q', 0);
        CONTINUE WHEN v_aq <= 0;
        v_t := least(v_aq, v_left);
        v_price := public.jnum(v_allocs -> a, 'p', v_unit_cost);
        PERFORM public.restore_to_batch((v_allocs -> a ->> 'b')::uuid, p_product, v_t, v_price);
        cost := cost + v_t * v_price;
        v_left := v_left - v_t;
        v_allocs := jsonb_set(v_allocs, ARRAY[a::text, 'q'], to_jsonb(v_aq - v_t));
      END LOOP;
      v_item := jsonb_set(v_item, '{allocs}', v_allocs);
    END IF;
    IF v_left > 0 THEN                                   -- legacy line or short allocation
      PERFORM public.restore_stock_fifo(p_product, v_left, v_unit_cost);
      cost := cost + v_left * v_unit_cost;
    END IF;
    v_item := v_item || jsonb_build_object('returned_base', v_ret + v_take);
    items := jsonb_set(items, ARRAY[i::text], v_item);
    v_need := v_need - v_take;
    restored := restored + v_take;
  END LOOP;

  IF restored > 0 THEN
    UPDATE products SET stock = stock + restored WHERE id = p_product;
  END IF;
END $$;

-- Put back everything a sale still holds (used by delete and edit).
-- p_returned_base: stock units already returned per product by OLD-style
-- returns that did not record themselves on the lines.
CREATE OR REPLACE FUNCTION public.sale_restore_all(p_items jsonb, p_untracked_returned jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_items jsonb := coalesce(p_items, '[]'::jsonb); r record; t record;
BEGIN
  FOR r IN
    SELECT (x->>'product_id') AS pid,
           sum(public.item_base_qty(x) - public.jnum(x, 'returned_base', 0)) AS held
    FROM jsonb_array_elements(v_items) x
    WHERE (x->>'product_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    GROUP BY 1
  LOOP
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM products WHERE id = r.pid::uuid);
    SELECT * INTO t FROM public.sale_restore_product(
      v_items, r.pid::uuid,
      greatest(r.held - public.jnum(p_untracked_returned, r.pid, 0), 0));
    v_items := t.items;
  END LOOP;
  RETURN v_items;
END $$;

-- ---------------------------------------------------------------------
-- 6. GST split (#15): CGST+SGST within the shop's state, IGST otherwise;
--    computed AFTER bill discount / extras on both UIs, stored per sale.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.shop_state_code() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT nullif(btrim(state_code), '') FROM shop_settings WHERE id = 1), '33')
$$;

CREATE OR REPLACE FUNCTION public.compute_tax(p_items jsonb, p_final numeric, p_party_state text, p_exempt boolean,
  OUT cgst numeric, OUT sgst numeric, OUT igst numeric, OUT taxable numeric, OUT pos text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_lines numeric; v_tax numeric; v_shop text := public.shop_state_code();
BEGIN
  cgst := 0; sgst := 0; igst := 0;
  pos := coalesce(nullif(btrim(p_party_state), ''), v_shop);
  SELECT coalesce(sum(public.item_line_total(x)), 0),
         coalesce(sum(public.item_line_total(x) * public.jnum(x, 'gst_rate', 0) / (100 + public.jnum(x, 'gst_rate', 0))), 0)
    INTO v_lines, v_tax
  FROM jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) x;
  IF coalesce(p_exempt, false) OR v_lines <= 0 OR v_tax <= 0 THEN
    taxable := coalesce(p_final, 0);
    RETURN;
  END IF;
  v_tax := round(v_tax * coalesce(p_final, 0) / v_lines, 2);   -- spread bill discount/extras
  IF pos <> v_shop THEN
    igst := v_tax;
  ELSE
    cgst := round(v_tax / 2, 2);
    sgst := v_tax - cgst;
  END IF;
  taxable := coalesce(p_final, 0) - v_tax;
END $$;

-- ---------------------------------------------------------------------
-- 7. Sales
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sales_before_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t record; v_state text;
BEGIN
  IF public.app_bulk_mode() THEN RETURN NEW; END IF;
  PERFORM public.assert_member();

  NEW.created_by := coalesce(auth.uid(), NEW.created_by);
  NEW.payment_method := public.norm_payment_method(NEW.payment_method);
  NEW.final_amount := greatest(round(coalesce(NEW.final_amount, 0), 2), 0);
  NEW.is_credit := coalesce(NEW.is_credit, false) OR NEW.payment_method = 'credit';
  IF NEW.is_credit THEN
    NEW.amount_paid := least(greatest(coalesce(NEW.amount_paid, 0), 0), NEW.final_amount);
    NEW.due_amount := NEW.final_amount - NEW.amount_paid;
    NEW.due_date := coalesce(NEW.due_date, (public.ist_today() + 30));
  ELSE
    NEW.amount_paid := NEW.final_amount;
    NEW.due_amount := 0;
  END IF;
  NEW.paid_at_sale := coalesce(NEW.paid_at_sale, NEW.amount_paid);
  NEW.cash_amount := greatest(coalesce(NEW.cash_amount, 0), 0);
  NEW.digital_amount := greatest(coalesce(NEW.digital_amount, 0), 0);

  -- GST is decided by the server so both billing screens agree (#15)
  SELECT state_code INTO v_state FROM customers WHERE id = NEW.customer_id;
  SELECT * INTO t FROM public.compute_tax(NEW.items, NEW.final_amount, v_state, NEW.tax_exempt);
  NEW.cgst_amount := t.cgst; NEW.sgst_amount := t.sgst; NEW.igst_amount := t.igst;
  NEW.taxable_amount := t.taxable; NEW.place_of_supply := t.pos;

  NEW.total_discount := coalesce(NEW.total_discount,
    (SELECT sum(public.jnum(x, 'discount_amount', 0)) FROM jsonb_array_elements(NEW.items) x), 0);

  -- stock + FIFO cost, atomically with the insert
  NEW.items := public.sale_apply_items(NEW.items);
  NEW.updated_at := now();
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.sales_before_update() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.app_bulk_mode() THEN RETURN NEW; END IF;
  -- line items change stock: only the edit/return RPCs may touch them (#7)
  IF NEW.items IS DISTINCT FROM OLD.items
     AND coalesce(current_setting('app.doc_rpc', true), '') <> 'on' THEN
    RAISE EXCEPTION 'Sale items can only be changed with edit_sale_atomic' USING ERRCODE = 'P0001';
  END IF;
  NEW.payment_method := public.norm_payment_method(NEW.payment_method);
  NEW.final_amount := greatest(coalesce(NEW.final_amount, 0), 0);
  NEW.due_amount := greatest(coalesce(NEW.due_amount, 0), 0);
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- customer balance follows every change, including a customer switch
CREATE OR REPLACE FUNCTION public.refresh_customer_credit(p_customer uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE customers SET total_credit = (
    SELECT coalesce(sum(due_amount), 0) FROM sales WHERE customer_id = p_customer AND due_amount > 0)
  WHERE id = p_customer;
$$;

CREATE OR REPLACE FUNCTION public.update_customer_credit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.app_bulk_mode() THEN RETURN NULL; END IF;
  IF TG_OP IN ('UPDATE','DELETE') AND OLD.customer_id IS NOT NULL THEN
    PERFORM public.refresh_customer_credit(OLD.customer_id);
  END IF;
  IF TG_OP IN ('INSERT','UPDATE') AND NEW.customer_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.customer_id IS DISTINCT FROM OLD.customer_id
          OR NEW.due_amount IS DISTINCT FROM OLD.due_amount) THEN
    PERFORM public.refresh_customer_credit(NEW.customer_id);
  END IF;
  RETURN NULL;
END $$;

-- returned stock units per product NOT recorded on the lines (old returns)
CREATE OR REPLACE FUNCTION public.sale_untracked_returns(p_sale uuid, p_items jsonb) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH ret AS (
    SELECT r.product_id::text AS pid, sum(r.quantity) AS qty
    FROM product_returns r
    WHERE (r.original_sale_id = p_sale OR r.sale_id = p_sale) AND r.product_id IS NOT NULL
    GROUP BY r.product_id
  ), lines AS (
    SELECT x->>'product_id' AS pid,
           sum(public.jnum(x, 'returned_base', 0)) AS tracked,
           sum(public.item_base_qty(x)) / nullif(sum(public.jnum(x, 'qty', 0)), 0) AS factor
    FROM jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) x GROUP BY 1
  )
  SELECT coalesce(jsonb_object_agg(ret.pid, greatest(ret.qty * coalesce(l.factor, 1) - coalesce(l.tracked, 0), 0)), '{}'::jsonb)
  FROM ret LEFT JOIN lines l ON l.pid = ret.pid
$$;

-- Delete a sale: stock back to the exact batches, returns and payments
-- removed with it, every cash-book effect reversed by the triggers (#9).
CREATE OR REPLACE FUNCTION public.delete_sale_atomic(p_sale_id uuid)
RETURNS TABLE (items jsonb, final_amount numeric, payment_method text, is_credit boolean,
               cash_amount numeric, digital_amount numeric, customer_id uuid, due_amount numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE s public.sales;
BEGIN
  PERFORM public.assert_admin();
  SELECT * INTO s FROM sales WHERE id = p_sale_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sale % not found — already deleted or never existed', p_sale_id USING ERRCODE = 'P0002';
  END IF;

  PERFORM public.sale_restore_all(s.items, public.sale_untracked_returns(s.id, s.items));

  DELETE FROM product_returns pr WHERE pr.original_sale_id = p_sale_id OR pr.sale_id = p_sale_id;
  DELETE FROM sales WHERE id = p_sale_id;     -- payments + reminders cascade

  RETURN QUERY SELECT s.items, s.final_amount, s.payment_method, s.is_credit,
                      s.cash_amount, s.digital_amount, s.customer_id, s.due_amount;
END $$;

-- Edit a sale atomically (#7, #13). Same parameters as before plus the
-- fields the old version silently dropped (round-off, extras, GST, dates).
CREATE OR REPLACE FUNCTION public.edit_sale_atomic(
  p_sale_id uuid, p_items jsonb, p_total_amount numeric, p_discount numeric,
  p_final_amount numeric, p_customer_id uuid, p_is_credit boolean, p_amount_paid numeric,
  p_due_amount numeric, p_payment_method text, p_cash_amount numeric, p_digital_amount numeric,
  p_reason text,
  p_extra_charges numeric DEFAULT NULL, p_round_off numeric DEFAULT NULL,
  p_tax_exempt boolean DEFAULT NULL, p_due_date date DEFAULT NULL)
RETURNS SETOF public.sales
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  s public.sales; v_items jsonb; v_final numeric; v_paid numeric; v_credit boolean;
  v_collected numeric; v_state text; t record; v_method text;
BEGIN
  PERFORM public.assert_admin();
  IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'Edit reason is required'; END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'A sale needs at least one item';
  END IF;

  SELECT * INTO s FROM sales WHERE id = p_sale_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sale not found' USING ERRCODE = 'P0002'; END IF;
  IF EXISTS (SELECT 1 FROM product_returns WHERE original_sale_id = p_sale_id OR sale_id = p_sale_id) THEN
    RAISE EXCEPTION 'This sale has returns. Record another return instead of editing it.';
  END IF;

  PERFORM set_config('app.doc_rpc', 'on', true);

  -- 1. give back everything the old version took, 2. take what the new one needs
  PERFORM public.sale_restore_all(s.items);
  v_items := public.sale_apply_items(p_items);

  v_method := public.norm_payment_method(p_payment_method);
  v_final := greatest(round(coalesce(p_final_amount, 0), 2), 0);
  v_credit := coalesce(p_is_credit, false) OR v_method = 'credit';
  v_paid := CASE WHEN v_credit THEN least(greatest(coalesce(p_amount_paid, 0), 0), v_final) ELSE v_final END;
  SELECT coalesce(sum(amount), 0) INTO v_collected FROM payments WHERE sale_id = p_sale_id;
  IF v_credit AND v_paid < v_collected THEN
    RAISE EXCEPTION 'Amount paid (%) is less than collections already recorded (%)', v_paid, v_collected;
  END IF;
  SELECT state_code INTO v_state FROM customers WHERE id = p_customer_id;
  SELECT * INTO t FROM public.compute_tax(v_items, v_final, v_state, coalesce(p_tax_exempt, s.tax_exempt));

  UPDATE sales SET
    items = v_items,
    total_amount = coalesce(p_total_amount, total_amount),
    discount = coalesce(p_discount, 0),
    total_discount = coalesce((SELECT sum(public.jnum(x, 'discount_amount', 0)) FROM jsonb_array_elements(v_items) x), 0),
    final_amount = v_final,
    customer_id = p_customer_id,
    is_credit = v_credit,
    amount_paid = v_paid,
    due_amount = CASE WHEN v_credit THEN v_final - v_paid ELSE 0 END,
    paid_at_sale = v_paid - CASE WHEN v_credit THEN v_collected ELSE 0 END,
    payment_method = v_method,
    cash_amount = greatest(coalesce(p_cash_amount, 0), 0),
    digital_amount = greatest(coalesce(p_digital_amount, 0), 0),
    extra_charges = coalesce(p_extra_charges, extra_charges),
    round_off = coalesce(p_round_off, round_off),
    tax_exempt = coalesce(p_tax_exempt, tax_exempt),
    due_date = CASE WHEN v_credit THEN coalesce(p_due_date, due_date, public.ist_today() + 30) ELSE NULL END,
    cgst_amount = t.cgst, sgst_amount = t.sgst, igst_amount = t.igst,
    taxable_amount = t.taxable, place_of_supply = t.pos
  WHERE id = p_sale_id;
  -- cash book and both customers' balances follow via triggers

  INSERT INTO transaction_edits (transaction_type, transaction_id, reason, old_data, new_data, edited_by)
  SELECT 'sale', p_sale_id, p_reason, to_jsonb(s), to_jsonb(n), auth.uid() FROM sales n WHERE n.id = p_sale_id;

  PERFORM set_config('app.doc_rpc', 'off', true);
  RETURN QUERY SELECT * FROM sales WHERE id = p_sale_id;
END $$;

-- ---------------------------------------------------------------------
-- 8. Returns (#14) and damaged stock
-- ---------------------------------------------------------------------
-- Refund value is the price the customer actually paid: line discount and
-- the bill-level discount/extras/round-off are spread over the lines.
-- A credit sale's due is reduced first; only the rest is paid out, through
-- the method the customer paid with.
CREATE OR REPLACE FUNCTION public.create_return_atomic(
  p_id uuid, p_product_id uuid, p_sale_id uuid, p_product_name text, p_quantity numeric,
  p_unit_price numeric DEFAULT NULL, p_refund_amount numeric DEFAULT NULL, p_reason text DEFAULT NULL,
  p_created_by uuid DEFAULT NULL, p_refund_method text DEFAULT NULL)
RETURNS TABLE (id uuid, product_id uuid, sale_id uuid, original_sale_id uuid, product_name text,
               quantity numeric, unit_price numeric, return_amount numeric, refund_amount numeric,
               credit_adjusted numeric, refund_method text, cost_amount numeric, tax_amount numeric,
               reason text, created_by uuid, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  s public.sales; v_sold numeric; v_returned numeric; v_lines_product numeric; v_lines_all numeric;
  v_unit_value numeric; v_value numeric; v_tax numeric; v_credit numeric; v_refund numeric;
  v_method text; v_factor numeric; v_base numeric; t record; v_name text;
BEGIN
  PERFORM public.assert_admin();

  -- idempotent: the offline queue may send the same return twice
  IF EXISTS (SELECT 1 FROM product_returns pr WHERE pr.id = p_id) THEN
    RETURN QUERY SELECT pr.id, pr.product_id, pr.sale_id, pr.original_sale_id, pr.product_name, pr.quantity,
      pr.unit_price, pr.return_amount, pr.refund_amount, pr.credit_adjusted, pr.refund_method, pr.cost_amount,
      pr.tax_amount, pr.reason, pr.created_by, pr.created_at FROM product_returns pr WHERE pr.id = p_id;
    RETURN;
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN RAISE EXCEPTION 'Return quantity must be positive'; END IF;
  SELECT * INTO s FROM sales WHERE sales.id = p_sale_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sale % not found', p_sale_id USING ERRCODE = 'P0002'; END IF;

  SELECT coalesce(sum(public.jnum(x, 'qty', 0)), 0),
         coalesce(sum(public.item_line_total(x)), 0),
         sum(public.item_base_qty(x)) / nullif(sum(public.jnum(x, 'qty', 0)), 0),
         max(x->>'name')
    INTO v_sold, v_lines_product, v_factor, v_name
  FROM jsonb_array_elements(s.items) x WHERE x->>'product_id' = p_product_id::text;
  IF v_sold <= 0 THEN RAISE EXCEPTION 'Product % is not in sale %', p_product_id, p_sale_id; END IF;

  SELECT coalesce(sum(pr.quantity), 0) INTO v_returned FROM product_returns pr
  WHERE (pr.original_sale_id = p_sale_id OR pr.sale_id = p_sale_id) AND pr.product_id = p_product_id;
  IF p_quantity > v_sold - v_returned + 0.0005 THEN
    RAISE EXCEPTION 'Cannot return % — sold %, already returned %', p_quantity, v_sold, v_returned;
  END IF;

  SELECT coalesce(sum(public.item_line_total(x)), 0) INTO v_lines_all FROM jsonb_array_elements(s.items) x;
  v_unit_value := (v_lines_product / v_sold)
                  * CASE WHEN v_lines_all > 0 THEN s.final_amount / v_lines_all ELSE 1 END;
  v_value := round(p_quantity * v_unit_value, 2);
  v_tax := CASE WHEN s.final_amount > 0
                THEN round(v_value * (coalesce(s.cgst_amount,0) + coalesce(s.sgst_amount,0) + coalesce(s.igst_amount,0)) / s.final_amount, 2)
                ELSE 0 END;
  v_credit := least(v_value, greatest(coalesce(s.due_amount, 0), 0));
  v_refund := v_value - v_credit;
  v_method := coalesce(public.norm_payment_method(nullif(p_refund_method, '')),
                       CASE WHEN coalesce(s.digital_amount,0) > 0 AND coalesce(s.cash_amount,0) = 0
                                 AND public.account_type_for_method(s.payment_method) = 'bank' THEN 'upi'
                            WHEN public.norm_payment_method(s.payment_method) IN ('upi','bank') THEN s.payment_method
                            ELSE 'cash' END);
  IF v_method IN ('credit','split') THEN v_method := 'cash'; END IF;

  -- stock back into the batches this sale consumed
  v_base := round(p_quantity * coalesce(v_factor, 1), 3);
  PERFORM set_config('app.doc_rpc', 'on', true);
  SELECT * INTO t FROM public.sale_restore_product(s.items, p_product_id, v_base);
  UPDATE sales SET items = t.items, due_amount = greatest(coalesce(sales.due_amount, 0) - v_credit, 0)
  WHERE sales.id = p_sale_id;
  PERFORM set_config('app.doc_rpc', 'off', true);

  INSERT INTO product_returns (id, product_id, sale_id, original_sale_id, product_name, quantity, unit_price,
                               return_amount, refund_amount, credit_adjusted, refund_method, cost_amount,
                               tax_amount, reason, created_by)
  VALUES (p_id, p_product_id, p_sale_id, p_sale_id, coalesce(nullif(p_product_name, ''), v_name, 'Item'),
          p_quantity, round(v_unit_value, 2), v_value, v_refund, v_credit, v_method, round(t.cost, 2),
          v_tax, p_reason, coalesce(auth.uid(), p_created_by));
  -- refund posting: product_returns trigger

  RETURN QUERY SELECT pr.id, pr.product_id, pr.sale_id, pr.original_sale_id, pr.product_name, pr.quantity,
    pr.unit_price, pr.return_amount, pr.refund_amount, pr.credit_adjusted, pr.refund_method, pr.cost_amount,
    pr.tax_amount, pr.reason, pr.created_by, pr.created_at FROM product_returns pr WHERE pr.id = p_id;
END $$;

-- Return every remaining unit of a sale in one call (desktop "Return Full Sale").
CREATE OR REPLACE FUNCTION public.return_full_sale(p_sale_id uuid, p_reason text DEFAULT 'Full sale returned')
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; v_n int := 0;
BEGIN
  PERFORM public.assert_admin();
  FOR r IN
    WITH sold AS (
      SELECT (x->>'product_id')::uuid AS pid, max(x->>'name') AS name, sum(public.jnum(x,'qty',0)) AS qty
      FROM sales s, jsonb_array_elements(s.items) x
      WHERE s.id = p_sale_id AND (x->>'product_id') ~* '^[0-9a-f-]{36}$' GROUP BY 1
    ), ret AS (
      SELECT product_id AS pid, sum(quantity) AS qty FROM product_returns
      WHERE original_sale_id = p_sale_id OR sale_id = p_sale_id GROUP BY 1
    )
    SELECT sold.pid, sold.name, sold.qty - coalesce(ret.qty, 0) AS left_qty
    FROM sold LEFT JOIN ret ON ret.pid = sold.pid
  LOOP
    CONTINUE WHEN r.left_qty <= 0;
    PERFORM public.create_return_atomic(gen_random_uuid(), r.pid, p_sale_id, r.name, r.left_qty,
                                        NULL, NULL, p_reason, auth.uid(), NULL);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;

CREATE OR REPLACE FUNCTION public.create_damaged_atomic(
  p_id uuid, p_product_id uuid, p_product_name text, p_quantity numeric,
  p_unit_price numeric DEFAULT NULL, p_reason text DEFAULT NULL, p_created_by uuid DEFAULT NULL)
RETURNS TABLE (id uuid, product_id uuid, product_name text, quantity numeric, unit_price numeric,
               reason text, created_by uuid, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE v_stock numeric; v_pp numeric; t record;
BEGIN
  PERFORM public.assert_admin();
  IF EXISTS (SELECT 1 FROM damaged_products d WHERE d.id = p_id) THEN
    RETURN QUERY SELECT d.id, d.product_id, d.product_name, d.quantity, d.unit_price, d.reason, d.created_by, d.created_at
      FROM damaged_products d WHERE d.id = p_id;
    RETURN;
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN RAISE EXCEPTION 'Damaged quantity must be positive'; END IF;
  SELECT p.stock, p.purchase_price INTO v_stock, v_pp FROM products p WHERE p.id = p_product_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product % not found', p_product_id; END IF;
  IF v_stock < p_quantity THEN RAISE EXCEPTION 'Insufficient stock: available %, damaged %', v_stock, p_quantity; END IF;

  UPDATE products SET stock = stock - p_quantity WHERE products.id = p_product_id;
  SELECT * INTO t FROM public.fifo_take(p_product_id, p_quantity, v_pp);

  INSERT INTO damaged_products (id, product_id, product_name, quantity, unit_price, reason, created_by)
  VALUES (p_id, p_product_id, p_product_name, p_quantity, round(t.cost / p_quantity, 2), p_reason,
          coalesce(auth.uid(), p_created_by));

  RETURN QUERY SELECT d.id, d.product_id, d.product_name, d.quantity, d.unit_price, d.reason, d.created_by, d.created_at
    FROM damaged_products d WHERE d.id = p_id;
END $$;

-- ---------------------------------------------------------------------
-- 9. Customer payments (credit collection)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payments_before_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_due numeric; v_cust uuid;
BEGIN
  IF public.app_bulk_mode() THEN RETURN NEW; END IF;
  NEW.payment_method := public.norm_payment_method(NEW.payment_method);
  IF NEW.payment_method IN ('credit','split') THEN NEW.payment_method := 'cash'; END IF;
  NEW.created_by := coalesce(auth.uid(), NEW.created_by);
  IF NEW.sale_id IS NOT NULL THEN
    SELECT due_amount, customer_id INTO v_due, v_cust FROM sales WHERE id = NEW.sale_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Sale not found for this payment'; END IF;
    IF NEW.amount > coalesce(v_due, 0) + 0.01 THEN
      RAISE EXCEPTION 'Payment % is more than the amount due (%)', NEW.amount, coalesce(v_due, 0);
    END IF;
    NEW.customer_id := coalesce(NEW.customer_id, v_cust);
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.update_credit_after_payment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.app_bulk_mode() THEN RETURN NULL; END IF;
  IF TG_OP = 'INSERT' AND NEW.sale_id IS NOT NULL THEN
    UPDATE sales SET amount_paid = coalesce(amount_paid,0) + NEW.amount,
                     due_amount = greatest(coalesce(due_amount,0) - NEW.amount, 0)
    WHERE id = NEW.sale_id;
  ELSIF TG_OP = 'DELETE' AND OLD.sale_id IS NOT NULL THEN
    UPDATE sales SET amount_paid = greatest(coalesce(amount_paid,0) - OLD.amount, 0),
                     due_amount = least(coalesce(due_amount,0) + OLD.amount, final_amount)
    WHERE id = OLD.sale_id;
  END IF;
  IF TG_OP = 'INSERT' AND NEW.customer_id IS NOT NULL THEN PERFORM public.refresh_customer_credit(NEW.customer_id); END IF;
  IF TG_OP = 'DELETE' AND OLD.customer_id IS NOT NULL THEN PERFORM public.refresh_customer_credit(OLD.customer_id); END IF;
  RETURN NULL;
END $$;

-- ---------------------------------------------------------------------
-- 10. Purchases (#11, #21): one insert does stock, batches, cost, dues
--     and cash — so the app needs ONE call and offline replays are safe.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purchase_apply_items(p_purchase public.purchases) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_item jsonb; v_gross numeric; v_k numeric; v_prod record; v_factor numeric;
  v_base numeric; v_unit_cost numeric;
BEGIN
  SELECT coalesce(sum(public.jnum(x, 'price', 0) * public.jnum(x, 'qty', 0)), 0)
    INTO v_gross FROM jsonb_array_elements(coalesce(p_purchase.items, '[]'::jsonb)) x;
  -- bill discount / extras / round-off are spread over the lines (landed cost)
  v_k := CASE WHEN v_gross > 0 AND coalesce(p_purchase.total_amount, 0) > 0
              THEN p_purchase.total_amount / v_gross ELSE 1 END;

  FOR v_item IN SELECT * FROM jsonb_array_elements(coalesce(p_purchase.items, '[]'::jsonb)) LOOP
    BEGIN
      SELECT id, unit_type INTO v_prod FROM products WHERE id = (v_item->>'product_id')::uuid FOR UPDATE;
    EXCEPTION WHEN invalid_text_representation THEN v_prod := NULL;
    END;
    CONTINUE WHEN v_prod.id IS NULL;
    v_factor := public.item_stock_factor(v_item, v_prod.unit_type);
    v_base := round(public.jnum(v_item, 'qty', 0) * v_factor, 3);
    CONTINUE WHEN v_base <= 0;
    v_unit_cost := public.jnum(v_item, 'price', 0) * v_k / v_factor;

    UPDATE products SET stock = stock + v_base, purchase_price = round(v_unit_cost, 2), updated_at = now()
    WHERE id = v_prod.id;
    INSERT INTO inventory_batches (product_id, purchase_id, quantity, remaining, purchase_price,
                                   batch_number, expiry_date, created_at)
    VALUES (v_prod.id, p_purchase.id, v_base, v_base, round(v_unit_cost, 4),
            nullif(v_item->>'batch_number', ''),
            CASE WHEN coalesce(v_item->>'expiry_date', '') ~ '^\d{4}-\d{2}-\d{2}' THEN left(v_item->>'expiry_date', 10)::date END,
            coalesce(p_purchase.created_at, now()));
  END LOOP;
END $$;

-- take a purchase's stock back out (edit/delete). Refuses once sold (#11).
CREATE OR REPLACE FUNCTION public.purchase_reverse_items(p_purchase public.purchases) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b record; v_item jsonb; v_sold numeric;
BEGIN
  SELECT coalesce(sum(quantity - remaining), 0) INTO v_sold FROM inventory_batches WHERE purchase_id = p_purchase.id;
  IF v_sold > 0 THEN
    RAISE EXCEPTION 'Cannot change or delete this purchase: % unit(s) of its stock have already been sold or used', v_sold;
  END IF;
  IF EXISTS (SELECT 1 FROM inventory_batches WHERE purchase_id = p_purchase.id) THEN
    FOR b IN SELECT product_id, quantity FROM inventory_batches WHERE purchase_id = p_purchase.id FOR UPDATE LOOP
      UPDATE products SET stock = greatest(stock - b.quantity, 0) WHERE id = b.product_id;
    END LOOP;
    DELETE FROM inventory_batches WHERE purchase_id = p_purchase.id;
  ELSE
    -- old purchases synced from the offline queue never got batches
    FOR v_item IN SELECT * FROM jsonb_array_elements(coalesce(p_purchase.items, '[]'::jsonb)) LOOP
      BEGIN
        UPDATE products SET stock = greatest(stock - public.jnum(v_item, 'qty', 0), 0)
        WHERE id = (v_item->>'product_id')::uuid;
      EXCEPTION WHEN invalid_text_representation THEN NULL;
      END;
    END LOOP;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.purchase_compute_itc(p_purchase public.purchases,
  OUT cgst numeric, OUT sgst numeric, OUT igst numeric, OUT taxable numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_state text; t record;
BEGIN
  SELECT state_code INTO v_state FROM suppliers WHERE id = p_purchase.supplier_id;
  SELECT * INTO t FROM public.compute_tax(p_purchase.items, p_purchase.total_amount, v_state, false);
  cgst := t.cgst; sgst := t.sgst; igst := t.igst; taxable := t.taxable;
END $$;

CREATE OR REPLACE FUNCTION public.purchases_before_write() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t record;
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
  -- money paid at purchase time goes out of cash/bank, never "credit"
  IF NEW.payment_method IN ('credit','split') THEN NEW.payment_method := 'cash'; END IF;
  SELECT * INTO t FROM public.purchase_compute_itc(NEW);
  NEW.cgst_amount := t.cgst; NEW.sgst_amount := t.sgst; NEW.igst_amount := t.igst; NEW.taxable_amount := t.taxable;
  NEW.due_amount := greatest(coalesce(NEW.due_amount, 0), 0);
  NEW.updated_at := now();
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.purchases_after_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.app_bulk_mode() THEN RETURN NULL; END IF;
  PERFORM public.purchase_apply_items(NEW);
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.purchases_before_delete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.app_bulk_mode() THEN RETURN OLD; END IF;
  PERFORM public.purchase_reverse_items(OLD);
  RETURN OLD;
END $$;

CREATE OR REPLACE FUNCTION public.refresh_supplier_dues(p_supplier uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE suppliers SET total_dues = (
    SELECT coalesce(sum(due_amount), 0) FROM purchases WHERE supplier_id = p_supplier AND due_amount > 0)
  WHERE id = p_supplier;
$$;

-- supplier dues now also follow deletes and supplier changes (#11)
CREATE OR REPLACE FUNCTION public.update_supplier_dues() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.app_bulk_mode() THEN RETURN NULL; END IF;
  IF TG_OP IN ('UPDATE','DELETE') AND OLD.supplier_id IS NOT NULL THEN
    PERFORM public.refresh_supplier_dues(OLD.supplier_id);
  END IF;
  IF TG_OP IN ('INSERT','UPDATE') AND NEW.supplier_id IS NOT NULL THEN
    PERFORM public.refresh_supplier_dues(NEW.supplier_id);
  END IF;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.delete_purchase_atomic(p_purchase_id uuid)
RETURNS SETOF public.purchases LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_admin();
  RETURN QUERY DELETE FROM purchases WHERE id = p_purchase_id RETURNING *;
  IF NOT FOUND THEN RAISE EXCEPTION 'Purchase not found' USING ERRCODE = 'P0002'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.edit_purchase_atomic(
  p_purchase_id uuid, p_items jsonb, p_total_amount numeric, p_supplier_id uuid,
  p_supplier_name text, p_is_credit boolean, p_amount_paid numeric, p_due_amount numeric,
  p_payment_method text, p_reason text, p_round_off numeric DEFAULT NULL)
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
    payment_method = p_payment_method, round_off = coalesce(p_round_off, round_off)
  WHERE id = p_purchase_id
  RETURNING * INTO n;

  PERFORM public.purchase_apply_items(n);

  INSERT INTO transaction_edits (transaction_type, transaction_id, reason, old_data, new_data, edited_by)
  VALUES ('purchase', p_purchase_id, p_reason, to_jsonb(p), to_jsonb(n), auth.uid());
  PERFORM set_config('app.doc_rpc', 'off', true);
  RETURN QUERY SELECT * FROM purchases WHERE id = p_purchase_id;
END $$;

-- Receiving a PO now creates a real purchase (#21): stock, batches with
-- cost, supplier dues and the cash/bank outflow all follow from it.
CREATE OR REPLACE FUNCTION public.receive_purchase_order(
  p_order_id uuid, p_is_credit boolean DEFAULT true, p_amount_paid numeric DEFAULT 0,
  p_payment_method text DEFAULT 'cash', p_items jsonb DEFAULT NULL)
RETURNS SETOF public.purchases
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o record; v_items jsonb; v_total numeric; v_id uuid;
BEGIN
  PERFORM public.assert_admin();
  SELECT * INTO o FROM purchase_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Purchase order not found' USING ERRCODE = 'P0002'; END IF;
  IF o.status = 'received' THEN RAISE EXCEPTION 'This order was already received'; END IF;
  IF o.status = 'cancelled' THEN RAISE EXCEPTION 'This order was cancelled'; END IF;

  v_items := coalesce(p_items, o.items);
  SELECT coalesce(jsonb_agg(x || jsonb_build_object(
           'qty', public.jnum(x, 'qty', 0),
           'price', public.jnum(x, 'price', public.jnum(x, 'purchase_price', 0)),
           'total', public.jnum(x, 'qty', 0) * public.jnum(x, 'price', public.jnum(x, 'purchase_price', 0)))), '[]'::jsonb),
         coalesce(sum(public.jnum(x, 'qty', 0) * public.jnum(x, 'price', public.jnum(x, 'purchase_price', 0))), 0)
    INTO v_items, v_total
  FROM jsonb_array_elements(v_items) x
  WHERE public.jnum(x, 'qty', 0) > 0;
  IF jsonb_array_length(v_items) = 0 THEN RAISE EXCEPTION 'Nothing to receive'; END IF;

  INSERT INTO purchases (supplier_id, supplier_name, items, total_amount, is_credit, amount_paid,
                         payment_method, purchase_order_id, created_by)
  VALUES (o.supplier_id, o.supplier_name, v_items, v_total, coalesce(p_is_credit, true),
          coalesce(p_amount_paid, 0), coalesce(p_payment_method, 'cash'), o.id, auth.uid())
  RETURNING id INTO v_id;

  UPDATE purchase_orders SET status = 'received', purchase_id = v_id, updated_at = now(),
    items = (SELECT coalesce(jsonb_agg(x || '{"received": true}'::jsonb), '[]'::jsonb) FROM jsonb_array_elements(o.items) x)
  WHERE id = p_order_id;
  RETURN QUERY SELECT * FROM purchases WHERE id = v_id;
END $$;

-- ---------------------------------------------------------------------
-- 11. Supplier payments
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.supplier_payments_before_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_due numeric; v_sup uuid;
BEGIN
  IF public.app_bulk_mode() THEN RETURN NEW; END IF;
  NEW.payment_method := public.norm_payment_method(NEW.payment_method);
  IF NEW.payment_method IN ('credit','split') THEN NEW.payment_method := 'cash'; END IF;
  NEW.created_by := coalesce(auth.uid(), NEW.created_by);
  IF NEW.purchase_id IS NOT NULL THEN
    SELECT due_amount, supplier_id INTO v_due, v_sup FROM purchases WHERE id = NEW.purchase_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Purchase not found for this payment'; END IF;
    IF NEW.amount > coalesce(v_due, 0) + 0.01 THEN
      RAISE EXCEPTION 'Payment % is more than the amount due (%)', NEW.amount, coalesce(v_due, 0);
    END IF;
    NEW.supplier_id := coalesce(NEW.supplier_id, v_sup);
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.update_supplier_dues_after_payment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.app_bulk_mode() THEN RETURN NULL; END IF;
  IF TG_OP = 'INSERT' AND NEW.purchase_id IS NOT NULL THEN
    UPDATE purchases SET amount_paid = coalesce(amount_paid,0) + NEW.amount,
                         due_amount = greatest(coalesce(due_amount,0) - NEW.amount, 0)
    WHERE id = NEW.purchase_id;
  ELSIF TG_OP = 'DELETE' AND OLD.purchase_id IS NOT NULL THEN
    UPDATE purchases SET amount_paid = greatest(coalesce(amount_paid,0) - OLD.amount, 0),
                         due_amount = least(coalesce(due_amount,0) + OLD.amount, total_amount)
    WHERE id = OLD.purchase_id;
  END IF;
  IF TG_OP = 'INSERT' AND NEW.supplier_id IS NOT NULL THEN PERFORM public.refresh_supplier_dues(NEW.supplier_id); END IF;
  IF TG_OP = 'DELETE' AND OLD.supplier_id IS NOT NULL THEN PERFORM public.refresh_supplier_dues(OLD.supplier_id); END IF;
  RETURN NULL;
END $$;

-- ---------------------------------------------------------------------
-- 12. Expenses, generic timestamps, audit
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expenses_before_write() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.app_bulk_mode() THEN RETURN NEW; END IF;
  NEW.payment_method := public.norm_payment_method(NEW.payment_method);
  IF NEW.payment_method IN ('credit','split') THEN NEW.payment_method := 'cash'; END IF;
  IF coalesce(NEW.amount, 0) <= 0 THEN RAISE EXCEPTION 'Expense amount must be positive'; END IF;
  IF TG_OP = 'INSERT' THEN NEW.created_by := coalesce(auth.uid(), NEW.created_by); END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

CREATE OR REPLACE FUNCTION public.audit_trigger_func() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.app_bulk_mode() THEN RETURN NULL; END IF;
  IF TG_OP = 'INSERT' THEN
    INSERT INTO audit_log (table_name, record_id, action, new_data, performed_by, entity_type, entity_id, user_id)
    VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', to_jsonb(NEW), auth.uid(), TG_TABLE_NAME, NEW.id::text, auth.uid());
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO audit_log (table_name, record_id, action, old_data, new_data, performed_by, entity_type, entity_id, user_id)
    VALUES (TG_TABLE_NAME, NEW.id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW), auth.uid(), TG_TABLE_NAME, NEW.id::text, auth.uid());
  ELSE
    INSERT INTO audit_log (table_name, record_id, action, old_data, performed_by, entity_type, entity_id, user_id)
    VALUES (TG_TABLE_NAME, OLD.id, 'DELETE', to_jsonb(OLD), auth.uid(), TG_TABLE_NAME, OLD.id::text, auth.uid());
  END IF;
  RETURN NULL;
END $$;

-- ---------------------------------------------------------------------
-- 13. Stock utilities used by the app
-- ---------------------------------------------------------------------
-- Physical count: locks the product, sets stock, keeps batches in step.
CREATE OR REPLACE FUNCTION public.reconcile_stock_with_batches(p_product_id uuid, p_physical_qty numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cur numeric; v_pp numeric; v_diff numeric; v_avg numeric;
BEGIN
  PERFORM public.assert_admin();
  IF p_physical_qty IS NULL OR p_physical_qty < 0 THEN RAISE EXCEPTION 'Stock cannot be negative'; END IF;
  SELECT stock, purchase_price INTO v_cur, v_pp FROM products WHERE id = p_product_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product not found: %', p_product_id; END IF;
  v_diff := p_physical_qty - v_cur;
  IF v_diff = 0 THEN RETURN; END IF;
  UPDATE products SET stock = p_physical_qty, updated_at = now() WHERE id = p_product_id;
  IF v_diff > 0 THEN
    -- quantity-weighted cost of what is on hand, else the product's cost
    SELECT sum(remaining * purchase_price) / nullif(sum(remaining), 0) INTO v_avg
    FROM inventory_batches WHERE product_id = p_product_id AND remaining > 0;
    PERFORM public.restore_stock_fifo(p_product_id, v_diff, coalesce(v_avg, v_pp, 0));
  ELSE
    PERFORM public.fifo_take(p_product_id, -v_diff, 0);
  END IF;
END $$;

-- Stock In / Stock Out by a quantity (inventory screen). The app used to
-- read stock and then write stock+qty, losing any sale made in between.
CREATE OR REPLACE FUNCTION public.adjust_stock(p_product_id uuid, p_delta numeric)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cur numeric;
BEGIN
  PERFORM public.assert_admin();
  IF p_delta IS NULL OR p_delta = 0 THEN RAISE EXCEPTION 'Enter a quantity'; END IF;
  SELECT stock INTO v_cur FROM products WHERE id = p_product_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product not found' USING ERRCODE = 'P0002'; END IF;
  IF v_cur + p_delta < 0 THEN
    RAISE EXCEPTION 'Only % in stock — cannot remove %', v_cur, -p_delta;
  END IF;
  PERFORM public.reconcile_stock_with_batches(p_product_id, v_cur + p_delta);
  RETURN v_cur + p_delta;
END $$;

-- internal only (no grants): kept for compatibility with old triggers
CREATE OR REPLACE FUNCTION public.increment_stock(p_product_id uuid, p_qty numeric)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE products SET stock = stock + p_qty WHERE id = p_product_id;
$$;
CREATE OR REPLACE FUNCTION public.decrement_stock(p_product_id uuid, p_qty numeric)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE products SET stock = greatest(stock - p_qty, 0) WHERE id = p_product_id;
$$;

-- Stock only moves through documents (sales, purchases, returns, damaged)
-- and the physical-count RPC above, all SECURITY DEFINER. A plain UPDATE
-- from the app (e.g. a price change sent with a cached product) used to
-- write back a stale stock figure and undo sales made since (#8); such an
-- update keeps every other change but leaves stock alone.
CREATE OR REPLACE FUNCTION public.guard_product_stock() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.stock IS DISTINCT FROM OLD.stock
     AND current_user IN ('authenticated', 'anon')
     AND NOT public.app_bulk_mode() THEN
    NEW.stock := OLD.stock;
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.get_product_batches(p_product_id uuid)
RETURNS TABLE(id uuid, batch_number text, expiry_date date, quantity numeric, remaining numeric,
              purchase_price numeric, created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT b.id, b.batch_number, b.expiry_date, b.quantity, b.remaining, b.purchase_price, b.created_at
  FROM inventory_batches b WHERE b.product_id = p_product_id AND b.remaining > 0
  ORDER BY b.created_at, b.id;
$$;

-- batch-level expiry for dashboard alerts (#24)
CREATE OR REPLACE FUNCTION public.get_expiring_batches(p_days integer DEFAULT 30)
RETURNS TABLE(product_id uuid, product_name text, batch_number text, expiry_date date,
              remaining numeric, days_until_expiry integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.assert_member();
  RETURN QUERY
  SELECT p.id, p.name, ib.batch_number, ib.expiry_date, ib.remaining,
         (ib.expiry_date - public.ist_today())::integer
  FROM inventory_batches ib JOIN products p ON p.id = ib.product_id
  WHERE ib.expiry_date IS NOT NULL AND ib.remaining > 0
    AND ib.expiry_date <= public.ist_today() + p_days
  UNION ALL
  -- products whose expiry was typed on the product itself
  SELECT p.id, p.name, p.batch_number, p.expiry_date, p.stock, (p.expiry_date - public.ist_today())::integer
  FROM products p
  WHERE p.expiry_date IS NOT NULL AND p.stock > 0 AND p.expiry_date <= public.ist_today() + p_days
    AND NOT EXISTS (SELECT 1 FROM inventory_batches b WHERE b.product_id = p.id AND b.expiry_date IS NOT NULL AND b.remaining > 0)
  ORDER BY 4;
END $$;

-- inventory at cost: batches where they exist, product cost for the rest
CREATE OR REPLACE FUNCTION public.get_stock_value() RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((
    SELECT sum(
      coalesce(b.val, 0) + greatest(p.stock - coalesce(b.qty, 0), 0) * coalesce(p.purchase_price, 0))
    FROM products p
    LEFT JOIN (SELECT product_id, sum(remaining) AS qty, sum(remaining * purchase_price) AS val
               FROM inventory_batches WHERE remaining > 0 GROUP BY product_id) b ON b.product_id = p.id
    WHERE NOT coalesce(p.has_variants, false)), 0)
  + coalesce((SELECT sum(pv.stock * pv.purchase_price) FROM product_variants pv
              JOIN products p ON p.id = pv.product_id
              WHERE p.has_variants AND coalesce(pv.is_active, true)), 0)
$$;

-- ---------------------------------------------------------------------
-- 14. Reports — ONE definition each (#16, #17, #18, #15)
--     revenue = invoice value − GST − returns (Ind AS 115 ¶47)
--     COGS    = FIFO cost of lines sold − cost of goods returned
--     days    = Indian Standard Time calendar days
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.item_cost(p_item jsonb) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(public.jnum(p_item, 'cost_total', NULL),
                  public.jnum(p_item, 'purchase_price', 0) * public.jnum(p_item, 'qty', 0))
$$;

-- GST paid to the government is not a business expense
CREATE OR REPLACE FUNCTION public.is_tax_payment_category(p text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT lower(coalesce(p, '')) ~ '^(gst|tax payment|gst payment|tds)'
$$;

CREATE OR REPLACE FUNCTION public.period_figures(p_start timestamptz, p_end timestamptz)
RETURNS TABLE (gross_sales numeric, output_tax numeric, returns_amount numeric, returns_tax numeric,
               net_revenue numeric, cogs numeric, returns_cost numeric, net_cogs numeric,
               expenses numeric, damaged_loss numeric, net_profit numeric, orders bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH s AS (
    SELECT coalesce(sum(final_amount), 0) AS gross,
           coalesce(sum(coalesce(cgst_amount,0) + coalesce(sgst_amount,0) + coalesce(igst_amount,0)), 0) AS tax,
           count(*) AS n
    FROM sales WHERE (p_start IS NULL OR created_at >= p_start) AND (p_end IS NULL OR created_at < p_end)
  ), c AS (
    SELECT coalesce(sum(public.item_cost(x)), 0) AS cost
    FROM sales s2, jsonb_array_elements(s2.items) x
    WHERE (p_start IS NULL OR s2.created_at >= p_start) AND (p_end IS NULL OR s2.created_at < p_end)
  ), r AS (
    SELECT coalesce(sum(coalesce(nullif(return_amount, 0), refund_amount + coalesce(credit_adjusted, 0), 0)), 0) AS amt,
           coalesce(sum(tax_amount), 0) AS tax,
           coalesce(sum(cost_amount), 0) AS cost
    FROM product_returns WHERE (p_start IS NULL OR created_at >= p_start) AND (p_end IS NULL OR created_at < p_end)
  ), e AS (
    SELECT coalesce(sum(amount), 0) AS amt FROM expenses
    WHERE NOT public.is_tax_payment_category(category)
      AND (p_start IS NULL OR created_at >= p_start) AND (p_end IS NULL OR created_at < p_end)
  ), d AS (
    SELECT coalesce(sum(quantity * coalesce(unit_price, 0)), 0) AS amt FROM damaged_products
    WHERE (p_start IS NULL OR created_at >= p_start) AND (p_end IS NULL OR created_at < p_end)
  )
  SELECT s.gross, s.tax, r.amt, r.tax,
         (s.gross - s.tax) - (r.amt - r.tax),
         c.cost, r.cost, c.cost - r.cost,
         e.amt, d.amt,
         ((s.gross - s.tax) - (r.amt - r.tax)) - (c.cost - r.cost) - e.amt - d.amt,
         s.n
  FROM s, c, r, e, d
$$;

-- Dashboard: one call, IST days, profit hidden from staff (#18, #28)
CREATE OR REPLACE FUNCTION public.get_dashboard_summary() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_today date := public.ist_today();
  v_t0 timestamptz := public.ist_day_start(v_today);
  v_t1 timestamptz := public.ist_day_start(v_today + 1);
  v_y0 timestamptz := public.ist_day_start(v_today - 1);
  v_m0 timestamptz := public.ist_month_start(v_today);
  v_admin boolean := auth.uid() IS NULL OR public.is_admin();
  m record; v jsonb;
BEGIN
  PERFORM public.assert_member();
  SELECT * INTO m FROM public.period_figures(v_m0, v_t1);
  v := jsonb_build_object(
    'is_admin', v_admin,
    'today_sales',      (SELECT coalesce(sum(final_amount),0) FROM sales WHERE created_at >= v_t0 AND created_at < v_t1),
    'yesterday_sales',  (SELECT coalesce(sum(final_amount),0) FROM sales WHERE created_at >= v_y0 AND created_at < v_t0),
    'today_order_count',     (SELECT count(*) FROM sales WHERE created_at >= v_t0 AND created_at < v_t1),
    'yesterday_order_count', (SELECT count(*) FROM sales WHERE created_at >= v_y0 AND created_at < v_t0),
    'today_expenses',   (SELECT coalesce(sum(amount),0) FROM expenses WHERE created_at >= v_t0 AND created_at < v_t1
                           AND NOT public.is_tax_payment_category(category)),
    'today_returns',    (SELECT coalesce(sum(return_amount),0) FROM product_returns WHERE created_at >= v_t0 AND created_at < v_t1),
    'monthly_gross_sales', m.gross_sales,
    'monthly_sales',    m.net_revenue,            -- net of GST and returns
    'monthly_returns',  m.returns_amount,
    'monthly_expenses', m.expenses,
    'total_products',   (SELECT count(*) FROM products),
    'total_customers',  (SELECT count(*) FROM customers),
    'low_stock_count',  (SELECT count(*) FROM products WHERE NOT coalesce(has_variants,false)
                           AND stock > 0 AND stock <= low_stock_alert AND low_stock_alert > 0),
    'out_of_stock_count', (SELECT count(*) FROM products WHERE NOT coalesce(has_variants,false) AND stock <= 0),
    'top_products', (SELECT coalesce(jsonb_agg(t), '[]'::jsonb) FROM (
        SELECT x->>'name' AS name, sum(public.item_line_total(x)) AS total, sum(public.jnum(x,'qty',0)) AS qty
        FROM sales s, jsonb_array_elements(s.items) x
        WHERE s.created_at >= v_m0 GROUP BY x->>'name' ORDER BY 2 DESC LIMIT 5) t),
    'recent_sales', (SELECT coalesce(jsonb_agg(r), '[]'::jsonb) FROM (
        SELECT id, invoice_no, final_amount, payment_method, created_at FROM sales
        WHERE created_at >= v_t0 AND created_at < v_t1 ORDER BY created_at DESC LIMIT 10) r),
    'weekly_sales', (SELECT coalesce(jsonb_agg(w ORDER BY w.d), '[]'::jsonb) FROM (
        SELECT d.d, to_char(d.d, 'Dy') AS day, d.d::text AS date,
               coalesce((SELECT sum(final_amount) FROM sales
                         WHERE created_at >= public.ist_day_start(d.d) AND created_at < public.ist_day_start(d.d + 1)), 0) AS total
        FROM generate_series(v_today - 6, v_today, interval '1 day') AS g(day), LATERAL (SELECT g.day::date AS d) d) w)
  );
  IF v_admin THEN
    v := v || jsonb_build_object(
      'monthly_cogs', m.net_cogs,
      'monthly_profit', m.net_profit,
      'monthly_damaged', m.damaged_loss,
      'stock_value', public.get_stock_value());
  ELSE
    v := v || jsonb_build_object('monthly_cogs', NULL, 'monthly_profit', NULL, 'stock_value', NULL);
  END IF;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.get_monthly_profit(p_start timestamptz, p_end timestamptz)
RETURNS TABLE (sales_total numeric, purchase_cost numeric, expenses_total numeric, profit numeric,
               gross_sales numeric, tax_total numeric, returns_total numeric, damaged_total numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.assert_admin();
  RETURN QUERY SELECT f.net_revenue, f.net_cogs, f.expenses, f.net_profit,
                      f.gross_sales, f.output_tax, f.returns_amount, f.damaged_loss
               FROM public.period_figures(p_start, p_end) f;
END $$;

CREATE OR REPLACE FUNCTION public.get_profit_loss(p_start_date date, p_end_date date)
RETURNS TABLE (sales_total numeric, purchase_cost numeric, gross_profit numeric,
               expenses_total numeric, net_profit numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.assert_admin();
  RETURN QUERY SELECT f.net_revenue, f.net_cogs, f.net_revenue - f.net_cogs,
                      f.expenses + f.damaged_loss, f.net_profit
  FROM public.period_figures(public.ist_day_start(p_start_date), public.ist_day_start(p_end_date + 1)) f;
END $$;

CREATE OR REPLACE FUNCTION public.get_sales_total(p_start timestamptz, p_end timestamptz) RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_admin();
  RETURN (SELECT coalesce(sum(final_amount), 0) FROM sales WHERE created_at >= p_start AND created_at < p_end);
END $$;

CREATE OR REPLACE FUNCTION public.get_expenses_total(p_start timestamptz, p_end timestamptz) RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_admin();
  RETURN (SELECT coalesce(sum(amount), 0) FROM expenses
          WHERE created_at >= p_start AND created_at < p_end AND NOT public.is_tax_payment_category(category));
END $$;

-- 12 IST months; month_start lets the app filter by date range (#18)
CREATE OR REPLACE FUNCTION public.get_monthly_sales_summary()
RETURNS TABLE (month text, month_start date, total_sales numeric, total_purchases numeric,
               total_cogs numeric, total_expenses numeric, profit numeric, gross_sales numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.assert_admin();
  RETURN QUERY
  SELECT to_char(m.d, 'Mon YYYY'), m.d,
         f.net_revenue,
         (SELECT coalesce(sum(p.total_amount), 0) FROM purchases p
          WHERE p.created_at >= public.ist_day_start(m.d)
            AND p.created_at < public.ist_day_start((m.d + interval '1 month')::date)),
         f.net_cogs, f.expenses, f.net_profit, f.gross_sales
  FROM (SELECT (date_trunc('month', public.ist_today()) - make_interval(months => k))::date AS d
        FROM generate_series(0, 11) k) m
  CROSS JOIN LATERAL public.period_figures(public.ist_day_start(m.d),
                                           public.ist_day_start((m.d + interval '1 month')::date)) f
  ORDER BY m.d;
END $$;

CREATE OR REPLACE FUNCTION public.get_category_sales(p_start timestamptz DEFAULT NULL, p_end timestamptz DEFAULT NULL)
RETURNS TABLE (category text, total_qty numeric, total_revenue numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.assert_admin();
  RETURN QUERY
  SELECT coalesce(nullif(btrim(p.category), ''), 'Uncategorized')::text,
         sum(public.jnum(x, 'qty', 0)),
         sum(public.item_line_total(x))
  FROM sales s
  CROSS JOIN LATERAL jsonb_array_elements(s.items) x
  LEFT JOIN products p ON p.id::text = x->>'product_id'
  WHERE (p_start IS NULL OR s.created_at >= p_start) AND (p_end IS NULL OR s.created_at < p_end)
  GROUP BY 1 ORDER BY 3 DESC;
END $$;

CREATE OR REPLACE FUNCTION public.get_daily_sales_trend(p_start timestamptz DEFAULT NULL, p_end timestamptz DEFAULT NULL)
RETURNS TABLE (day date, total_sales numeric, order_count bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  v_from date := coalesce(public.ist_date(p_start), public.ist_today() - 30);
  v_to date := coalesce(public.ist_date(p_end - interval '1 microsecond'), public.ist_today());
BEGIN
  PERFORM public.assert_admin();
  RETURN QUERY
  SELECT g.day::date,
         coalesce(sum(s.final_amount), 0),
         count(s.id)
  FROM generate_series(v_from, v_to, interval '1 day') g(day)
  LEFT JOIN sales s ON s.created_at >= public.ist_day_start(g.day::date)
                   AND s.created_at < public.ist_day_start(g.day::date + 1)
  GROUP BY g.day ORDER BY g.day;
END $$;

-- Reports screen. Previous period = same length right before (#18).
CREATE OR REPLACE FUNCTION public.get_reports_summary(p_start timestamptz, p_end timestamptz)
RETURNS TABLE (total_sales numeric, total_purchases numeric, total_expenses numeric, net_profit numeric,
               sales_by_day jsonb, top_products jsonb, sales_by_category jsonb, expenses_by_category jsonb,
               payment_breakdown jsonb, prev_month_sales numeric, prev_month_expenses numeric,
               prev_month_profit numeric, gross_sales numeric, tax_total numeric, returns_total numeric,
               damaged_total numeric, order_count bigint, purchase_invoices numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  f record; pf record;
  v_prev_start timestamptz := p_start - (p_end - p_start);
BEGIN
  PERFORM public.assert_admin();
  SELECT * INTO f FROM public.period_figures(p_start, p_end);
  SELECT * INTO pf FROM public.period_figures(v_prev_start, p_start);
  RETURN QUERY SELECT
    f.net_revenue, f.net_cogs, f.expenses, f.net_profit,
    (SELECT coalesce(jsonb_agg(jsonb_build_object('date', to_char(d, 'DD Mon'), 'total', t) ORDER BY d), '[]'::jsonb)
       FROM (SELECT public.ist_date(created_at) AS d, sum(final_amount) AS t FROM sales
             WHERE created_at >= p_start AND created_at < p_end GROUP BY 1) x),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('name', n, 'total', t, 'qty', q) ORDER BY t DESC), '[]'::jsonb)
       FROM (SELECT x->>'name' AS n, sum(public.item_line_total(x)) AS t, sum(public.jnum(x,'qty',0)) AS q
             FROM sales s, jsonb_array_elements(s.items) x
             WHERE s.created_at >= p_start AND s.created_at < p_end
             GROUP BY 1 ORDER BY 2 DESC LIMIT 5) y),
    (SELECT coalesce(jsonb_object_agg(c, t), '{}'::jsonb)
       FROM (SELECT coalesce(nullif(btrim(p.category), ''), 'Other') AS c, sum(public.item_line_total(x)) AS t
             FROM sales s CROSS JOIN LATERAL jsonb_array_elements(s.items) x
             LEFT JOIN products p ON p.id::text = x->>'product_id'
             WHERE s.created_at >= p_start AND s.created_at < p_end GROUP BY 1) z),
    (SELECT coalesce(jsonb_object_agg(c, t), '{}'::jsonb)
       FROM (SELECT coalesce(nullif(btrim(category), ''), 'Other') AS c, sum(amount) AS t FROM expenses
             WHERE created_at >= p_start AND created_at < p_end GROUP BY 1) e),
    (SELECT coalesce(jsonb_object_agg(m, t), '{}'::jsonb)
       FROM (SELECT CASE WHEN is_credit THEN 'credit' ELSE public.norm_payment_method(payment_method) END AS m,
                    sum(final_amount) AS t FROM sales
             WHERE created_at >= p_start AND created_at < p_end GROUP BY 1) pm),
    pf.net_revenue, pf.expenses, pf.net_profit,
    f.gross_sales, f.output_tax, f.returns_amount, f.damaged_loss, f.orders,
    (SELECT coalesce(sum(total_amount), 0) FROM purchases WHERE created_at >= p_start AND created_at < p_end);
END $$;

-- Balance sheet from the cash book + inventory + receivables/payables (#16)
CREATE OR REPLACE FUNCTION public.get_balance_sheet()
RETURNS TABLE (cash_in_hand numeric, bank_balance numeric, inventory_value numeric, total_receivables numeric,
               total_assets numeric, total_payables numeric, credit_purchase_dues numeric, gst_payable numeric,
               total_liabilities numeric, owner_capital numeric, retained_earnings numeric, total_equity numeric,
               difference numeric, balance_check boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  v_cash numeric; v_bank numeric; v_inv numeric; v_ar numeric; v_ap numeric; v_gst numeric;
  v_capital numeric; v_re numeric; v_assets numeric; v_liab numeric; v_unbatched numeric;
BEGIN
  PERFORM public.assert_admin();
  SELECT coalesce(sum(balance) FILTER (WHERE account_type = 'cash'), 0),
         coalesce(sum(balance) FILTER (WHERE account_type <> 'cash'), 0)
    INTO v_cash, v_bank FROM accounts;
  v_inv := public.get_stock_value();
  SELECT coalesce(sum(due_amount), 0) INTO v_ar FROM sales WHERE due_amount > 0;
  SELECT coalesce(sum(due_amount), 0) INTO v_ap FROM purchases WHERE due_amount > 0;
  -- GST collected − input credit − tax on returns − GST already paid
  SELECT coalesce(sum(coalesce(cgst_amount,0)+coalesce(sgst_amount,0)+coalesce(igst_amount,0)), 0)
       - coalesce((SELECT sum(coalesce(cgst_amount,0)+coalesce(sgst_amount,0)+coalesce(igst_amount,0)) FROM purchases), 0)
       - coalesce((SELECT sum(tax_amount) FROM product_returns), 0)
       - coalesce((SELECT sum(amount) FROM expenses WHERE public.is_tax_payment_category(category)), 0)
    INTO v_gst FROM sales;
  SELECT f.net_profit INTO v_re FROM public.period_figures(NULL, NULL) f;

  -- recorded capital: opening balances of the money accounts, manual
  -- capital/drawing/other entries, and opening stock with no purchase record
  SELECT coalesce(sum(a.balance - coalesce(j.net, 0)), 0) INTO v_capital
  FROM accounts a
  LEFT JOIN (SELECT account_id, sum(CASE WHEN type='in' THEN amount ELSE -amount END) AS net
             FROM account_transactions GROUP BY account_id) j ON j.account_id = a.id;
  v_capital := v_capital + coalesce((
    SELECT sum(CASE WHEN type='in' THEN amount ELSE -amount END) FROM account_transactions
    WHERE ref_type IS NULL AND coalesce(source,'manual') = 'manual' AND category <> 'transfer'), 0);
  SELECT coalesce(sum(greatest(p.stock - coalesce(b.qty, 0), 0) * coalesce(p.purchase_price, 0)), 0) INTO v_unbatched
  FROM products p LEFT JOIN (SELECT product_id, sum(remaining) AS qty FROM inventory_batches GROUP BY product_id) b
    ON b.product_id = p.id
  WHERE NOT coalesce(p.has_variants, false);
  v_capital := v_capital + v_unbatched;

  v_assets := v_cash + v_bank + v_inv + v_ar;
  v_liab := v_ap + greatest(v_gst, 0);
  RETURN QUERY SELECT v_cash, v_bank, v_inv, v_ar, v_assets, v_ap, v_ap, greatest(v_gst, 0), v_liab,
                      v_capital, v_re, v_capital + v_re,
                      round(v_assets - v_liab - v_capital - v_re, 2),
                      abs(v_assets - v_liab - v_capital - v_re) < 1;
END $$;

-- Cash flow straight from the cash book (#16): real dates, real opening.
CREATE OR REPLACE FUNCTION public.get_cash_flow(p_start timestamptz, p_end timestamptz)
RETURNS TABLE (cash_sales numeric, digital_sales numeric, total_sales_inflow numeric,
               purchase_payments numeric, expense_payments numeric, total_outflow numeric,
               net_cash_flow numeric, opening_balance numeric, closing_balance numeric,
               cash_received_customers numeric, cash_paid_suppliers numeric, refunds_paid numeric,
               other_in numeric, other_out numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE v_now_balance numeric; v_after numeric; v_net numeric; r record;
BEGIN
  PERFORM public.assert_admin();
  SELECT
    coalesce(sum(s) FILTER (WHERE grp = 'sale' AND acct = 'cash'), 0)  AS cs,
    coalesce(sum(s) FILTER (WHERE grp = 'sale' AND acct <> 'cash'), 0) AS ds,
    coalesce(sum(s) FILTER (WHERE grp = 'credit_collection'), 0)       AS coll,
    coalesce(-sum(s) FILTER (WHERE grp = 'purchase'), 0)               AS pur,
    coalesce(-sum(s) FILTER (WHERE grp = 'credit_payment'), 0)         AS supp,
    coalesce(-sum(s) FILTER (WHERE grp = 'expense'), 0)                AS exp,
    coalesce(-sum(s) FILTER (WHERE grp = 'return_refund'), 0)          AS ref,
    coalesce(sum(s) FILTER (WHERE grp = 'other' AND s > 0), 0)         AS oin,
    coalesce(-sum(s) FILTER (WHERE grp = 'other' AND s < 0), 0)        AS oout,
    coalesce(sum(s), 0) AS net
  INTO r
  FROM (
    SELECT CASE WHEN t.type = 'in' THEN t.amount ELSE -t.amount END AS s,
           a.account_type AS acct,
           CASE
             WHEN t.category LIKE 'sale%' THEN 'sale'
             WHEN t.category LIKE 'credit_collection%' THEN 'credit_collection'
             WHEN t.category LIKE 'purchase%' THEN 'purchase'
             WHEN t.category LIKE 'credit_payment%' THEN 'credit_payment'
             WHEN t.category LIKE 'expense%' THEN 'expense'
             WHEN t.category LIKE 'return_re%' THEN 'return_refund'
             ELSE 'other' END AS grp
    FROM account_transactions t JOIN accounts a ON a.id = t.account_id
    WHERE t.category <> 'transfer' AND t.created_at >= p_start AND t.created_at < p_end
  ) x;

  SELECT coalesce(sum(balance), 0) INTO v_now_balance FROM accounts;
  SELECT coalesce(sum(CASE WHEN type='in' THEN amount ELSE -amount END), 0) INTO v_after
  FROM account_transactions WHERE created_at >= p_start;
  v_net := r.net;

  RETURN QUERY SELECT r.cs, r.ds, r.cs + r.ds + r.coll,
                      r.pur + r.supp, r.exp, r.pur + r.supp + r.exp + r.ref + r.oout,
                      v_net, v_now_balance - v_after, v_now_balance - v_after + v_net,
                      r.coll, r.supp, r.ref, r.oin, r.oout;
END $$;

-- Overdue aging by DUE date (sale date + 30 when no due date) (#16)
CREATE OR REPLACE FUNCTION public.get_receivables_aging()
RETURNS TABLE (customer_id uuid, customer_name text, phone text, total_due numeric, current_amount numeric,
               days_1_30 numeric, days_31_60 numeric, days_61_90 numeric, days_90_plus numeric,
               oldest_sale_date timestamptz, sale_count bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.assert_admin();
  RETURN QUERY
  WITH d AS (
    SELECT s.customer_id AS cid, s.due_amount AS due, s.created_at,
           public.ist_today() - coalesce(s.due_date, public.ist_date(s.created_at) + 30) AS overdue
    FROM sales s WHERE s.due_amount > 0
  )
  SELECT d.cid, coalesce(c.name, 'Walk-in / unknown')::text, coalesce(c.phone, '')::text,
         sum(d.due),
         coalesce(sum(d.due) FILTER (WHERE d.overdue <= 0), 0),
         coalesce(sum(d.due) FILTER (WHERE d.overdue BETWEEN 1 AND 30), 0),
         coalesce(sum(d.due) FILTER (WHERE d.overdue BETWEEN 31 AND 60), 0),
         coalesce(sum(d.due) FILTER (WHERE d.overdue BETWEEN 61 AND 90), 0),
         coalesce(sum(d.due) FILTER (WHERE d.overdue > 90), 0),
         min(d.created_at), count(*)
  FROM d LEFT JOIN customers c ON c.id = d.cid
  GROUP BY d.cid, c.name, c.phone
  ORDER BY 4 DESC;
END $$;

-- GSTR-3B (#16): taxable value excludes tax; ITC from purchases; returns
-- reduce outward supplies; argument names match the app (p_start, p_end).
CREATE OR REPLACE FUNCTION public.get_gstr3b_summary(p_start timestamptz, p_end timestamptz)
RETURNS TABLE (outward_taxable numeric, outward_igst numeric, outward_cgst numeric, outward_sgst numeric,
               inward_taxable numeric, inward_igst numeric, inward_cgst numeric, inward_sgst numeric,
               total_igst numeric, total_cgst numeric, total_sgst numeric, total_tax_payable numeric,
               itc_carry_forward numeric, returns_taxable numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE o record; i record; r record; v_out numeric; v_in numeric;
BEGIN
  PERFORM public.assert_admin();
  SELECT coalesce(sum(coalesce(taxable_amount, final_amount - coalesce(cgst_amount,0) - coalesce(sgst_amount,0) - coalesce(igst_amount,0))), 0) AS tx,
         coalesce(sum(igst_amount), 0) AS ig, coalesce(sum(cgst_amount), 0) AS cg, coalesce(sum(sgst_amount), 0) AS sg
    INTO o FROM sales WHERE created_at >= p_start AND created_at < p_end;
  -- returns: split their tax by the original sale's heads
  SELECT coalesce(sum(pr.return_amount - pr.tax_amount), 0) AS tx,
         coalesce(sum(pr.tax_amount * coalesce(s.igst_amount,0) / nullif(coalesce(s.cgst_amount,0)+coalesce(s.sgst_amount,0)+coalesce(s.igst_amount,0), 0)), 0) AS ig,
         coalesce(sum(pr.tax_amount * coalesce(s.cgst_amount,0) / nullif(coalesce(s.cgst_amount,0)+coalesce(s.sgst_amount,0)+coalesce(s.igst_amount,0), 0)), 0) AS cg,
         coalesce(sum(pr.tax_amount * coalesce(s.sgst_amount,0) / nullif(coalesce(s.cgst_amount,0)+coalesce(s.sgst_amount,0)+coalesce(s.igst_amount,0), 0)), 0) AS sg
    INTO r FROM product_returns pr LEFT JOIN sales s ON s.id = coalesce(pr.original_sale_id, pr.sale_id)
   WHERE pr.created_at >= p_start AND pr.created_at < p_end;
  SELECT coalesce(sum(coalesce(taxable_amount, total_amount)), 0) AS tx,
         coalesce(sum(igst_amount), 0) AS ig, coalesce(sum(cgst_amount), 0) AS cg, coalesce(sum(sgst_amount), 0) AS sg
    INTO i FROM purchases WHERE created_at >= p_start AND created_at < p_end;

  v_out := (o.ig - r.ig) + (o.cg - r.cg) + (o.sg - r.sg);
  v_in := i.ig + i.cg + i.sg;
  RETURN QUERY SELECT
    round(o.tx - r.tx, 2), round(o.ig - r.ig, 2), round(o.cg - r.cg, 2), round(o.sg - r.sg, 2),
    round(i.tx, 2), round(i.ig, 2), round(i.cg, 2), round(i.sg, 2),
    round(greatest((o.ig - r.ig) - i.ig, 0), 2), round(greatest((o.cg - r.cg) - i.cg, 0), 2),
    round(greatest((o.sg - r.sg) - i.sg, 0), 2),
    round(greatest(v_out - v_in, 0), 2), round(greatest(v_in - v_out, 0), 2), round(r.tx, 2);
END $$;

CREATE OR REPLACE FUNCTION public.get_trial_balance()
RETURNS TABLE (account_name text, account_type text, debit numeric, credit numeric, balance numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE b record;
BEGIN
  PERFORM public.assert_admin();
  SELECT * INTO b FROM public.get_balance_sheet();
  RETURN QUERY
  SELECT a.name::text, a.account_type::text, greatest(a.balance, 0)::numeric, greatest(-a.balance, 0)::numeric, a.balance::numeric
  FROM accounts a
  UNION ALL SELECT 'Inventory', 'asset', b.inventory_value, 0::numeric, b.inventory_value
  UNION ALL SELECT 'Customer receivables', 'asset', b.total_receivables, 0::numeric, b.total_receivables
  UNION ALL SELECT 'Supplier payables', 'liability', 0::numeric, b.total_payables, -b.total_payables
  UNION ALL SELECT 'GST payable', 'liability', 0::numeric, b.gst_payable, -b.gst_payable
  UNION ALL SELECT 'Owner capital & opening balances', 'equity', 0::numeric, b.owner_capital, -b.owner_capital
  UNION ALL SELECT 'Retained earnings', 'equity', greatest(-b.retained_earnings, 0), greatest(b.retained_earnings, 0), -b.retained_earnings
  UNION ALL SELECT 'Unreconciled difference', 'equity', greatest(-b.difference, 0), greatest(b.difference, 0), -b.difference;
END $$;

CREATE OR REPLACE FUNCTION public.get_financial_summary()
RETURNS TABLE (cash_position numeric, bank_position numeric, total_cash_bank numeric, total_receivables numeric,
               total_payables numeric, net_position numeric, monthly_sales numeric, monthly_purchases numeric,
               monthly_expenses numeric, monthly_profit numeric, gross_margin_pct numeric,
               expense_ratio_pct numeric, cash_runway_days numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE v_cash numeric; v_bank numeric; v_ar numeric; v_ap numeric; f record; v_days numeric;
BEGIN
  PERFORM public.assert_admin();
  SELECT coalesce(sum(balance) FILTER (WHERE account_type = 'cash'), 0),
         coalesce(sum(balance) FILTER (WHERE account_type <> 'cash'), 0) INTO v_cash, v_bank FROM accounts;
  SELECT coalesce(sum(due_amount), 0) INTO v_ar FROM sales WHERE due_amount > 0;
  SELECT coalesce(sum(due_amount), 0) INTO v_ap FROM purchases WHERE due_amount > 0;
  SELECT * INTO f FROM public.period_figures(public.ist_month_start(public.ist_today()), now());
  v_days := greatest(public.ist_today() - public.ist_month_start(public.ist_today())::date + 1, 1);
  RETURN QUERY SELECT v_cash, v_bank, v_cash + v_bank, v_ar, v_ap, v_cash + v_bank + v_ar - v_ap,
    f.net_revenue, f.net_cogs, f.expenses, f.net_profit,
    CASE WHEN f.net_revenue > 0 THEN round((f.net_revenue - f.net_cogs) / f.net_revenue * 100, 1) ELSE 0 END,
    CASE WHEN f.net_revenue > 0 THEN round(f.expenses / f.net_revenue * 100, 1) ELSE 0 END,
    CASE WHEN f.expenses > 0 THEN round((v_cash + v_bank) / (f.expenses / v_days), 0) ELSE 999 END;
END $$;

CREATE OR REPLACE FUNCTION public.get_sales_forecast()
RETURNS TABLE (current_month_sales numeric, days_elapsed int, days_in_month int, projected_monthly_sales numeric,
               last_month_sales numeric, month_over_month_pct numeric, daily_average numeric,
               trend_direction text, forecast_confidence text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  v_today date := public.ist_today();
  v_m0 date := date_trunc('month', v_today)::date;
  v_prev date := (v_m0 - interval '1 month')::date;
  v_cur numeric; v_last numeric; v_el int; v_dim int; v_avg numeric; v_last_avg numeric;
BEGIN
  PERFORM public.assert_admin();
  SELECT coalesce(sum(final_amount), 0) INTO v_cur FROM sales WHERE created_at >= public.ist_day_start(v_m0);
  SELECT coalesce(sum(final_amount), 0) INTO v_last FROM sales
   WHERE created_at >= public.ist_day_start(v_prev) AND created_at < public.ist_day_start(v_m0);
  v_el := v_today - v_m0 + 1;
  v_dim := ((v_m0 + interval '1 month')::date - v_m0);
  v_avg := v_cur / v_el;
  v_last_avg := v_last / greatest(v_m0 - v_prev, 1);
  RETURN QUERY SELECT v_cur, v_el, v_dim, round(v_avg * v_dim, 2), v_last,
    CASE WHEN v_last > 0 THEN round((v_avg * v_dim - v_last) / v_last * 100, 1) ELSE 0 END,
    round(v_avg, 2),
    CASE WHEN v_avg > v_last_avg * 1.1 THEN 'growing' WHEN v_avg < v_last_avg * 0.9 THEN 'declining' ELSE 'stable' END,
    CASE WHEN v_el >= 15 THEN 'high' WHEN v_el >= 7 THEN 'medium' ELSE 'low' END;
END $$;

CREATE OR REPLACE FUNCTION public.get_customer_insights()
RETURNS TABLE (customer_id uuid, customer_name text, total_purchases numeric, total_orders bigint,
               avg_order_value numeric, last_purchase_date timestamptz, days_since_last_purchase bigint,
               lifetime_value numeric, churn_risk text, segment text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.assert_admin();
  RETURN QUERY
  WITH cs AS (
    SELECT c.id AS cid, c.name AS cname, coalesce(sum(s.final_amount), 0) AS tot, count(s.id) AS n,
           max(s.created_at) AS last_at
    FROM customers c LEFT JOIN sales s ON s.customer_id = c.id GROUP BY c.id, c.name)
  SELECT cs.cid, cs.cname, cs.tot, cs.n,
         CASE WHEN cs.n > 0 THEN round(cs.tot / cs.n, 2) ELSE 0 END,
         cs.last_at, (public.ist_today() - public.ist_date(cs.last_at))::bigint, cs.tot,
         CASE WHEN cs.last_at IS NULL THEN 'no_activity'
              WHEN cs.last_at < now() - interval '90 days' THEN 'high'
              WHEN cs.last_at < now() - interval '30 days' THEN 'medium' ELSE 'low' END,
         CASE WHEN cs.tot >= 50000 THEN 'platinum' WHEN cs.tot >= 20000 THEN 'gold'
              WHEN cs.tot >= 5000 THEN 'silver' WHEN cs.tot > 0 THEN 'bronze' ELSE 'prospect' END
  FROM cs ORDER BY cs.tot DESC;
END $$;

-- ABC uses cumulative revenue share (A = top 80%, B = next 15%)
CREATE OR REPLACE FUNCTION public.get_product_insights()
RETURNS TABLE (product_id uuid, product_name text, category text, current_stock numeric, purchase_price numeric,
               selling_price numeric, total_sold numeric, total_revenue numeric, total_profit numeric,
               profit_margin numeric, velocity_per_day numeric, days_of_stock numeric, abc_class text, stock_status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.assert_admin();
  RETURN QUERY
  WITH ps AS (
    SELECT x->>'product_id' AS pid, sum(public.jnum(x,'qty',0)) AS sold,
           sum(public.item_line_total(x)) AS rev, sum(public.item_line_total(x) - public.item_cost(x)) AS prof
    FROM sales s, jsonb_array_elements(s.items) x
    WHERE s.created_at >= now() - interval '90 days' GROUP BY 1
  ), ranked AS (
    SELECT pr.*, ps.sold, ps.rev, ps.prof,
           sum(coalesce(ps.rev,0)) OVER (ORDER BY coalesce(ps.rev,0) DESC, pr.id) AS cum,
           sum(coalesce(ps.rev,0)) OVER () AS grand
    FROM products pr LEFT JOIN ps ON ps.pid = pr.id::text
  )
  SELECT r.id, r.name, coalesce(r.category, 'Uncategorized'), r.stock, r.purchase_price, r.selling_price,
         coalesce(r.sold, 0), coalesce(r.rev, 0), coalesce(r.prof, 0),
         CASE WHEN coalesce(r.rev,0) > 0 THEN round(r.prof / r.rev * 100, 1) ELSE 0 END,
         round(coalesce(r.sold, 0) / 90.0, 2),
         CASE WHEN coalesce(r.sold, 0) > 0 THEN round(r.stock / (r.sold / 90.0), 0) ELSE 999 END,
         CASE WHEN r.grand > 0 AND coalesce(r.rev,0) > 0 AND r.cum - r.rev < r.grand * 0.80 THEN 'A'
              WHEN r.grand > 0 AND coalesce(r.rev,0) > 0 AND r.cum - r.rev < r.grand * 0.95 THEN 'B' ELSE 'C' END,
         CASE WHEN r.stock <= 0 THEN 'out_of_stock' WHEN r.stock <= r.low_stock_alert THEN 'low' ELSE 'healthy' END
  FROM ranked r ORDER BY coalesce(r.rev, 0) DESC;
END $$;

-- Rewritten: no temp table, scalar counts, aggregates ordered inside (#16)
CREATE OR REPLACE FUNCTION public.get_inventory_health()
RETURNS TABLE (total_products bigint, total_stock_value numeric, healthy_count bigint, low_stock_count bigint,
               out_of_stock_count bigint, slow_moving_count bigint, dead_stock_count bigint, overstock_count bigint,
               slow_moving_items jsonb, out_of_stock_items jsonb, top_reorder_items jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.assert_admin();
  RETURN QUERY
  WITH sold AS (
    SELECT x->>'product_id' AS pid,
           sum(public.jnum(x,'qty',0)) FILTER (WHERE s.created_at >= now() - interval '90 days') AS q90,
           max(s.created_at) AS last_at
    FROM sales s, jsonb_array_elements(s.items) x
    WHERE s.created_at >= now() - interval '180 days' GROUP BY 1
  ), p AS (
    SELECT pr.id, pr.name, pr.stock, pr.low_stock_alert, coalesce(sd.q90, 0) AS q90, sd.last_at
    FROM products pr LEFT JOIN sold sd ON sd.pid = pr.id::text
    WHERE NOT coalesce(pr.has_variants, false)
  )
  SELECT
    (SELECT count(*) FROM p) + (SELECT count(*) FROM product_variants pv JOIN products pp ON pp.id = pv.product_id
                                WHERE pp.has_variants AND coalesce(pv.is_active, true)),
    public.get_stock_value(),
    (SELECT count(*) FROM p WHERE p.stock > p.low_stock_alert OR (p.low_stock_alert = 0 AND p.stock > 0)),
    (SELECT count(*) FROM p WHERE p.stock > 0 AND p.stock <= p.low_stock_alert AND p.low_stock_alert > 0),
    (SELECT count(*) FROM p WHERE p.stock <= 0),
    (SELECT count(*) FROM p WHERE p.stock > 0 AND p.q90 < 2),
    (SELECT count(*) FROM p WHERE p.stock > 0 AND p.last_at IS NULL),
    (SELECT count(*) FROM p WHERE p.stock > 100 AND p.low_stock_alert > 0 AND p.stock > p.low_stock_alert * 5),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('name', q.name, 'stock', q.stock, 'sold_90d', q.q90) ORDER BY q.stock DESC), '[]'::jsonb)
       FROM (SELECT * FROM p WHERE p.stock > 0 AND p.q90 < 2 ORDER BY p.stock DESC LIMIT 10) q),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('name', q.name, 'low_stock_alert', q.low_stock_alert) ORDER BY q.name), '[]'::jsonb)
       FROM (SELECT * FROM p WHERE p.stock <= 0 ORDER BY p.name LIMIT 10) q),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('name', q.name, 'stock', q.stock, 'alert', q.low_stock_alert)
                               ORDER BY (q.low_stock_alert - q.stock) DESC), '[]'::jsonb)
       FROM (SELECT * FROM p WHERE p.low_stock_alert > 0 AND p.stock < p.low_stock_alert
             ORDER BY (p.low_stock_alert - p.stock) DESC LIMIT 10) q);
END $$;

-- Per-product sales velocity over 90 days (inventory + slow-moving, #24)
CREATE OR REPLACE FUNCTION public.get_product_sales_stats() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_t0 timestamptz := public.ist_day_start(public.ist_today());
BEGIN
  PERFORM public.assert_member();
  RETURN coalesce((
    WITH si AS (
      SELECT x->>'product_id' AS pid, public.jnum(x,'qty',0) AS qty, public.item_line_total(x) AS val, s.created_at
      FROM sales s, jsonb_array_elements(s.items) x
      WHERE s.created_at >= now() - interval '90 days' AND x ? 'product_id'
    ), a AS (
      SELECT pid, sum(qty) AS q90,
             sum(qty) FILTER (WHERE created_at >= now() - interval '60 days') AS q60,
             sum(qty) FILTER (WHERE created_at >= now() - interval '30 days') AS q30,
             sum(qty) FILTER (WHERE created_at >= now() - interval '15 days') AS q15,
             sum(qty) FILTER (WHERE created_at >= now() - interval '7 days') AS q7,
             sum(qty) FILTER (WHERE created_at >= v_t0) AS qt,
             sum(val) FILTER (WHERE created_at >= now() - interval '30 days') AS v30,
             max(created_at) AS last_at
      FROM si GROUP BY pid)
    SELECT jsonb_object_agg(pid, jsonb_build_object(
      'qty90d', coalesce(q90,0), 'qty60d', coalesce(q60,0), 'qty30d', coalesce(q30,0),
      'qty15d', coalesce(q15,0), 'qty7d', coalesce(q7,0), 'qtyToday', coalesce(qt,0),
      'totalValue30d', coalesce(v30,0), 'lastSoldAt', last_at,
      'daysSinceLastSale', floor(extract(epoch FROM (now() - last_at)) / 86400)))
    FROM a), '{}'::jsonb);
END $$;

-- Customer portal by unguessable token (anon allowed, read-only)
CREATE OR REPLACE FUNCTION public.get_customer_portal(p_token uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'name', c.name, 'total_credit', c.total_credit,
    'shop_name', (SELECT shop_name FROM shop_settings WHERE id = 1),
    'sales', coalesce((SELECT jsonb_agg(jsonb_build_object(
                 'invoice_no', s.invoice_no, 'created_at', s.created_at, 'final_amount', s.final_amount,
                 'amount_paid', s.amount_paid, 'due_amount', s.due_amount, 'is_credit', s.is_credit,
                 'items', (SELECT jsonb_agg(jsonb_build_object('name', x->>'name', 'qty', x->'qty', 'total', x->'total'))
                           FROM jsonb_array_elements(s.items) x)) ORDER BY s.created_at DESC)
               FROM (SELECT * FROM sales WHERE customer_id = c.id ORDER BY created_at DESC LIMIT 20) s), '[]'::jsonb))
  FROM customers c WHERE c.portal_token = p_token
$$;

-- ---------------------------------------------------------------------
-- 15. Backup / restore / factory reset — one transaction each (#31)
-- ---------------------------------------------------------------------
-- Business tables in dependency order (parents first).
CREATE OR REPLACE FUNCTION public.backup_table_list() RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY['shop_settings','app_config','customers','suppliers','products','product_variants',
               'accounts','sales','purchase_orders','purchases','inventory_batches','payments',
               'supplier_payments','expenses','account_transactions','legacy_postings','product_returns',
               'damaged_products','stock_reconciliation','payment_reminders','transaction_edits']
$$;

CREATE OR REPLACE FUNCTION public.restore_backup(p_data jsonb, p_confirm text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tab text; v_rows jsonb; v_counts jsonb := '{}'::jsonb; v_n bigint; v_col text;
BEGIN
  PERFORM public.assert_admin();
  IF p_confirm IS DISTINCT FROM 'RESTORE' THEN RAISE EXCEPTION 'Confirmation text must be RESTORE'; END IF;
  IF p_data IS NULL OR jsonb_typeof(p_data) <> 'object' OR NOT (p_data ? 'tables') THEN
    RAISE EXCEPTION 'Not a backup file (missing "tables")';
  END IF;

  PERFORM set_config('app.bulk_mode', 'on', true);   -- no stock/cash side effects while loading
  SET CONSTRAINTS ALL DEFERRED;                      -- purchases <-> purchase_orders reference each other
  EXECUTE 'TRUNCATE ' || (SELECT string_agg(format('public.%I', t), ', ') FROM unnest(public.backup_table_list()) t)
          || ' RESTART IDENTITY';

  FOREACH v_tab IN ARRAY public.backup_table_list() LOOP
    v_rows := p_data->'tables'->v_tab;
    CONTINUE WHEN v_rows IS NULL OR jsonb_typeof(v_rows) <> 'array' OR jsonb_array_length(v_rows) = 0;
    -- authors that no longer exist are kept anonymous instead of failing
    FOREACH v_col IN ARRAY ARRAY['created_by','edited_by'] LOOP
      IF EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name=v_tab AND column_name=v_col) THEN
        SELECT coalesce(jsonb_agg(CASE WHEN r ? v_col AND jsonb_typeof(r->v_col) = 'string'
                                         AND NOT EXISTS (SELECT 1 FROM profiles WHERE id::text = r->>v_col)
                                       THEN r - v_col ELSE r END), '[]'::jsonb)
          INTO v_rows FROM jsonb_array_elements(v_rows) r;
      END IF;
    END LOOP;
    EXECUTE format('INSERT INTO public.%1$I SELECT * FROM jsonb_populate_recordset(NULL::public.%1$I, $1)', v_tab)
      USING v_rows;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object(v_tab, v_n);
  END LOOP;

  PERFORM setval('sales_invoice_no_seq', greatest(coalesce((SELECT max(invoice_no) FROM sales), 0), 1),
                 (SELECT max(invoice_no) FROM sales) IS NOT NULL);
  UPDATE sales SET invoice_no = nextval('sales_invoice_no_seq') WHERE invoice_no IS NULL;
  UPDATE customers c SET total_credit = coalesce((SELECT sum(due_amount) FROM sales s WHERE s.customer_id = c.id AND s.due_amount > 0), 0);
  UPDATE suppliers x SET total_dues = coalesce((SELECT sum(due_amount) FROM purchases p WHERE p.supplier_id = x.id AND p.due_amount > 0), 0);
  PERFORM set_config('app.bulk_mode', 'off', true);
  RETURN v_counts;
END $$;

-- p_scope: 'all' = every business record (keeps users and settings)
--          'purchases_accounts' = purchases, supplier payments and the cash
--          book only; current stock is kept as opening stock.
CREATE OR REPLACE FUNCTION public.factory_reset(p_confirm text, p_scope text DEFAULT 'all')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tables text[];
BEGIN
  PERFORM public.assert_admin();
  IF p_confirm IS DISTINCT FROM 'RESET' THEN RAISE EXCEPTION 'Confirmation text must be RESET'; END IF;
  PERFORM set_config('app.bulk_mode', 'on', true);

  IF p_scope = 'purchases_accounts' THEN
    TRUNCATE public.account_transactions, public.legacy_postings, public.supplier_payments,
             public.inventory_batches, public.purchases, public.accounts;
    UPDATE purchase_orders SET purchase_id = NULL;
    UPDATE suppliers SET total_dues = 0;
    -- what is on the shelf stays valued at its current cost
    INSERT INTO inventory_batches (product_id, quantity, remaining, purchase_price)
    SELECT id, stock, stock, coalesce(purchase_price, 0) FROM products WHERE stock > 0;
  ELSIF p_scope = 'all' THEN
    v_tables := ARRAY['customers','suppliers','products','product_variants','accounts','sales','purchase_orders',
                      'purchases','inventory_batches','payments','supplier_payments','expenses',
                      'account_transactions','legacy_postings','product_returns','damaged_products',
                      'stock_reconciliation','payment_reminders','transaction_edits','audit_log',
                      'daily_analytics_summary','backups'];
    EXECUTE 'TRUNCATE ' || (SELECT string_agg(format('public.%I', t), ', ') FROM unnest(v_tables) t) || ' RESTART IDENTITY';
    PERFORM setval('sales_invoice_no_seq', 1, false);
  ELSE
    RAISE EXCEPTION 'Unknown reset scope %', p_scope;
  END IF;

  INSERT INTO accounts (name, account_type, balance) VALUES ('Cash in Hand', 'cash', 0), ('Bank Account', 'bank', 0);
  PERFORM set_config('app.bulk_mode', 'off', true);
  RETURN jsonb_build_object('scope', p_scope, 'reset_at', now());
END $$;

-- backup bookkeeping (metadata only; files live in Storage bucket "backups")
CREATE OR REPLACE FUNCTION public.get_table_row_counts() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb := '{}'::jsonb; t text; n bigint;
BEGIN
  PERFORM public.assert_admin();
  FOREACH t IN ARRAY public.backup_table_list() LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
    v := v || jsonb_build_object(t, n);
  END LOOP;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.create_backup_record(p_backup_type varchar DEFAULT 'manual') RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v uuid;
BEGIN
  PERFORM public.assert_admin();
  INSERT INTO backups (backup_type, status, row_counts, tables_included, created_by)
  VALUES (p_backup_type, 'running', public.get_table_row_counts(), public.backup_table_list(), coalesce(auth.uid()::text, current_user))
  RETURNING id INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.complete_backup(p_backup_id uuid, p_file_path text, p_file_size_bytes bigint, p_checksum varchar)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_admin();
  UPDATE backups SET status = 'completed', completed_at = now(), file_path = p_file_path,
                     file_size_bytes = p_file_size_bytes, checksum = p_checksum
  WHERE id = p_backup_id;
END $$;

CREATE OR REPLACE FUNCTION public.fail_backup(p_backup_id uuid, p_error_message text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_admin();
  UPDATE backups SET status = 'failed', completed_at = now(), error_message = p_error_message WHERE id = p_backup_id;
END $$;

CREATE OR REPLACE FUNCTION public.get_backup_history(p_limit integer DEFAULT 20)
RETURNS TABLE (id uuid, backup_type varchar, status varchar, started_at timestamptz, completed_at timestamptz,
               file_path text, file_size_bytes bigint, checksum varchar, row_counts jsonb, error_message text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.assert_admin();
  RETURN QUERY SELECT b.id, b.backup_type, b.status, b.started_at, b.completed_at, b.file_path,
                      b.file_size_bytes, b.checksum, b.row_counts, b.error_message
               FROM backups b ORDER BY b.started_at DESC LIMIT p_limit;
END $$;

CREATE OR REPLACE FUNCTION public.get_database_size_estimate() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb := '{}'::jsonb; t text; s bigint; v_total bigint;
BEGIN
  PERFORM public.assert_admin();
  SELECT pg_database_size(current_database()) INTO v_total;
  FOREACH t IN ARRAY public.backup_table_list() LOOP
    SELECT pg_total_relation_size(format('public.%I', t)::regclass) INTO s;
    v := v || jsonb_build_object(t, s);
  END LOOP;
  RETURN jsonb_build_object('total_size_bytes', v_total, 'total_size_mb', round(v_total / 1048576.0, 2), 'table_sizes', v);
END $$;

-- Tamil name maintenance — admin only now (was callable by anyone, #3)
CREATE OR REPLACE FUNCTION public.update_tamil_names(products_json jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE item jsonb;
BEGIN
  PERFORM public.assert_admin();
  FOR item IN SELECT * FROM jsonb_array_elements(products_json) LOOP
    UPDATE products SET tamil_name = item->>'tamil_name'
    WHERE id = (item->>'id')::uuid AND (tamil_name IS NULL OR tamil_name = '' OR tamil_name = name);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.clear_all_tamil_names() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_admin();
  UPDATE products SET tamil_name = NULL WHERE tamil_name IS NOT NULL;
END $$;

-- migration bookkeeping
CREATE OR REPLACE FUNCTION public.record_migration(p_version varchar, p_name varchar,
  p_checksum varchar DEFAULT NULL, p_execution_ms integer DEFAULT NULL) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO schema_migrations (version, name, applied_by, checksum, execution_ms)
  VALUES (p_version, p_name, current_user, p_checksum, p_execution_ms)
  ON CONFLICT (version) DO UPDATE SET applied_at = now(), checksum = EXCLUDED.checksum;
$$;

-- ---------------------------------------------------------------------
-- 16. One-time data backfills (bulk mode is on: no triggers fire)
-- ---------------------------------------------------------------------
INSERT INTO app_config (key, value) VALUES ('audit_fix_migrated_at', now()::text) ON CONFLICT (key) DO NOTHING;

-- 16a. Make sure the two money accounts exist; tag old journal rows.
DO $$ BEGIN PERFORM public.resolve_account('cash'); PERFORM public.resolve_account('bank'); END $$;
UPDATE account_transactions
   SET source = CASE WHEN public.is_document_category(category) THEN 'legacy' ELSE 'manual' END
 WHERE source IS NULL;

-- 16b. What the OLD app posted for each existing document (must run before
--      payment methods are normalised: the old app sent "digital" to cash).
DO $$
DECLARE v_cut timestamptz := (SELECT value::timestamptz FROM app_config WHERE key = 'audit_fix_migrated_at');
BEGIN
  -- sales: posted only if split or not credit (sale_service.dart:51)
  INSERT INTO legacy_postings (ref_type, ref_id, account_id, amount)
  SELECT 'sales', s.id, public.resolve_account(x.acct), x.amt
  FROM sales s
  CROSS JOIN LATERAL (
    SELECT 'cash' AS acct, s.cash_amount AS amt
      WHERE lower(coalesce(s.payment_method,'cash')) = 'split' AND s.cash_amount > 0 AND s.digital_amount > 0
    UNION ALL
    SELECT 'bank', s.digital_amount
      WHERE lower(coalesce(s.payment_method,'cash')) = 'split' AND s.cash_amount > 0 AND s.digital_amount > 0
    UNION ALL
    SELECT CASE WHEN lower(coalesce(s.payment_method,'cash')) IN ('upi','digital') THEN 'bank' ELSE 'cash' END, s.final_amount
      WHERE (lower(coalesce(s.payment_method,'cash')) = 'split' OR NOT coalesce(s.is_credit,false))
        AND NOT (lower(coalesce(s.payment_method,'cash')) = 'split' AND s.cash_amount > 0 AND s.digital_amount > 0)
  ) x
  WHERE s.created_at < v_cut AND x.amt > 0
    AND NOT EXISTS (SELECT 1 FROM account_transactions t WHERE t.ref_type = 'sales' AND t.ref_id = s.id)
  ON CONFLICT DO NOTHING;

  -- purchases: posted if not credit; only upi/bank went to the bank
  INSERT INTO legacy_postings (ref_type, ref_id, account_id, amount)
  SELECT 'purchases', p.id,
         public.resolve_account(CASE WHEN lower(coalesce(p.payment_method,'cash')) IN ('upi','bank') THEN 'bank' ELSE 'cash' END),
         -p.total_amount
  FROM purchases p
  WHERE p.created_at < v_cut AND NOT coalesce(p.is_credit,false) AND p.total_amount > 0
    AND NOT EXISTS (SELECT 1 FROM account_transactions t WHERE t.ref_type = 'purchases' AND t.ref_id = p.id)
  ON CONFLICT DO NOTHING;

  -- expenses: the screen never passed a method, so always cash
  INSERT INTO legacy_postings (ref_type, ref_id, account_id, amount)
  SELECT 'expenses', e.id, public.resolve_account('cash'), -e.amount
  FROM expenses e
  WHERE e.created_at < v_cut AND e.amount > 0
    AND NOT EXISTS (SELECT 1 FROM account_transactions t WHERE t.ref_type = 'expenses' AND t.ref_id = e.id)
  ON CONFLICT DO NOTHING;

  -- customer / supplier payments: only "upi" reached the bank
  INSERT INTO legacy_postings (ref_type, ref_id, account_id, amount)
  SELECT 'payments', p.id,
         public.resolve_account(CASE WHEN lower(coalesce(p.payment_method,'cash')) = 'upi' THEN 'bank' ELSE 'cash' END), p.amount
  FROM payments p
  WHERE p.created_at < v_cut AND p.amount > 0
    AND NOT EXISTS (SELECT 1 FROM account_transactions t WHERE t.ref_type = 'payments' AND t.ref_id = p.id)
  ON CONFLICT DO NOTHING;

  INSERT INTO legacy_postings (ref_type, ref_id, account_id, amount)
  SELECT 'supplier_payments', p.id,
         public.resolve_account(CASE WHEN lower(coalesce(p.payment_method,'cash')) = 'upi' THEN 'bank' ELSE 'cash' END), -p.amount
  FROM supplier_payments p
  WHERE p.created_at < v_cut AND p.amount > 0
    AND NOT EXISTS (SELECT 1 FROM account_transactions t WHERE t.ref_type = 'supplier_payments' AND t.ref_id = p.id)
  ON CONFLICT DO NOTHING;

  -- returns: refunds always left the cash drawer
  INSERT INTO legacy_postings (ref_type, ref_id, account_id, amount)
  SELECT 'product_returns', r.id, public.resolve_account('cash'), -r.refund_amount
  FROM product_returns r
  WHERE r.created_at < v_cut AND r.refund_amount > 0
    AND NOT EXISTS (SELECT 1 FROM account_transactions t WHERE t.ref_type = 'product_returns' AND t.ref_id = r.id)
  ON CONFLICT DO NOTHING;
END $$;

-- 16c. Normalise payment methods everywhere (#12)
UPDATE sales SET payment_method = public.norm_payment_method(payment_method)
 WHERE payment_method IS DISTINCT FROM public.norm_payment_method(payment_method);
UPDATE purchases SET payment_method = CASE WHEN public.norm_payment_method(payment_method) IN ('credit','split')
                                           THEN 'cash' ELSE public.norm_payment_method(payment_method) END
 WHERE payment_method IS DISTINCT FROM public.norm_payment_method(payment_method)
    OR payment_method IN ('credit','split');
UPDATE expenses SET payment_method = 'cash' WHERE payment_method IS NULL;
UPDATE payments SET payment_method = public.norm_payment_method(payment_method)
 WHERE payment_method IS DISTINCT FROM public.norm_payment_method(payment_method);
UPDATE supplier_payments SET payment_method = public.norm_payment_method(payment_method)
 WHERE payment_method IS DISTINCT FROM public.norm_payment_method(payment_method);

-- 16d. Money received at the till / paid at purchase (excludes later collections)
UPDATE sales s SET paid_at_sale = CASE
    WHEN coalesce(s.is_credit, false)
      THEN greatest(coalesce(s.amount_paid, 0) - coalesce((SELECT sum(p.amount) FROM payments p WHERE p.sale_id = s.id), 0), 0)
    ELSE coalesce(s.final_amount, 0) END
 WHERE s.paid_at_sale IS NULL;
UPDATE purchases p SET paid_at_purchase = CASE
    WHEN coalesce(p.is_credit, false)
      THEN greatest(coalesce(p.amount_paid, 0) - coalesce((SELECT sum(x.amount) FROM supplier_payments x WHERE x.purchase_id = p.id), 0), 0)
    ELSE coalesce(p.total_amount, 0) END
 WHERE p.paid_at_purchase IS NULL;

-- 16e. Returns: link both ways, value and cost for old rows
UPDATE product_returns SET original_sale_id = coalesce(original_sale_id, sale_id),
                           sale_id = coalesce(sale_id, original_sale_id)
 WHERE original_sale_id IS NULL OR sale_id IS NULL;
UPDATE product_returns SET return_amount = refund_amount WHERE coalesce(return_amount, 0) = 0;
UPDATE product_returns r SET cost_amount = round(r.quantity * coalesce((
    SELECT sum(public.item_cost(x)) / nullif(sum(public.jnum(x, 'qty', 0)), 0)
    FROM sales s, jsonb_array_elements(s.items) x
    WHERE s.id = r.original_sale_id AND x->>'product_id' = r.product_id::text), 0), 2)
 WHERE coalesce(r.cost_amount, 0) = 0;

-- 16f. GST columns for old sales and purchases
UPDATE sales s SET (cgst_amount, sgst_amount, igst_amount, taxable_amount, place_of_supply) =
  (SELECT t.cgst, t.sgst, t.igst, t.taxable, t.pos
   FROM public.compute_tax(s.items, s.final_amount,
          (SELECT c.state_code FROM customers c WHERE c.id = s.customer_id), s.tax_exempt) t)
WHERE s.taxable_amount IS NULL;
UPDATE purchases p SET (cgst_amount, sgst_amount, igst_amount, taxable_amount) =
  (SELECT t.cgst, t.sgst, t.igst, t.taxable FROM public.purchase_compute_itc(p) t)
WHERE p.taxable_amount IS NULL;

-- 16g. Denormalised balances
UPDATE customers c SET total_credit = coalesce((SELECT sum(due_amount) FROM sales s
                                               WHERE s.customer_id = c.id AND s.due_amount > 0), 0);
UPDATE suppliers x SET total_dues = coalesce((SELECT sum(due_amount) FROM purchases p
                                             WHERE p.supplier_id = x.id AND p.due_amount > 0), 0);

-- 16h. Shop settings seeded from the admin's profile
INSERT INTO shop_settings (id, shop_name, address, phone, gstin)
SELECT 1, p.shop_name, p.shop_address, p.shop_phone, p.gstin
FROM profiles p WHERE p.role = 'admin' ORDER BY p.created_at LIMIT 1
ON CONFLICT (id) DO NOTHING;
INSERT INTO shop_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- 16i. Fill e-mail on profiles for the staff screen
DO $$ BEGIN
  UPDATE profiles p SET email = u.email FROM auth.users u WHERE u.id = p.id AND p.email IS NULL;
EXCEPTION WHEN insufficient_privilege THEN NULL;
END $$;

-- 16j. Batches that hold MORE units than the product's stock: the old app
--      sometimes deducted stock without consuming batches. Those extra units
--      were sold long ago; left in place they would be costed again and
--      inflate stock value. Remove the excess from the OLDEST batches (what
--      FIFO would have used) and log each fix in stock_reconciliation.
--      Re-running finds nothing to do.
DO $$
DECLARE r record; v_fix record;
BEGIN
  FOR r IN
    SELECT p.id, greatest(coalesce(p.stock, 0), 0) AS stock, b.qty
    FROM products p
    JOIN (SELECT product_id, sum(remaining) AS qty FROM inventory_batches
          WHERE remaining > 0 GROUP BY product_id) b ON b.product_id = p.id
    WHERE NOT coalesce(p.has_variants, false)
      AND b.qty > greatest(coalesce(p.stock, 0), 0) + 0.0005
  LOOP
    SELECT * INTO v_fix FROM public.fifo_take(r.id, r.qty - r.stock, 0);
    INSERT INTO stock_reconciliation (product_id, system_qty, physical_qty, notes)
    VALUES (r.id, r.qty, r.stock,
            format('2026-10 upgrade: removed %s batch unit(s) already sold by the old app (batches %s, stock %s)',
                   r.qty - r.stock, r.qty, r.stock));
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 17. Triggers — the complete, intended set
-- ---------------------------------------------------------------------
-- sales
CREATE TRIGGER a_sales_before_insert BEFORE INSERT ON sales
  FOR EACH ROW EXECUTE FUNCTION public.sales_before_insert();
CREATE TRIGGER a_sales_before_update BEFORE UPDATE ON sales
  FOR EACH ROW EXECUTE FUNCTION public.sales_before_update();
CREATE TRIGGER b_sales_postings AFTER INSERT OR UPDATE OR DELETE ON sales
  FOR EACH ROW EXECUTE FUNCTION public.document_postings_trigger();
CREATE TRIGGER c_sales_customer_credit AFTER INSERT OR UPDATE OR DELETE ON sales
  FOR EACH ROW EXECUTE FUNCTION public.update_customer_credit();
CREATE TRIGGER z_audit_sales AFTER INSERT OR UPDATE OR DELETE ON sales
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- purchases
CREATE TRIGGER a_purchases_before_write BEFORE INSERT OR UPDATE ON purchases
  FOR EACH ROW EXECUTE FUNCTION public.purchases_before_write();
CREATE TRIGGER a_purchases_before_delete BEFORE DELETE ON purchases
  FOR EACH ROW EXECUTE FUNCTION public.purchases_before_delete();
CREATE TRIGGER b_purchases_after_insert AFTER INSERT ON purchases
  FOR EACH ROW EXECUTE FUNCTION public.purchases_after_insert();
CREATE TRIGGER b_purchases_postings AFTER INSERT OR UPDATE OR DELETE ON purchases
  FOR EACH ROW EXECUTE FUNCTION public.document_postings_trigger();
CREATE TRIGGER c_purchases_supplier_dues AFTER INSERT OR UPDATE OR DELETE ON purchases
  FOR EACH ROW EXECUTE FUNCTION public.update_supplier_dues();
CREATE TRIGGER z_audit_purchases AFTER INSERT OR UPDATE OR DELETE ON purchases
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- expenses
CREATE TRIGGER a_expenses_before_write BEFORE INSERT OR UPDATE ON expenses
  FOR EACH ROW EXECUTE FUNCTION public.expenses_before_write();
CREATE TRIGGER b_expenses_postings AFTER INSERT OR UPDATE OR DELETE ON expenses
  FOR EACH ROW EXECUTE FUNCTION public.document_postings_trigger();
CREATE TRIGGER z_audit_expenses AFTER INSERT OR UPDATE OR DELETE ON expenses
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- customer payments
CREATE TRIGGER a_payments_before_insert BEFORE INSERT ON payments
  FOR EACH ROW EXECUTE FUNCTION public.payments_before_insert();
CREATE TRIGGER b_payments_postings AFTER INSERT OR UPDATE OR DELETE ON payments
  FOR EACH ROW EXECUTE FUNCTION public.document_postings_trigger();
CREATE TRIGGER c_payments_credit AFTER INSERT OR DELETE ON payments
  FOR EACH ROW EXECUTE FUNCTION public.update_credit_after_payment();
CREATE TRIGGER z_audit_payments AFTER INSERT OR UPDATE OR DELETE ON payments
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- supplier payments
CREATE TRIGGER a_supplier_payments_before_insert BEFORE INSERT ON supplier_payments
  FOR EACH ROW EXECUTE FUNCTION public.supplier_payments_before_insert();
CREATE TRIGGER b_supplier_payments_postings AFTER INSERT OR UPDATE OR DELETE ON supplier_payments
  FOR EACH ROW EXECUTE FUNCTION public.document_postings_trigger();
CREATE TRIGGER c_supplier_payments_dues AFTER INSERT OR DELETE ON supplier_payments
  FOR EACH ROW EXECUTE FUNCTION public.update_supplier_dues_after_payment();
CREATE TRIGGER z_audit_supplier_payments AFTER INSERT OR UPDATE OR DELETE ON supplier_payments
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- returns
CREATE TRIGGER b_returns_postings AFTER INSERT OR UPDATE OR DELETE ON product_returns
  FOR EACH ROW EXECUTE FUNCTION public.document_postings_trigger();
CREATE TRIGGER z_audit_product_returns AFTER INSERT OR UPDATE OR DELETE ON product_returns
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- cash book
CREATE TRIGGER a_account_tx_before_insert BEFORE INSERT ON account_transactions
  FOR EACH ROW EXECUTE FUNCTION public.account_tx_before_insert();
CREATE TRIGGER b_account_tx_balance AFTER INSERT OR UPDATE OR DELETE ON account_transactions
  FOR EACH ROW EXECUTE FUNCTION public.account_tx_balance();
CREATE TRIGGER z_audit_account_transactions AFTER INSERT OR UPDATE OR DELETE ON account_transactions
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();

-- master data
CREATE TRIGGER z_audit_customers AFTER UPDATE OR DELETE ON customers
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();
CREATE TRIGGER z_audit_suppliers AFTER UPDATE OR DELETE ON suppliers
  FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func();
CREATE TRIGGER touch_products BEFORE UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER guard_products_stock BEFORE UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION public.guard_product_stock();
CREATE TRIGGER touch_product_variants BEFORE UPDATE ON product_variants
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER touch_purchase_orders BEFORE UPDATE ON purchase_orders
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER touch_shop_settings BEFORE UPDATE ON shop_settings
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ---------------------------------------------------------------------
-- 18. Row Level Security — complete policy set for every table (#3)
-- ---------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

-- profiles: own row or admin; column rules enforced by profiles_guard
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (id = auth.uid() OR public.is_admin());
CREATE POLICY profiles_update_own ON profiles FOR UPDATE TO authenticated USING (id = auth.uid()) WITH CHECK (id = auth.uid());
CREATE POLICY profiles_admin ON profiles FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- readable by every active member, writable by admins
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['shops','shop_settings','products','product_variants','inventory_batches','customers'] LOOP
    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (public.is_active_member())', t || '_member_read', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin())', t || '_admin_all', t);
  END LOOP;
END $$;
-- staff at the till may add a new customer for a credit sale
CREATE POLICY customers_member_insert ON customers FOR INSERT TO authenticated WITH CHECK (public.is_active_member());

-- sales: members read and create; only admins change or delete
CREATE POLICY sales_member_read ON sales FOR SELECT TO authenticated USING (public.is_active_member());
CREATE POLICY sales_member_insert ON sales FOR INSERT TO authenticated WITH CHECK (public.is_active_member());
CREATE POLICY sales_admin_all ON sales FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- app config: version check runs before login
CREATE POLICY app_config_read ON app_config FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY app_config_admin ON app_config FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- audit: members may append, only admins read
CREATE POLICY audit_log_member_insert ON audit_log FOR INSERT TO authenticated WITH CHECK (public.is_active_member());
CREATE POLICY audit_log_admin_read ON audit_log FOR SELECT TO authenticated USING (public.is_admin());

-- everything else: admins only
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['purchases','expenses','suppliers','payments','supplier_payments','accounts',
                           'account_transactions','product_returns','damaged_products','purchase_orders',
                           'stock_reconciliation','payment_reminders','transaction_edits','daily_analytics_summary',
                           'schema_migrations','backups','legacy_postings'] LOOP
    EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin())', t || '_admin_all', t);
  END LOOP;
END $$;

-- Storage bucket for cloud backups (#31), admins only
DO $$
BEGIN
  IF to_regclass('storage.buckets') IS NOT NULL THEN
    INSERT INTO storage.buckets (id, name, public) VALUES ('backups', 'backups', false) ON CONFLICT (id) DO NOTHING;
    DROP POLICY IF EXISTS "ideal_pos_backups_admin" ON storage.objects;
    CREATE POLICY "ideal_pos_backups_admin" ON storage.objects FOR ALL TO authenticated
      USING (bucket_id = 'backups' AND public.is_admin())
      WITH CHECK (bucket_id = 'backups' AND public.is_admin());
  END IF;
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'Could not create the backups storage bucket — create a private bucket named "backups" in the dashboard.';
END $$;

-- ---------------------------------------------------------------------
-- 19. Function privileges (#3): nothing is callable unless listed here.
-- ---------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon, authenticated;
DO $$ BEGIN
  ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon;
EXCEPTION WHEN others THEN NULL;
END $$;

-- used inside RLS policies, so every caller needs them
GRANT EXECUTE ON FUNCTION public.is_admin(), public.is_active_member() TO anon, authenticated;
-- read-only portal for customers (by unguessable token)
GRANT EXECUTE ON FUNCTION public.get_customer_portal(uuid) TO anon, authenticated;

-- app-callable RPCs (each one checks admin/member itself)
GRANT EXECUTE ON FUNCTION
  public.get_dashboard_summary(), public.get_product_sales_stats(), public.get_expiring_batches(integer),
  public.get_product_batches(uuid),
  public.delete_sale_atomic(uuid),
  public.edit_sale_atomic(uuid, jsonb, numeric, numeric, numeric, uuid, boolean, numeric, numeric, text, numeric, numeric, text, numeric, numeric, boolean, date),
  public.create_return_atomic(uuid, uuid, uuid, text, numeric, numeric, numeric, text, uuid, text),
  public.return_full_sale(uuid, text),
  public.create_damaged_atomic(uuid, uuid, text, numeric, numeric, text, uuid),
  public.delete_purchase_atomic(uuid),
  public.edit_purchase_atomic(uuid, jsonb, numeric, uuid, text, boolean, numeric, numeric, text, text, numeric),
  public.receive_purchase_order(uuid, boolean, numeric, text, jsonb),
  public.reconcile_stock_with_batches(uuid, numeric), public.adjust_stock(uuid, numeric),
  public.add_account_transaction(uuid, text, numeric, text, text, uuid, text, timestamptz),
  public.transfer_between_accounts(uuid, uuid, numeric, text, uuid),
  public.merge_duplicate_accounts(), public.get_account_reconciliation(),
  public.get_account_summary(timestamptz, timestamptz, uuid),
  public.get_monthly_profit(timestamptz, timestamptz), public.get_profit_loss(date, date),
  public.get_sales_total(timestamptz, timestamptz), public.get_expenses_total(timestamptz, timestamptz),
  public.get_monthly_sales_summary(), public.get_category_sales(timestamptz, timestamptz),
  public.get_daily_sales_trend(timestamptz, timestamptz), public.get_reports_summary(timestamptz, timestamptz),
  public.get_balance_sheet(), public.get_cash_flow(timestamptz, timestamptz), public.get_receivables_aging(),
  public.get_gstr3b_summary(timestamptz, timestamptz), public.get_trial_balance(),
  public.get_financial_summary(), public.get_sales_forecast(), public.get_customer_insights(),
  public.get_product_insights(), public.get_inventory_health(), public.get_stock_value(),
  public.admin_set_staff(uuid, text, text, boolean, text), public.admin_delete_staff(uuid),
  public.restore_backup(jsonb, text), public.factory_reset(text, text),
  public.get_table_row_counts(), public.create_backup_record(varchar),
  public.complete_backup(uuid, text, bigint, varchar), public.fail_backup(uuid, text),
  public.get_backup_history(integer), public.get_database_size_estimate(),
  public.update_tamil_names(jsonb), public.clear_all_tamil_names()
TO authenticated;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- ---------------------------------------------------------------------
-- 20. Done
-- ---------------------------------------------------------------------
DO $$ BEGIN PERFORM public.record_migration('v100', '2026_10_audit_fixes', 'audit-fix-1.1.0'); END $$;
DO $$ BEGIN PERFORM set_config('app.bulk_mode', 'off', true); END $$;

COMMIT;
