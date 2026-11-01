-- =====================================================================
-- READ-ONLY report (1 Nov 2026): "some sales bills are missing".
-- Nothing is changed. Run in Supabase -> SQL Editor; the editor shows
-- this one result. Last 60 days, newest first. One row per finding:
--
--   DELETED      the bill was saved, then deleted (who, when, its amount).
--                The full bill is kept in audit_log and can be put back.
--   EDITED       the bill's amount or items were changed after saving.
--   NUMBER ONLY  a bill number was used up but no bill exists and none was
--                deleted: a save that failed half-way (e.g. the internet
--                dropped). No sale was recorded under that number.
--   SUMMARY      bills per day per person who made them, to spot a day or
--                a device with fewer bills than expected.
-- =====================================================================
WITH since AS (
  SELECT now() - interval '60 days' AS t
), people AS (
  SELECT id, coalesce(nullif(name, ''), 'unknown') AS name FROM profiles
), deleted AS (
  SELECT a.created_at AS happened, a.performed_by,
         a.old_data
  FROM audit_log a, since
  WHERE a.table_name = 'sales' AND a.action = 'DELETE' AND a.created_at >= since.t
), edited AS (
  SELECT a.created_at AS happened, a.performed_by, a.old_data, a.new_data
  FROM audit_log a, since
  WHERE a.table_name = 'sales' AND a.action = 'UPDATE' AND a.created_at >= since.t
    -- a real edit: amount, number of lines or quantities changed (not the
    -- bookkeeping a customer return or a stock step writes on the bill)
    AND ((a.old_data->>'final_amount')::numeric IS DISTINCT FROM (a.new_data->>'final_amount')::numeric
         OR jsonb_array_length(coalesce(a.old_data->'items', '[]')) <> jsonb_array_length(coalesce(a.new_data->'items', '[]'))
         OR (SELECT coalesce(sum(public.jnum(x, 'qty', 0)), 0) FROM jsonb_array_elements(coalesce(a.old_data->'items', '[]')) x)
            <> (SELECT coalesce(sum(public.jnum(x, 'qty', 0)), 0) FROM jsonb_array_elements(coalesce(a.new_data->'items', '[]')) x))
), numbers AS (
  SELECT min(invoice_no) AS lo, max(invoice_no) AS hi
  FROM sales, since WHERE invoice_no IS NOT NULL AND created_at >= since.t
), gaps AS (
  SELECT g AS bill_no
  FROM numbers, generate_series(numbers.lo, numbers.hi) g
  WHERE NOT EXISTS (SELECT 1 FROM sales s WHERE s.invoice_no = g)
    AND NOT EXISTS (SELECT 1 FROM deleted d WHERE (d.old_data->>'invoice_no')::bigint = g)
), findings AS (
  SELECT 1 AS ord, 'DELETED' AS kind,
         (d.old_data->>'invoice_no')::bigint AS bill_no,
         ((d.old_data->>'created_at')::timestamptz AT TIME ZONE 'Asia/Kolkata')::date AS bill_date,
         round((d.old_data->>'final_amount')::numeric, 2) AS amount,
         coalesce(nullif(d.old_data->>'customer_name', ''), '') AS customer,
         to_char(d.happened AT TIME ZONE 'Asia/Kolkata', 'DD Mon HH12:MI AM') AS happened_at,
         coalesce(p.name, 'system / SQL') AS by_whom,
         jsonb_array_length(coalesce(d.old_data->'items', '[]'::jsonb)) || ' item(s), '
           || coalesce(d.old_data->>'payment_method', '') AS detail
  FROM deleted d LEFT JOIN people p ON p.id = d.performed_by
  UNION ALL
  SELECT 2, 'EDITED', (e.new_data->>'invoice_no')::bigint,
         ((e.new_data->>'created_at')::timestamptz AT TIME ZONE 'Asia/Kolkata')::date,
         round((e.new_data->>'final_amount')::numeric, 2), coalesce(e.new_data->>'customer_name', ''),
         to_char(e.happened AT TIME ZONE 'Asia/Kolkata', 'DD Mon HH12:MI AM'), coalesce(p.name, 'system / SQL'),
         'was ' || round((e.old_data->>'final_amount')::numeric, 2) || ', '
           || jsonb_array_length(coalesce(e.old_data->'items', '[]'::jsonb)) || ' -> '
           || jsonb_array_length(coalesce(e.new_data->'items', '[]'::jsonb)) || ' item(s)'
  FROM edited e LEFT JOIN people p ON p.id = e.performed_by
  UNION ALL
  SELECT 3, 'NUMBER ONLY', g.bill_no, NULL, NULL, '', '', '', 'number used, no bill saved'
  FROM gaps g
  UNION ALL
  SELECT 4, 'SUMMARY', count(*), (s.created_at AT TIME ZONE 'Asia/Kolkata')::date, round(sum(s.final_amount), 2),
         '', '', coalesce(p.name, 'unknown'), 'bills that day by this person'
  FROM sales s CROSS JOIN since LEFT JOIN people p ON p.id = s.created_by
  WHERE s.created_at >= since.t
  GROUP BY (s.created_at AT TIME ZONE 'Asia/Kolkata')::date, p.name
)
SELECT kind, bill_no, bill_date, amount, customer, happened_at, by_whom, detail
FROM findings
ORDER BY ord, bill_date DESC NULLS LAST, bill_no DESC;
