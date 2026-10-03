BEGIN;

-- ============================================
-- Accounts Receivable Aging RPC
-- Returns aging buckets: 0-30, 31-60, 61-90, 90+ days
-- ============================================

-- Drop existing function first (different return type)
DROP FUNCTION IF EXISTS get_receivables_aging();

CREATE OR REPLACE FUNCTION get_receivables_aging()
RETURNS TABLE(
  customer_id UUID,
  customer_name TEXT,
  phone TEXT,
  total_due NUMERIC,
  current_amount NUMERIC,
  days_1_30 NUMERIC,
  days_31_60 NUMERIC,
  days_61_90 NUMERIC,
  days_90_plus NUMERIC,
  oldest_sale_date TIMESTAMP,
  sale_count BIGINT
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  RETURN QUERY
  WITH customer_dues AS (
    SELECT
      s.customer_id,
      COALESCE(c.name, 'Unknown') AS customer_name,
      COALESCE(c.phone, '') AS phone,
      s.due_amount,
      s.created_at,
      s.id AS sale_id
    FROM sales s
    LEFT JOIN customers c ON c.id = s.customer_id
    WHERE s.is_credit = true
      AND s.due_amount > 0
  ),
  aging_calc AS (
    SELECT
      cd.customer_id,
      cd.customer_name,
      cd.phone,
      cd.due_amount,
      cd.created_at,
      EXTRACT(DAY FROM NOW() - cd.created_at)::INT AS days_old
    FROM customer_dues cd
  )
  SELECT
    ac.customer_id,
    ac.customer_name,
    ac.phone,
    SUM(ac.due_amount) AS total_due,
    SUM(CASE WHEN ac.days_old <= 0 THEN ac.due_amount ELSE 0 END) AS current_amount,
    SUM(CASE WHEN ac.days_old BETWEEN 1 AND 30 THEN ac.due_amount ELSE 0 END) AS days_1_30,
    SUM(CASE WHEN ac.days_old BETWEEN 31 AND 60 THEN ac.due_amount ELSE 0 END) AS days_31_60,
    SUM(CASE WHEN ac.days_old BETWEEN 61 AND 90 THEN ac.due_amount ELSE 0 END) AS days_61_90,
    SUM(CASE WHEN ac.days_old > 90 THEN ac.due_amount ELSE 0 END) AS days_90_plus,
    MIN(ac.created_at) AS oldest_sale_date,
    COUNT(ac.customer_id) AS sale_count
  FROM aging_calc ac
  GROUP BY ac.customer_id, ac.customer_name, ac.phone
  ORDER BY SUM(ac.due_amount) DESC;
END;
$$;

COMMIT;
