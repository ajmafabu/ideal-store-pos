-- STEP 0 of 2 — READ-ONLY (1 Nov 2026). Nothing is changed.
-- Bill #3603: what was typed as the reason for each edit, and the items of
-- the ₹13,874 bill (31 Oct) and of the ₹390 sale (1 Nov) side by side.
WITH params AS (SELECT 3603::bigint AS bill, 13874::numeric AS big, 390::numeric AS small),
versions AS (
  SELECT a.created_at, a.new_data AS d, round((a.new_data->>'final_amount')::numeric, 2) AS amount
  FROM audit_log a, params
  WHERE a.table_name = 'sales' AND (a.new_data->>'invoice_no')::bigint = params.bill
), big AS (
  SELECT v.* FROM versions v, params WHERE v.amount = params.big ORDER BY v.created_at DESC LIMIT 1
), small AS (
  SELECT v.* FROM versions v, params WHERE v.amount = params.small ORDER BY v.created_at DESC LIMIT 1
)
SELECT 'EDIT REASON' AS part,
       to_char(te.created_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon HH12:MI AM') AS line,
       coalesce(te.reason, '') AS detail,
       round((te.old_data->>'final_amount')::numeric, 2) || ' -> ' || round((te.new_data->>'final_amount')::numeric, 2) AS amount
FROM transaction_edits te JOIN sales s ON s.id = te.transaction_id, params
WHERE te.transaction_type = 'sale' AND s.invoice_no = params.bill
UNION ALL
SELECT 'BILL ' || big.amount, x->>'name', 'qty ' || (x->>'qty') || ' × ' || (x->>'price'), coalesce(x->>'total', '')
FROM big, jsonb_array_elements(big.d->'items') x
UNION ALL
SELECT 'SALE ' || small.amount, x->>'name', 'qty ' || (x->>'qty') || ' × ' || (x->>'price'), coalesce(x->>'total', '')
FROM small, jsonb_array_elements(small.d->'items') x
ORDER BY part, line;
