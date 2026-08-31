-- ============================================
-- Fix: Profit calculation
-- COGS = purchase_price × qty for items SOLD
-- NOT total purchases (which includes unsold inventory)
-- ============================================

DROP FUNCTION IF EXISTS get_monthly_sales_summary();
DROP FUNCTION IF EXISTS get_monthly_profit(timestamp with time zone, timestamp with time zone);

-- Monthly sales summary with correct COGS
CREATE OR REPLACE FUNCTION get_monthly_sales_summary()
RETURNS TABLE(month TEXT, total_sales NUMERIC, total_purchases NUMERIC, total_expenses NUMERIC, profit NUMERIC)
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  WITH months AS (
    SELECT generate_series(
      date_trunc('month', NOW() - INTERVAL '11 months'),
      date_trunc('month', NOW()),
      INTERVAL '1 month'
    ) AS month
  )
  SELECT
    TO_CHAR(m.month, 'Mon YYYY') AS month,
    COALESCE((SELECT SUM(final_amount) FROM sales WHERE date_trunc('month', created_at) = m.month), 0) AS total_sales,
    COALESCE((SELECT SUM((item->>'purchase_price')::NUMERIC * (item->>'qty')::INT) FROM sales s, jsonb_array_elements(s.items) AS item WHERE date_trunc('month', s.created_at) = m.month), 0) AS total_purchases,
    COALESCE((SELECT SUM(amount) FROM expenses WHERE date_trunc('month', created_at) = m.month), 0) AS total_expenses,
    COALESCE((SELECT SUM(final_amount) FROM sales WHERE date_trunc('month', created_at) = m.month), 0)
    - COALESCE((SELECT SUM((item->>'purchase_price')::NUMERIC * (item->>'qty')::INT) FROM sales s, jsonb_array_elements(s.items) AS item WHERE date_trunc('month', s.created_at) = m.month), 0)
    - COALESCE((SELECT SUM(amount) FROM expenses WHERE date_trunc('month', created_at) = m.month), 0) AS profit
  FROM months m
  ORDER BY m.month;
$$;

-- Monthly profit with correct COGS
CREATE OR REPLACE FUNCTION get_monthly_profit(
    p_start TIMESTAMPTZ,
    p_end TIMESTAMPTZ
)
RETURNS TABLE (
    sales_total NUMERIC,
    purchase_cost NUMERIC,
    expenses_total NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE((SELECT SUM(s.final_amount) FROM sales s WHERE s.created_at >= p_start AND s.created_at < p_end), 0),
        COALESCE((SELECT SUM((item->>'purchase_price')::NUMERIC * (item->>'qty')::INT) FROM sales s, jsonb_array_elements(s.items) AS item WHERE s.created_at >= p_start AND s.created_at < p_end), 0),
        COALESCE((SELECT SUM(e.amount) FROM expenses e WHERE e.created_at >= p_start AND e.created_at < p_end), 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
