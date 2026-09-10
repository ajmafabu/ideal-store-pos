-- ============================================================
-- Phase 1: Analytics Foundation Migration
-- Fixes existing RPCs + creates server-side analytics functions
-- ============================================================

BEGIN;

-- ============================================================
-- 1. FIX EXISTING RPCs — Add date range parameters
-- ============================================================

-- Fix get_category_sales: add date range params
CREATE OR REPLACE FUNCTION get_category_sales(
  p_start TIMESTAMPTZ DEFAULT NULL,
  p_end TIMESTAMPTZ DEFAULT NULL
)
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
  WHERE (p_start IS NULL OR s.created_at >= p_start)
    AND (p_end IS NULL OR s.created_at < p_end)
  GROUP BY p.category
  ORDER BY total_revenue DESC;
$$;

-- Fix get_daily_sales_trend: add date range params
CREATE OR REPLACE FUNCTION get_daily_sales_trend(
  p_start TIMESTAMPTZ DEFAULT NULL,
  p_end TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE(day DATE, total_sales NUMERIC, order_count BIGINT)
LANGUAGE sql STABLE
AS $$
  WITH date_range AS (
    SELECT
      COALESCE(p_start, NOW() - INTERVAL '30 days') AS start_date,
      COALESCE(p_end, NOW()) AS end_date
  )
  SELECT
    d.day::date,
    COALESCE((SELECT SUM(final_amount) FROM sales WHERE created_at::date = d.day), 0) AS total_sales,
    COALESCE((SELECT COUNT(*) FROM sales WHERE created_at::date = d.day), 0) AS order_count
  FROM generate_series(
    (SELECT start_date FROM date_range)::date,
    (SELECT end_date FROM date_range)::date,
    INTERVAL '1 day'
  ) AS d(day)
  ORDER BY d.day;
$$;

-- ============================================================
-- 2. CUSTOMER INSIGHTS RPC
-- ============================================================

CREATE OR REPLACE FUNCTION get_customer_insights()
RETURNS TABLE (
  customer_id UUID,
  customer_name TEXT,
  total_purchases NUMERIC,
  total_orders BIGINT,
  avg_order_value NUMERIC,
  last_purchase_date TIMESTAMPTZ,
  days_since_last_purchase BIGINT,
  lifetime_value NUMERIC,
  churn_risk TEXT,
  segment TEXT
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  RETURN QUERY
  WITH customer_stats AS (
    SELECT
      c.id AS cid,
      c.name AS cname,
      COALESCE(SUM(s.final_amount), 0) AS total_purchases,
      COUNT(s.id) AS total_orders,
      CASE WHEN COUNT(s.id) > 0
        THEN SUM(s.final_amount) / COUNT(s.id)
        ELSE 0
      END AS avg_order_value,
      MAX(s.created_at) AS last_purchase_date
    FROM customers c
    LEFT JOIN sales s ON s.customer_id = c.id
    GROUP BY c.id, c.name
  )
  SELECT
    cs.cid AS customer_id,
    cs.cname AS customer_name,
    cs.total_purchases,
    cs.total_orders,
    ROUND(cs.avg_order_value, 2) AS avg_order_value,
    cs.last_purchase_date,
    EXTRACT(DAY FROM NOW() - cs.last_purchase_date)::BIGINT AS days_since_last_purchase,
    cs.total_purchases AS lifetime_value,
    CASE
      WHEN cs.last_purchase_date IS NULL THEN 'no_activity'
      WHEN cs.last_purchase_date < NOW() - INTERVAL '90 days' THEN 'high'
      WHEN cs.last_purchase_date < NOW() - INTERVAL '30 days' THEN 'medium'
      ELSE 'low'
    END AS churn_risk,
    CASE
      WHEN cs.total_purchases >= 50000 THEN 'platinum'
      WHEN cs.total_purchases >= 20000 THEN 'gold'
      WHEN cs.total_purchases >= 5000 THEN 'silver'
      WHEN cs.total_purchases > 0 THEN 'bronze'
      ELSE 'prospect'
    END AS segment
  FROM customer_stats cs
  ORDER BY cs.total_purchases DESC;
END;
$$;

-- ============================================================
-- 3. PRODUCT INSIGHTS RPC
-- ============================================================

CREATE OR REPLACE FUNCTION get_product_insights()
RETURNS TABLE (
  product_id UUID,
  product_name TEXT,
  category TEXT,
  current_stock INT,
  purchase_price NUMERIC,
  selling_price NUMERIC,
  total_sold BIGINT,
  total_revenue NUMERIC,
  total_profit NUMERIC,
  profit_margin NUMERIC,
  velocity_per_day NUMERIC,
  days_of_stock NUMERIC,
  abc_class TEXT,
  stock_status TEXT
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  RETURN QUERY
  WITH product_sales AS (
    SELECT
      (item->>'product_id')::uuid AS pid,
      SUM((item->>'qty')::int) AS total_sold,
      SUM((item->>'total')::numeric) AS total_revenue,
      SUM((item->>'total')::numeric - (item->>'purchase_price')::numeric * (item->>'qty')::int) AS total_profit
    FROM sales, jsonb_array_elements(sales.items) AS item
    WHERE sales.created_at >= NOW() - INTERVAL '90 days'
    GROUP BY (item->>'product_id')::uuid
  ),
  total_rev AS (
    SELECT SUM(total_revenue) AS grand_total FROM product_sales
  )
  SELECT
    pr.id AS product_id,
    pr.name AS product_name,
    COALESCE(pr.category, 'Uncategorized') AS category,
    pr.stock AS current_stock,
    pr.purchase_price,
    pr.selling_price,
    COALESCE(ps.total_sold, 0)::BIGINT AS total_sold,
    COALESCE(ps.total_revenue, 0) AS total_revenue,
    COALESCE(ps.total_profit, 0) AS total_profit,
    CASE WHEN COALESCE(ps.total_revenue, 0) > 0
      THEN ROUND((COALESCE(ps.total_profit, 0) / ps.total_revenue) * 100, 1)
      ELSE 0
    END AS profit_margin,
    CASE WHEN pr.stock > 0
      THEN ROUND(COALESCE(ps.total_sold, 0) / 90.0, 2)
      ELSE 0
    END AS velocity_per_day,
    CASE WHEN COALESCE(ps.total_sold, 0) > 0
      THEN ROUND(pr.stock / (ps.total_sold / 90.0), 0)
      ELSE 999
    END AS days_of_stock,
    CASE
      WHEN tr.grand_total > 0 AND COALESCE(ps.total_revenue, 0) >= tr.grand_total * 0.80 THEN 'A'
      WHEN tr.grand_total > 0 AND COALESCE(ps.total_revenue, 0) >= tr.grand_total * 0.95 THEN 'B'
      ELSE 'C'
    END AS abc_class,
    CASE
      WHEN pr.stock = 0 THEN 'out_of_stock'
      WHEN pr.stock <= pr.low_stock_alert THEN 'low'
      ELSE 'healthy'
    END AS stock_status
  FROM products pr
  LEFT JOIN product_sales ps ON ps.pid = pr.id
  CROSS JOIN total_rev tr
  ORDER BY COALESCE(ps.total_revenue, 0) DESC;
END;
$$;

-- ============================================================
-- 4. INVENTORY HEALTH RPC
-- ============================================================

CREATE OR REPLACE FUNCTION get_inventory_health()
RETURNS TABLE (
  total_products BIGINT,
  total_stock_value NUMERIC,
  healthy_count BIGINT,
  low_stock_count BIGINT,
  out_of_stock_count BIGINT,
  slow_moving_count BIGINT,
  dead_stock_count BIGINT,
  overstock_count BIGINT,
  slow_moving_items JSONB,
  out_of_stock_items JSONB,
  top_reorder_items JSONB
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_slow JSONB;
  v_out JSONB;
  v_reorder JSONB;
BEGIN
  -- Slow moving: sold < 2 units in 90 days but has stock
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'stock', stock, 'sold_90d', sold_90d)), '[]'::jsonb)
  INTO v_slow
  FROM (
    SELECT pr.name, pr.stock,
      COALESCE((SELECT SUM((item->>'qty')::int) FROM sales, jsonb_array_elements(sales.items) AS item
        WHERE (item->>'product_id')::uuid = pr.id AND sales.created_at >= NOW() - INTERVAL '90 days'), 0) AS sold_90d
    FROM products pr WHERE pr.stock > 0
  ) sub WHERE sold_90d < 2
  ORDER BY stock DESC LIMIT 10;

  -- Out of stock
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'low_stock_alert', low_stock_alert)), '[]'::jsonb)
  INTO v_out
  FROM products WHERE stock = 0 AND low_stock_alert > 0
  ORDER BY name LIMIT 10;

  -- Top reorder: stock < low_stock_alert
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'stock', stock, 'alert', low_stock_alert)), '[]'::jsonb)
  INTO v_reorder
  FROM products WHERE stock < low_stock_alert AND low_stock_alert > 0
  ORDER BY (low_stock_alert - stock) DESC LIMIT 10;

  RETURN QUERY
  SELECT
    (SELECT COUNT(*) FROM products)::BIGINT AS total_products,
    COALESCE((SELECT SUM(stock * purchase_price) FROM products), 0) AS total_stock_value,
    (SELECT COUNT(*) FROM products WHERE stock > low_stock_alert OR low_stock_alert = 0)::BIGINT AS healthy_count,
    (SELECT COUNT(*) FROM products WHERE stock > 0 AND stock <= low_stock_alert AND low_stock_alert > 0)::BIGINT AS low_stock_count,
    (SELECT COUNT(*) FROM products WHERE stock = 0)::BIGINT AS out_of_stock_count,
    (SELECT COUNT(*) FROM (
      SELECT pr.id FROM products pr WHERE pr.stock > 0
      AND COALESCE((SELECT SUM((item->>'qty')::int) FROM sales, jsonb_array_elements(sales.items) AS item
        WHERE (item->>'product_id')::uuid = pr.id AND sales.created_at >= NOW() - INTERVAL '90 days'), 0) < 2
    ) sub)::BIGINT AS slow_moving_count,
    (SELECT COUNT(*) FROM products WHERE stock > 0 AND NOT EXISTS (
      SELECT 1 FROM sales, jsonb_array_elements(sales.items) AS item
      WHERE (item->>'product_id')::uuid = products.id AND sales.created_at >= NOW() - INTERVAL '180 days'
    ))::BIGINT AS dead_stock_count,
    (SELECT COUNT(*) FROM products WHERE stock > 100 AND low_stock_alert > 0 AND stock > low_stock_alert * 5)::BIGINT AS overstock_count,
    v_slow AS slow_moving_items,
    v_out AS out_of_stock_items,
    v_reorder AS top_reorder_items;
