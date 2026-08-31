-- ============================================
-- ACCOUNTS MODULE
-- Two accounts: Cash in Hand, Bank Account
-- RLS is in rls_consolidated.sql
-- ============================================

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

-- Indexes
CREATE INDEX IF NOT EXISTS idx_account_tx_account ON account_transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_account_tx_date ON account_transactions(created_at);
CREATE INDEX IF NOT EXISTS idx_account_tx_category ON account_transactions(category);

-- Atomic function: insert transaction + update balance in one operation
-- Prevents race condition where two concurrent reads get same balance
CREATE OR REPLACE FUNCTION add_account_transaction(
  p_account_id UUID,
  p_type TEXT,
  p_amount NUMERIC,
  p_category TEXT,
  p_description TEXT DEFAULT NULL,
  p_created_by UUID DEFAULT NULL
) RETURNS void AS $$
DECLARE
  v_new_balance NUMERIC;
BEGIN
  -- Insert the transaction
  INSERT INTO account_transactions (account_id, type, amount, category, description, created_by)
  VALUES (p_account_id, p_type, p_amount, p_category, p_description, p_created_by);

  -- Atomically update balance: lock the row with FOR UPDATE
  IF p_type = 'in' THEN
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_account_id RETURNING balance INTO v_new_balance;
  ELSE
    UPDATE accounts SET balance = balance - p_amount WHERE id = p_account_id RETURNING balance INTO v_new_balance;
  END IF;

  IF v_new_balance IS NULL THEN
    RAISE EXCEPTION 'Account not found: %', p_account_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Dashboard aggregation functions (avoid fetching all rows to Dart)
CREATE OR REPLACE FUNCTION get_sales_total(p_start TIMESTAMPTZ, p_end TIMESTAMPTZ)
RETURNS NUMERIC AS $$
  SELECT COALESCE(SUM(final_amount), 0) FROM sales WHERE created_at >= p_start AND created_at < p_end;
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_expenses_total(p_start TIMESTAMPTZ, p_end TIMESTAMPTZ)
RETURNS NUMERIC AS $$
  SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE created_at >= p_start AND created_at < p_end;
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_monthly_profit(p_start TIMESTAMPTZ, p_end TIMESTAMPTZ)
RETURNS TABLE(sales_total NUMERIC, purchase_cost NUMERIC, expenses_total NUMERIC, profit NUMERIC) AS $$
  SELECT
    COALESCE(SUM(s.final_amount), 0)::NUMERIC,
    COALESCE((
      SELECT SUM((item->>'purchase_price')::NUMERIC * (item->>'qty')::INT)
      FROM sales s2, jsonb_array_elements(s2.items) AS item
      WHERE s2.created_at >= p_start AND s2.created_at < p_end
    ), 0)::NUMERIC,
    COALESCE((SELECT SUM(e.amount) FROM expenses e WHERE e.created_at >= p_start AND e.created_at < p_end), 0)::NUMERIC,
    0::NUMERIC
  FROM sales s WHERE s.created_at >= p_start AND s.created_at < p_end;
$$ LANGUAGE sql SECURITY DEFINER;

-- Stock value: sum of stock * purchase_price for all products
CREATE OR REPLACE FUNCTION get_stock_value()
RETURNS NUMERIC AS $$
  SELECT COALESCE(SUM(stock * purchase_price), 0) FROM products;
$$ LANGUAGE sql SECURITY DEFINER;

-- Top products by revenue in last N days
CREATE OR REPLACE FUNCTION get_top_products(p_days INT DEFAULT 30, p_limit INT DEFAULT 5)
RETURNS TABLE(name TEXT, total NUMERIC) AS $$
  SELECT
    item->>'name' AS name,
    SUM((item->>'total')::NUMERIC) AS total
  FROM sales, jsonb_array_elements(sales.items) AS item
  WHERE sales.created_at >= NOW() - (p_days || ' days')::INTERVAL
  GROUP BY item->>'name'
  ORDER BY total DESC
  LIMIT p_limit;
$$ LANGUAGE sql SECURITY DEFINER;
