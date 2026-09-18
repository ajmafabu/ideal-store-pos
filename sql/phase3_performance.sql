-- ============================================
-- PHASE 3: PERFORMANCE
-- Run this ONCE in Supabase SQL Editor
-- ============================================

BEGIN;

-- ============================================
-- P1-5: Consolidated Dashboard RPC
-- ============================================
-- Replaces 6+ individual RPCs with a single call.
-- Returns: today_sales, yesterday_sales, today_expenses,
-- monthly_sales, monthly_cogs, monthly_expenses, monthly_profit,
-- stock_value, total_products, total_customers, low_stock_count,
-- top_products, recent_sales, weekly_sales
-- ============================================

CREATE OR REPLACE FUNCTION get_dashboard_summary()
RETURNS JSONB AS $$
DECLARE
  v_today_start TIMESTAMPTZ := date_trunc('day', NOW());
  v_today_end TIMESTAMPTZ := date_trunc('day', NOW()) + INTERVAL '1 day';
  v_yesterday_start TIMESTAMPTZ := v_today_start - INTERVAL '1 day';
  v_month_start TIMESTAMPTZ := date_trunc('month', NOW());
  v_result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'today_sales', (SELECT COALESCE(SUM(final_amount), 0) FROM sales WHERE created_at >= v_today_start AND created_at < v_today_end),
    'yesterday_sales', (SELECT COALESCE(SUM(final_amount), 0) FROM sales WHERE created_at >= v_yesterday_start AND created_at < v_today_start),
    'today_expenses', (SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE created_at >= v_today_start AND created_at < v_today_end),
    'monthly_sales', (SELECT COALESCE(SUM(final_amount), 0) FROM sales WHERE created_at >= v_month_start),
    'monthly_cogs', (SELECT COALESCE(SUM((item->>'purchase_price')::NUMERIC * (item->>'qty')::INT), 0)
      FROM sales s, jsonb_array_elements(s.items) AS item WHERE s.created_at >= v_month_start),
    'monthly_expenses', (SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE created_at >= v_month_start),
    'stock_value', (SELECT COALESCE(
      (SELECT SUM(stock * purchase_price) FROM products WHERE has_variants = false)
      + (SELECT COALESCE(SUM(pv.stock * pv.purchase_price), 0) FROM product_variants pv
         JOIN products p ON p.id = pv.product_id WHERE p.has_variants = true AND pv.is_active = true), 0)),
    'total_products', (SELECT COUNT(*) FROM products),
    'total_customers', (SELECT COUNT(*) FROM customers),
    'low_stock_count', (SELECT COUNT(*) FROM products WHERE stock > 0 AND stock <= low_stock_alert AND low_stock_alert > 0 AND has_variants = false),
    'today_order_count', (SELECT COUNT(*) FROM sales WHERE created_at >= v_today_start AND created_at < v_today_end),
    'top_products', (SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
      SELECT item->>'name' AS name, SUM((item->>'total')::NUMERIC) AS total
      FROM sales s, jsonb_array_elements(s.items) AS item
      WHERE s.created_at >= v_month_start
      GROUP BY item->>'name' ORDER BY total DESC LIMIT 5
    ) t),
    'recent_sales', (SELECT COALESCE(jsonb_agg(r), '[]'::jsonb) FROM (
      SELECT id, final_amount, payment_method, created_at
      FROM sales WHERE created_at >= v_today_start AND created_at < v_today_end
      ORDER BY created_at DESC LIMIT 10
    ) r),
    'weekly_sales', (SELECT COALESCE(jsonb_agg(w), '[]'::jsonb) FROM (
      SELECT to_char(d.day, 'Dy') AS day,
             COALESCE((SELECT SUM(final_amount) FROM sales WHERE created_at::date = d.day::date), 0) AS total
      FROM generate_series(v_today_start::date - INTERVAL '6 days', v_today_start::date, INTERVAL '1 day') AS d(day)
      ORDER BY d.day
    ) w)
  ) INTO v_result;

  -- Compute derived fields
  v_result := v_result || jsonb_build_object(
    'monthly_profit', (v_result->>'monthly_sales')::NUMERIC
                      - (v_result->>'monthly_cogs')::NUMERIC
                      - (v_result->>'monthly_expenses')::NUMERIC
  );

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================
-- P1-6: Batch Product Sales Stats RPC
-- ============================================
-- Replaces the Dart-side N+1 aggregation.
-- Returns per-product sales stats for the last 90 days in a single query.
-- ============================================

CREATE OR REPLACE FUNCTION get_product_sales_stats()
RETURNS JSONB AS $$
DECLARE
  v_now TIMESTAMPTZ := NOW();
  v_since90 TIMESTAMPTZ := NOW() - INTERVAL '90 days';
  v_since60 TIMESTAMPTZ := NOW() - INTERVAL '60 days';
  v_since30 TIMESTAMPTZ := NOW() - INTERVAL '30 days';
  v_since15 TIMESTAMPTZ := NOW() - INTERVAL '15 days';
  v_since7 TIMESTAMPTZ := NOW() - INTERVAL '7 days';
  v_today TIMESTAMPTZ := date_trunc('day', NOW());