END;
$$;

-- ============================================================
-- 5. FINANCIAL SUMMARY RPC
-- ============================================================

CREATE OR REPLACE FUNCTION get_financial_summary()
RETURNS TABLE (
  cash_position NUMERIC,
  bank_position NUMERIC,
  total_cash_bank NUMERIC,
  total_receivables NUMERIC,
  total_payables NUMERIC,
  net_position NUMERIC,
  monthly_sales NUMERIC,
  monthly_purchases NUMERIC,
  monthly_expenses NUMERIC,
  monthly_profit NUMERIC,
  gross_margin_pct NUMERIC,
  expense_ratio_pct NUMERIC,
  cash_runway_days NUMERIC
)
LANGUAGE sql STABLE
AS $$
  WITH cash_data AS (
    SELECT
      COALESCE(SUM(CASE WHEN name ILIKE '%cash%' THEN balance ELSE 0 END), 0) AS cash_pos,
      COALESCE(SUM(CASE WHEN name ILIKE '%bank%' THEN balance ELSE 0 END), 0) AS bank_pos
    FROM accounts
  ),
  monthly AS (
    SELECT
      COALESCE(SUM(s.final_amount), 0) AS sales,
      COALESCE((SELECT SUM(p.total_amount) FROM purchases p
        WHERE p.created_at >= date_trunc('month', NOW())), 0) AS purchases,
      COALESCE((SELECT SUM(e.amount) FROM expenses e
        WHERE e.created_at >= date_trunc('month', NOW())), 0) AS expenses
    FROM sales s WHERE s.created_at >= date_trunc('month', NOW())
  ),
  receivables AS (
    SELECT COALESCE(SUM(due_amount), 0) AS total FROM sales WHERE is_credit = true AND due_amount > 0
  ),
  payables AS (
    SELECT COALESCE(SUM(due_amount), 0) AS total FROM purchases WHERE is_credit = true AND due_amount > 0
  )
  SELECT
    cd.cash_pos,
    cd.bank_pos,
    cd.cash_pos + cd.bank_pos AS total_cash_bank,
    r.total AS total_receivables,
    p.total AS total_payables,
    (cd.cash_pos + cd.bank_pos + r.total - p.total) AS net_position,
    m.sales AS monthly_sales,
    m.purchases AS monthly_purchases,
    m.expenses AS monthly_expenses,
    (m.sales - m.purchases - m.expenses) AS monthly_profit,
    CASE WHEN m.sales > 0
      THEN ROUND(((m.sales - m.purchases) / m.sales) * 100, 1)
      ELSE 0
    END AS gross_margin_pct,
    CASE WHEN m.sales > 0
      THEN ROUND((m.expenses / m.sales) * 100, 1)
      ELSE 0
    END AS expense_ratio_pct,
    CASE WHEN m.expenses > 0
      THEN ROUND((cd.cash_pos + cd.bank_pos) / (m.expenses / 30), 0)
      ELSE 999
    END AS cash_runway_days
  FROM cash_data cd, monthly m, receivables r, payables p;
