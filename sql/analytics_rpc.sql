-- ============================================
-- Analytics RPCs for Advanced Analytics
-- ============================================

-- Monthly sales summary for last 12 months
CREATE OR REPLACE FUNCTION get_monthly_sales_summary()
RETURNS TABLE(month TEXT, total_sales NUMERIC, total_purchases NUMERIC, total_expenses NUMERIC, profit NUMERIC)
LANGUAGE sql STABLE
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
    COALESCE((SELECT SUM(total_amount) FROM purchases WHERE date_trunc('month', created_at) = m.month), 0) AS total_purchases,
    COALESCE((SELECT SUM(amount) FROM expenses WHERE date_trunc('month', created_at) = m.month), 0) AS total_expenses,
    COALESCE((SELECT SUM(final_amount) FROM sales WHERE date_trunc('month', created_at) = m.month), 0)
    - COALESCE((SELECT SUM((item->>'purchase_price')::NUMERIC * (item->>'qty')::INT) FROM sales s, jsonb_array_elements(s.items) AS item WHERE date_trunc('month', s.created_at) = m.month), 0)
    - COALESCE((SELECT SUM(amount) FROM expenses WHERE date_trunc('month', created_at) = m.month), 0) AS profit
  FROM months m
  ORDER BY m.month;
$$;

-- Category-wise sales
CREATE OR REPLACE FUNCTION get_category_sales()
RETURNS TABLE(category TEXT, total_qty BIGINT, total_revenue NUMERIC)
LANGUAGE sql STABLE
AS $$
  SELECT 
    COALESCE(p.category, 'Uncategorized') AS category,
    SUM((item->>'qty')::int) AS total_qty,
    SUM((item->>'total')::numeric) AS total_revenue
  FROM sales s,
  jsonb_array_elements(s.items) AS item
  LEFT JOIN products p ON p.id = (item->>'product_id')::uuid
  GROUP BY p.category
  ORDER BY total_revenue DESC;
$$;

-- Daily sales trend (last 30 days)
CREATE OR REPLACE FUNCTION get_daily_sales_trend()
RETURNS TABLE(day DATE, total_sales NUMERIC, order_count BIGINT)
LANGUAGE sql STABLE
AS $$
  SELECT 
    d.day::date,
    COALESCE((SELECT SUM(final_amount) FROM sales WHERE created_at::date = d.day), 0) AS total_sales,
    COALESCE((SELECT COUNT(*) FROM sales WHERE created_at::date = d.day), 0) AS order_count
  FROM generate_series(NOW() - INTERVAL '30 days', NOW(), INTERVAL '1 day') AS d(day)
  ORDER BY d.day;
$$;
