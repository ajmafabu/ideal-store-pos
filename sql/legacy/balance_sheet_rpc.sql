BEGIN;

-- ============================================
-- Balance Sheet RPC
-- Returns Assets, Liabilities, and Equity
-- ============================================

CREATE OR REPLACE FUNCTION get_balance_sheet()
RETURNS TABLE(
  cash_in_hand NUMERIC,
  bank_balance NUMERIC,
  inventory_value NUMERIC,
  total_receivables NUMERIC,
  total_assets NUMERIC,
  total_payables NUMERIC,
  credit_purchase_dues NUMERIC,
  total_liabilities NUMERIC,
  owner_capital NUMERIC,
  retained_earnings NUMERIC,
  total_equity NUMERIC,
  balance_check BOOLEAN
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_cash_in_hand NUMERIC := 0;
  v_bank_balance NUMERIC := 0;
  v_inventory_value NUMERIC := 0;
  v_total_receivables NUMERIC := 0;
  v_total_payables NUMERIC := 0;
  v_credit_purchase_dues NUMERIC := 0;
  v_owner_capital NUMERIC := 0;
  v_retained_earnings NUMERIC := 0;
BEGIN
  -- ASSETS
  
  -- Cash in hand (sum of cash payments received)
  SELECT COALESCE(SUM(cash_amount), 0) INTO v_cash_in_hand
  FROM sales
  WHERE payment_method IN ('cash', 'split')
    AND is_credit = false;
  
  -- Bank balance (sum of digital payments received)
  SELECT COALESCE(SUM(digital_amount), 0) INTO v_bank_balance
  FROM sales
  WHERE payment_method IN ('digital', 'upi', 'split')
    AND is_credit = false;
  
  -- Inventory value (stockqty * purchase_price)
  SELECT COALESCE(SUM(stockqty * purchase_price), 0) INTO v_inventory_value
  FROM products
  WHERE stockqty > 0;
  
  -- Total receivables (customer credit dues)
  SELECT COALESCE(SUM(due_amount), 0) INTO v_total_receivables
  FROM sales
  WHERE is_credit = true AND due_amount > 0;
  
  -- LIABILITIES
  
  -- Total payables (supplier credit dues)
  SELECT COALESCE(SUM(due_amount), 0) INTO v_total_payables
  FROM purchases
  WHERE is_credit = true AND due_amount > 0;
  
  -- Credit purchase dues (same as above, for clarity)
  v_credit_purchase_dues := v_total_payables;
  
  -- EQUITY
  
  -- Owner's capital (total cash投入 = total sales cash received - total purchases paid)
  SELECT COALESCE(SUM(
    CASE WHEN payment_method IN ('cash', 'split') AND is_credit = false 
         THEN cash_amount ELSE 0 END
  ), 0) INTO v_owner_capital
  FROM sales;
  
  -- Retained earnings (total profit = sales - COGS - expenses)
  SELECT COALESCE(SUM(final_amount), 0) INTO v_retained_earnings
  FROM sales;
  
  -- Subtract COGS
  SELECT v_retained_earnings - COALESCE(SUM(
    (item->>'purchase_price')::NUMERIC * (item->>'qty')::INT
  ), 0) INTO v_retained_earnings
  FROM sales s, jsonb_array_elements(s.items) AS item;
  
  -- Subtract expenses
  SELECT v_retained_earnings - COALESCE(SUM(amount), 0) INTO v_retained_earnings
  FROM expenses;
  
  -- Return results
  RETURN QUERY
  SELECT
    v_cash_in_hand,
    v_bank_balance,
    v_inventory_value,
    v_total_receivables,
    v_cash_in_hand + v_bank_balance + v_inventory_value + v_total_receivables AS total_assets,
    v_total_payables,
    v_credit_purchase_dues,
    v_total_payables AS total_liabilities,
    v_owner_capital,
    v_retained_earnings,
    v_owner_capital + v_retained_earnings AS total_equity,
    (v_cash_in_hand + v_bank_balance + v_inventory_value + v_total_receivables) = 
    (v_total_payables + v_owner_capital + v_retained_earnings) AS balance_check;
END;
$$;

COMMIT;