BEGIN
  RETURN (
    WITH sale_items AS (
      SELECT
        (item->>'product_id')::UUID AS product_id,
        (item->>'qty')::INT AS qty,
        (item->>'price')::NUMERIC AS price,
        s.created_at
      FROM sales s, jsonb_array_elements(s.items) AS item
      WHERE s.created_at >= v_since90
        AND (item->>'product_id')::UUID IS NOT NULL
    ),
    aggregated AS (
      SELECT
        product_id,
        SUM(qty) AS qty_90d,
        SUM(CASE WHEN created_at >= v_since60 THEN qty ELSE 0 END) AS qty_60d,
        SUM(CASE WHEN created_at >= v_since30 THEN qty ELSE 0 END) AS qty_30d,
        SUM(CASE WHEN created_at >= v_since15 THEN qty ELSE 0 END) AS qty_15d,
        SUM(CASE WHEN created_at >= v_since7 THEN qty ELSE 0 END) AS qty_7d,
        SUM(CASE WHEN created_at >= v_today THEN qty ELSE 0 END) AS qty_today,
        SUM(CASE WHEN created_at >= v_since30 THEN qty * price ELSE 0 END) AS total_value_30d,
        MAX(created_at) AS last_sold_at
      FROM sale_items
      GROUP BY product_id
    )
    SELECT jsonb_object_agg(
      product_id::TEXT,
      jsonb_build_object(
        'qty90d', qty_90d,
        'qty60d', qty_60d,
        'qty30d', qty_30d,
        'qty15d', qty_15d,
        'qty7d', qty_7d,
        'qtyToday', qty_today,
        'totalValue30d', total_value_30d,
        'lastSoldAt', last_sold_at,
        'daysSinceLastSale', EXTRACT(EPOCH FROM (v_now - last_sold_at)) / 86400
      )
    )
    FROM aggregated
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================
-- PERF-4: Optimized get_inventory_health
-- ============================================
-- CHANGES: Replaced per-product correlated subqueries with CTE-based
-- pre-aggregated sales data. Instead of running a subquery for EACH product
-- (N+1 in SQL), we aggregate all sales once and join.
-- ============================================

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
  -- Pre-aggregate sales data for the last 90 days (one pass, not per-product)
  CREATE TEMPORARY TABLE IF NOT EXISTS _product_sales_90d AS
  SELECT
    (item->>'product_id')::UUID AS product_id,
    SUM((item->>'qty')::INT) AS sold_90d
  FROM sales s, jsonb_array_elements(s.items) AS item
  WHERE s.created_at >= NOW() - INTERVAL '90 days'
  GROUP BY (item->>'product_id')::UUID;

  -- Slow moving: sold < 2 units in 90 days but has stock
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'stock', stock, 'sold_90d', sold_90d)), '[]'::jsonb)
  INTO v_slow
  FROM (
    SELECT pr.name, pr.stock, COALESCE(ps.sold_90d, 0) AS sold_90d
    FROM products pr
    LEFT JOIN _product_sales_90d ps ON ps.product_id = pr.id
    WHERE pr.stock > 0 AND pr.has_variants = false
  ) sub WHERE sold_90d < 2
  ORDER BY stock DESC LIMIT 10;

  -- Out of stock
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'low_stock_alert', low_stock_alert)), '[]'::jsonb)
  INTO v_out
  FROM products WHERE stock = 0 AND low_stock_alert > 0 AND has_variants = false
  ORDER BY name LIMIT 10;

  -- Top reorder: stock < low_stock_alert
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'stock', stock, 'alert', low_stock_alert)), '[]'::jsonb)
  INTO v_reorder
  FROM products WHERE stock < low_stock_alert AND low_stock_alert > 0 AND has_variants = false
  ORDER BY (low_stock_alert - stock) DESC LIMIT 10;

  RETURN QUERY
  SELECT
    (SELECT COUNT(*) FROM products WHERE has_variants = false
     UNION ALL SELECT COUNT(*) FROM product_variants pv
     JOIN products p ON p.id = pv.product_id WHERE p.has_variants = true AND pv.is_active = true
    )::BIGINT AS total_products,
    get_stock_value() AS total_stock_value,
    (SELECT COUNT(*) FROM products WHERE (stock > low_stock_alert OR low_stock_alert = 0) AND has_variants = false)::BIGINT AS healthy_count,
    (SELECT COUNT(*) FROM products WHERE stock > 0 AND stock <= low_stock_alert AND low_stock_alert > 0 AND has_variants = false)::BIGINT AS low_stock_count,
    (SELECT COUNT(*) FROM products WHERE stock = 0 AND has_variants = false)::BIGINT AS out_of_stock_count,
    (SELECT COUNT(*) FROM (
      SELECT pr.id FROM products pr
      LEFT JOIN _product_sales_90d ps ON ps.product_id = pr.id
      WHERE pr.stock > 0 AND pr.has_variants = false AND COALESCE(ps.sold_90d, 0) < 2
    ) sub)::BIGINT AS slow_moving_count,
    (SELECT COUNT(*) FROM products WHERE stock > 0 AND has_variants = false AND NOT EXISTS (
      SELECT 1 FROM sales, jsonb_array_elements(sales.items) AS item
      WHERE (item->>'product_id')::UUID = products.id AND sales.created_at >= NOW() - INTERVAL '180 days'
    ))::BIGINT AS dead_stock_count,
    (SELECT COUNT(*) FROM products WHERE stock > 100 AND low_stock_alert > 0 AND stock > low_stock_alert * 5 AND has_variants = false)::BIGINT AS overstock_count,
    v_slow AS slow_moving_items,
    v_out AS out_of_stock_items,
    v_reorder AS top_reorder_items;

  -- Clean up temp table
  DROP TABLE IF EXISTS _product_sales_90d;
END;
$$;

-- ============================================
-- GRANTS
-- ============================================

GRANT EXECUTE ON FUNCTION get_dashboard_summary() TO authenticated;
GRANT EXECUTE ON FUNCTION get_product_sales_stats() TO authenticated;

COMMIT;
