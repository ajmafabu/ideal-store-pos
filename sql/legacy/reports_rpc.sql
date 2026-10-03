BEGIN;

-- ============================================
-- Reports RPC - Server-side aggregation for reports_screen.dart
-- Replaces client-side loops with single RPC call
-- ============================================

CREATE OR REPLACE FUNCTION get_reports_summary(
  p_start TIMESTAMP,
  p_end TIMESTAMP
)
RETURNS TABLE(
  total_sales NUMERIC,
  total_purchases NUMERIC,
  total_expenses NUMERIC,
  net_profit NUMERIC,
  sales_by_day JSONB,
  top_products JSONB,
  sales_by_category JSONB,
  expenses_by_category JSONB,
  payment_breakdown JSONB,
  prev_month_sales NUMERIC,
  prev_month_expenses NUMERIC,
  prev_month_profit NUMERIC
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_prev_start TIMESTAMP;
  v_prev_end TIMESTAMP;
  v_total_sales NUMERIC := 0;
  v_total_purchases NUMERIC := 0;
  v_total_expenses NUMERIC := 0;
  v_sales_by_day JSONB := '[]'::JSONB;
  v_top_products JSONB := '[]'::JSONB;
  v_sales_by_category JSONB := '{}'::JSONB;
  v_expenses_by_category JSONB := '{}'::JSONB;
  v_payment_breakdown JSONB := '{}'::JSONB;
  v_prev_month_sales NUMERIC := 0;
  v_prev_month_expenses NUMERIC := 0;
BEGIN
  -- Calculate previous month range
  v_prev_start := p_start - INTERVAL '1 month';
  v_prev_end := p_start;

  -- Total sales
  SELECT COALESCE(SUM(final_amount), 0) INTO v_total_sales
  FROM sales
  WHERE created_at >= p_start AND created_at < p_end;

  -- Total purchases (from sale items - COGS)
  SELECT COALESCE(SUM((item->>'purchase_price')::NUMERIC * (item->>'qty')::INT), 0) INTO v_total_purchases
  FROM sales s, jsonb_array_elements(s.items) AS item
  WHERE s.created_at >= p_start AND s.created_at < p_end;

  -- Total expenses
  SELECT COALESCE(SUM(amount), 0) INTO v_total_expenses
  FROM expenses
  WHERE created_at >= p_start AND created_at < p_end;

  -- Sales by day
  SELECT COALESCE(
    jsonb_agg(jsonb_build_object('date', TO_CHAR(day, 'DD Mon'), 'total', daily_total)),
    '[]'::JSONB
  ) INTO v_sales_by_day
  FROM (
    SELECT
      created_at::date AS day,
      SUM(final_amount) AS daily_total
    FROM sales
    WHERE created_at >= p_start AND created_at < p_end
    GROUP BY created_at::date
    ORDER BY day
  ) sub;

  -- Top 5 products
  SELECT COALESCE(
    jsonb_agg(jsonb_build_object('name', product_name, 'total', product_total)),
    '[]'::JSONB
  ) INTO v_top_products
  FROM (
    SELECT
      item->>'name' AS product_name,
      SUM((item->>'total')::NUMERIC) AS product_total
    FROM sales s, jsonb_array_elements(s.items) AS item
    WHERE s.created_at >= p_start AND s.created_at < p_end
    GROUP BY item->>'name'
    ORDER BY product_total DESC
    LIMIT 5
  ) sub;

  -- Sales by category
  SELECT COALESCE(
    jsonb_object_agg(category, category_total),
    '{}'::JSONB
  ) INTO v_sales_by_category
  FROM (
    SELECT
      COALESCE(p.category, 'Other') AS category,
      SUM((item->>'total')::NUMERIC) AS category_total
    FROM sales s, jsonb_array_elements(s.items) AS item
    LEFT JOIN products p ON p.id = (item->>'product_id')::UUID
    WHERE s.created_at >= p_start AND s.created_at < p_end
    GROUP BY p.category
  ) sub;

  -- Expenses by category
  SELECT COALESCE(
    jsonb_object_agg(category, expense_total),
    '{}'::JSONB
  ) INTO v_expenses_by_category
  FROM (
    SELECT
      COALESCE(category, 'Other') AS category,
      SUM(amount) AS expense_total
    FROM expenses
    WHERE created_at >= p_start AND created_at < p_end
    GROUP BY category
  ) sub;

  -- Payment breakdown
  SELECT COALESCE(
    jsonb_object_agg(payment_method, method_total),
    '{}'::JSONB
  ) INTO v_payment_breakdown
  FROM (
    SELECT
      COALESCE(payment_method, 'cash') AS payment_method,
      SUM(final_amount) AS method_total
    FROM sales
    WHERE created_at >= p_start AND created_at < p_end
    GROUP BY payment_method
  ) sub;

  -- Previous month sales
  SELECT COALESCE(SUM(final_amount), 0) INTO v_prev_month_sales
  FROM sales
  WHERE created_at >= v_prev_start AND created_at < v_prev_end;

  -- Previous month expenses
  SELECT COALESCE(SUM(amount), 0) INTO v_prev_month_expenses
  FROM expenses
  WHERE created_at >= v_prev_start AND created_at < v_prev_end;

  -- Return results
  RETURN QUERY
  SELECT
    v_total_sales,
    v_total_purchases,
    v_total_expenses,
    v_total_sales - v_total_purchases - v_total_expenses,
    v_sales_by_day,
    v_top_products,
    v_sales_by_category,
    v_expenses_by_category,
    v_payment_breakdown,
    v_prev_month_sales,
    v_prev_month_expenses,
    v_prev_month_sales - v_prev_month_expenses - (
      SELECT COALESCE(SUM((item->>'purchase_price')::NUMERIC * (item->>'qty')::INT), 0)
      FROM sales s, jsonb_array_elements(s.items) AS item
      WHERE s.created_at >= v_prev_start AND s.created_at < v_prev_end
    );
END;
$$;

COMMIT;
