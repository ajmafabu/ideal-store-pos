BEGIN;

-- ============================================
-- Cash Flow Statement RPC
-- Returns Operating Cash Flow
-- ============================================

CREATE OR REPLACE FUNCTION get_cash_flow(
  p_start TIMESTAMP,
  p_end TIMESTAMP
)
RETURNS TABLE(
  cash_sales NUMERIC,
  digital_sales NUMERIC,
  total_sales_inflow NUMERIC,
  purchase_payments NUMERIC,
  expense_payments NUMERIC,
  total_outflow NUMERIC,
  net_cash_flow NUMERIC,
  opening_balance NUMERIC,
  closing_balance NUMERIC,
  cash_received_customers NUMERIC,
  cash_paid_suppliers NUMERIC
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_cash_sales NUMERIC := 0;
  v_digital_sales NUMERIC := 0;
  v_purchase_payments NUMERIC := 0;
  v_expense_payments NUMERIC := 0;
  v_cash_received_customers NUMERIC := 0;
  v_cash_paid_suppliers NUMERIC := 0;
BEGIN
  -- Cash inflows from sales
  SELECT COALESCE(SUM(cash_amount), 0) INTO v_cash_sales
  FROM sales
  WHERE created_at >= p_start AND created_at < p_end
    AND is_credit = false;

  SELECT COALESCE(SUM(digital_amount), 0) INTO v_digital_sales
  FROM sales
  WHERE created_at >= p_start AND created_at < p_end
    AND is_credit = false;

  -- Cash received from credit customers (partial payments)
  SELECT COALESCE(SUM(amount_paid), 0) INTO v_cash_received_customers
  FROM sales
  WHERE created_at >= p_start AND created_at < p_end
    AND is_credit = true
    AND amount_paid > 0;

  -- Purchase payments (cash purchases)
  SELECT COALESCE(SUM(
    CASE WHEN payment_method = 'cash' THEN total_amount ELSE 0 END
  ), 0) INTO v_cash_paid_suppliers
  FROM purchases
  WHERE created_at >= p_start AND created_at < p_end;

  -- Expense payments
  SELECT COALESCE(SUM(amount), 0) INTO v_expense_payments
  FROM expenses
  WHERE created_at >= p_start AND created_at < p_end;

  -- Calculate totals
  v_purchase_payments := v_cash_paid_suppliers;

  -- Return results
  RETURN QUERY
  SELECT
    v_cash_sales,
    v_digital_sales,
    v_cash_sales + v_digital_sales + v_cash_received_customers AS total_sales_inflow,
    v_purchase_payments,
    v_expense_payments,
    v_purchase_payments + v_expense_payments AS total_outflow,
    (v_cash_sales + v_digital_sales + v_cash_received_customers) - (v_purchase_payments + v_expense_payments) AS net_cash_flow,
    0::NUMERIC AS opening_balance,  -- Will be calculated separately if needed
    (v_cash_sales + v_digital_sales + v_cash_received_customers) - (v_purchase_payments + v_expense_payments) AS closing_balance,
    v_cash_received_customers,
    v_cash_paid_suppliers;
END;
$$;

COMMIT;
