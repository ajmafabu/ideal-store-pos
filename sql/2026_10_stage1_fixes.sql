-- =====================================================================
-- 2026_10_stage1_fixes.sql  —  product edits save again; receivables aging loads
--
-- 1. Product edits (price, name, barcode, Tamil name, GST, …) were refused
--    since 2026_10_audit_fixes.sql with
--      "permission denied for function app_bulk_mode"
--    The stock guard trigger on products runs as the app user and calls
--    app_bulk_mode(), which section 19 of that migration revoked from
--    everyone. Purchases still updated cost prices (they run as owner), so
--    only direct edits from the app failed. app_bulk_mode() only reads a
--    setting; logged-in users may call it. anon stays without it (verify
--    check 8) — RLS never lets anon update products.
--
-- 2. Reports → Receivables Aging failed with
--      "operator does not exist: interval <= integer"
--    On older databases sales.due_date is a timestamp, not a date, so
--    "today - due_date" was an interval. It is now cast to a date.
--
-- Apply in Supabase → SQL Editor: back up, run verify_schema.sql, run this
-- file, run verify_schema.sql again (checks 16 and 17 must say OK).
-- Safe to run more than once.
-- =====================================================================
BEGIN;

-- 1. the stock guard can run for the app user again
GRANT EXECUTE ON FUNCTION public.app_bulk_mode() TO authenticated;

-- 2. receivables aging works whether due_date is a date or a timestamp
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
           public.ist_today() - coalesce(s.due_date::date, public.ist_date(s.created_at) + 30) AS overdue
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

REVOKE EXECUTE ON FUNCTION public.get_receivables_aging() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_receivables_aging() TO authenticated;

COMMIT;
