-- =====================================================================
-- READ-ONLY (1 Nov 2026): where is bill #3603? Nothing is changed.
-- Run in Supabase -> SQL Editor. Shows bills #3600-#3606 as they are now,
-- and every saved / changed / deleted record of them in audit_log.
-- =====================================================================
WITH people AS (
  SELECT id, coalesce(nullif(name, ''), 'unknown') AS name FROM profiles
)
SELECT 'NOW IN SALES' AS what,
       s.invoice_no AS bill_no,
       to_char(s.created_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon YYYY HH12:MI AM') AS bill_time,
       round(s.final_amount, 2) AS amount,
       s.payment_method AS paid_by,
       coalesce(c.name, '') AS customer,
       jsonb_array_length(coalesce(s.items, '[]')) AS items,
       coalesce(p.name, 'unknown') AS by_whom,
       '' AS note
FROM sales s
LEFT JOIN customers c ON c.id = s.customer_id
LEFT JOIN people p ON p.id = s.created_by
WHERE s.invoice_no BETWEEN 3600 AND 3606
UNION ALL
SELECT 'HISTORY: ' || a.action,
       coalesce((a.new_data->>'invoice_no')::bigint, (a.old_data->>'invoice_no')::bigint),
       to_char(a.created_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon YYYY HH12:MI AM'),
       round(coalesce((a.new_data->>'final_amount')::numeric, (a.old_data->>'final_amount')::numeric), 2),
       coalesce(a.new_data->>'payment_method', a.old_data->>'payment_method'),
       '',
       jsonb_array_length(coalesce(a.new_data->'items', a.old_data->'items', '[]')),
       coalesce(p.name, 'system / SQL'),
       CASE a.action WHEN 'DELETE' THEN 'deleted at this time; the full bill is kept here'
                     WHEN 'INSERT' THEN 'saved' ELSE 'changed' END
FROM audit_log a
LEFT JOIN people p ON p.id = a.performed_by
WHERE a.table_name = 'sales'
  AND coalesce((a.new_data->>'invoice_no')::bigint, (a.old_data->>'invoice_no')::bigint) BETWEEN 3600 AND 3606
ORDER BY bill_no, what DESC;