$$;

-- ============================================================
-- 6. SALES FORECAST RPC
-- ============================================================

CREATE OR REPLACE FUNCTION get_sales_forecast()
RETURNS TABLE (
  current_month_sales NUMERIC,
  days_elapsed INT,
  days_in_month INT,
  projected_monthly_sales NUMERIC,
  last_month_sales NUMERIC,
  month_over_month_pct NUMERIC,
  daily_average NUMERIC,
  trend_direction TEXT,
  forecast_confidence TEXT
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_current_sales NUMERIC;
  v_days_elapsed INT;
  v_days_in_month INT;
  v_last_month_sales NUMERIC;
  v_daily_avg NUMERIC;
BEGIN
  -- Current month sales
  SELECT COALESCE(SUM(final_amount), 0) INTO v_current_sales
  FROM sales WHERE created_at >= date_trunc('month', NOW());

  -- Days elapsed this month
  v_days_elapsed := EXTRACT(DAY FROM NOW() - date_trunc('month', NOW()))::INT + 1;
  v_days_in_month := EXTRACT(DAY FROM (
    date_trunc('month', NOW()) + INTERVAL '1 month - 1 day'
  ))::INT;

  -- Last month sales
  SELECT COALESCE(SUM(final_amount), 0) INTO v_last_month_sales
  FROM sales WHERE created_at >= date_trunc('month', NOW() - INTERVAL '1 month')
    AND created_at < date_trunc('month', NOW());

  v_daily_avg := CASE WHEN v_days_elapsed > 0
    THEN v_current_sales / v_days_elapsed
    ELSE 0
  END;

  RETURN QUERY
  SELECT
    v_current_sales AS current_month_sales,
    v_days_elapsed AS days_elapsed,
    v_days_in_month AS days_in_month,
    ROUND(v_daily_avg * v_days_in_month, 2) AS projected_monthly_sales,
    v_last_month_sales AS last_month_sales,
    CASE WHEN v_last_month_sales > 0
      THEN ROUND(((v_current_sales / GREATEST(v_days_elapsed, 1) * v_days_in_month - v_last_month_sales) / v_last_month_sales) * 100, 1)
      ELSE 0
    END AS month_over_month_pct,
    ROUND(v_daily_avg, 2) AS daily_average,
    CASE
      WHEN v_daily_avg > (v_last_month_sales / v_days_in_month) * 1.1 THEN 'growing'
      WHEN v_daily_avg < (v_last_month_sales / v_days_in_month) * 0.9 THEN 'declining'
      ELSE 'stable'
    END AS trend_direction,
    CASE
      WHEN v_days_elapsed >= 15 THEN 'high'
      WHEN v_days_elapsed >= 7 THEN 'medium'
      ELSE 'low'
    END AS forecast_confidence;
END;
$$;

-- ============================================================
-- 7. DAILY ANALYTICS SUMMARY TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS daily_analytics_summary (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  date DATE NOT NULL UNIQUE,
  total_sales NUMERIC DEFAULT 0,
  total_purchases NUMERIC DEFAULT 0,
  total_expenses NUMERIC DEFAULT 0,
  profit NUMERIC DEFAULT 0,
  orders_count INT DEFAULT 0,
  items_sold INT DEFAULT 0,
  credit_sales NUMERIC DEFAULT 0,
  cash_sales NUMERIC DEFAULT 0,
  returns_count INT DEFAULT 0,
  returns_amount NUMERIC DEFAULT 0,
  unique_customers INT DEFAULT 0,
  avg_order_value NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE daily_analytics_summary ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can read daily_analytics" ON daily_analytics_summary FOR SELECT USING (true);
CREATE POLICY "Service role can manage daily_analytics" ON daily_analytics_summary FOR ALL USING (true);

-- Index for date range queries
CREATE INDEX IF NOT EXISTS idx_daily_analytics_date ON daily_analytics_summary(date DESC);

-- ============================================================
-- 8. FUNCTION TO POPULATE DAILY SUMMARY
-- ============================================================

CREATE OR REPLACE FUNCTION populate_daily_analytics(p_date DATE)
RETURNS void AS $$
DECLARE
  v_next_date DATE := p_date + INTERVAL '1 day';
BEGIN
  INSERT INTO daily_analytics_summary (
    date, total_sales, total_purchases, total_expenses, profit,
    orders_count, items_sold, credit_sales, cash_sales,
    returns_count, returns_amount, unique_customers, avg_order_value,
    updated_at
  )
  SELECT
    p_date,
    -- Sales
    COALESCE((SELECT SUM(final_amount) FROM sales
      WHERE created_at >= p_date AND created_at < v_next_date), 0),
    -- Purchases
    COALESCE((SELECT SUM(total_amount) FROM purchases
      WHERE created_at >= p_date AND created_at < v_next_date), 0),
    -- Expenses
    COALESCE((SELECT SUM(amount) FROM expenses
      WHERE created_at >= p_date AND created_at < v_next_date), 0),
    -- Profit (sales - purchase cost - expenses)
    0, -- calculated below
    -- Orders count
    COALESCE((SELECT COUNT(*) FROM sales
      WHERE created_at >= p_date AND created_at < v_next_date), 0),
    -- Items sold
    COALESCE((SELECT SUM((item->>'qty')::int) FROM sales s,
      jsonb_array_elements(s.items) AS item
      WHERE s.created_at >= p_date AND s.created_at < v_next_date), 0),
    -- Credit sales
    COALESCE((SELECT SUM(final_amount) FROM sales
      WHERE created_at >= p_date AND created_at < v_next_date
      AND is_credit = true), 0),
    -- Cash sales
    COALESCE((SELECT SUM(final_amount) FROM sales
      WHERE created_at >= p_date AND created_at < v_next_date
      AND payment_method = 'CASH'), 0),
    -- Returns count
    COALESCE((SELECT COUNT(*) FROM product_returns
      WHERE created_at >= p_date AND created_at < v_next_date), 0),
    -- Returns amount
    COALESCE((SELECT SUM(return_amount) FROM product_returns
      WHERE created_at >= p_date AND created_at < v_next_date), 0),
    -- Unique customers
    COALESCE((SELECT COUNT(DISTINCT customer_id) FROM sales
      WHERE created_at >= p_date AND created_at < v_next_date
      AND customer_id IS NOT NULL), 0),
    -- Avg order value
    0, -- calculated below
    NOW()
  ON CONFLICT (date) DO UPDATE SET
    total_sales = EXCLUDED.total_sales,
    total_purchases = EXCLUDED.total_purchases,
    total_expenses = EXCLUDED.total_expenses,
    profit = EXCLUDED.profit,
    orders_count = EXCLUDED.orders_count,
    items_sold = EXCLUDED.items_sold,
    credit_sales = EXCLUDED.credit_sales,
    cash_sales = EXCLUDED.cash_sales,
    returns_count = EXCLUDED.returns_count,
    returns_amount = EXCLUDED.returns_amount,
    unique_customers = EXCLUDED.unique_customers,
    avg_order_value = EXCLUDED.avg_order_value,
    updated_at = NOW();

  -- Update calculated fields
  UPDATE daily_analytics_summary SET
    profit = total_sales - total_purchases - total_expenses,
    avg_order_value = CASE WHEN orders_count > 0
      THEN ROUND(total_sales / orders_count, 2)
      ELSE 0
    END
  WHERE date = p_date;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 9. FUNCTION TO BACKFILL DAILY ANALYTICS
-- ============================================================

CREATE OR REPLACE FUNCTION backfill_daily_analytics(
  p_start DATE DEFAULT (NOW() - INTERVAL '90 days')::DATE,
  p_end DATE DEFAULT CURRENT_DATE
)
RETURNS void AS $$
DECLARE
  d DATE;
BEGIN
  d := p_start;
  WHILE d <= p_end LOOP
    PERFORM populate_daily_analytics(d);
    d := d + INTERVAL '1 day';
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 10. FUNCTION TO AUTO-POPULATE TODAY (run daily via cron or trigger)
-- ============================================================

CREATE OR REPLACE FUNCTION refresh_today_analytics()
RETURNS void AS $$
BEGIN
  PERFORM populate_daily_analytics(CURRENT_DATE);
  -- Also refresh yesterday in case of late syncs
  PERFORM populate_daily_analytics(CURRENT_DATE - 1);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 11. GRANTS
-- ============================================================

GRANT EXECUTE ON FUNCTION get_customer_insights() TO authenticated;
GRANT EXECUTE ON FUNCTION get_product_insights() TO authenticated;
GRANT EXECUTE ON FUNCTION get_inventory_health() TO authenticated;
GRANT EXECUTE ON FUNCTION get_financial_summary() TO authenticated;
GRANT EXECUTE ON FUNCTION get_sales_forecast() TO authenticated;
GRANT EXECUTE ON FUNCTION get_category_sales(TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION get_daily_sales_trend(TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION populate_daily_analytics(DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION backfill_daily_analytics(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION refresh_today_analytics() TO authenticated;
GRANT ALL ON daily_analytics_summary TO authenticated;

COMMIT;
