-- STEP 1 of 2 (1 Nov 2026) — run ONLY if the ₹390 sale (3 items, 1 Nov
-- 6:03 PM) was a real, separate customer. Back up first.
-- Saves that ₹390 sale as its own NEW bill, at its own time, from the copy
-- kept in audit_log. Stock and cash are handled by the database as for any
-- bill. Running it again does nothing (fixed id).
-- Shows the new bill's number.
WITH params AS (SELECT 3603::bigint AS bill, 390::numeric AS small,
                       md5('ideal-bill-3603-split-small')::uuid AS new_id),
small AS (
  SELECT a.created_at AS at, a.new_data AS d
  FROM audit_log a, params
  WHERE a.table_name = 'sales' AND (a.new_data->>'invoice_no')::bigint = params.bill
    AND round((a.new_data->>'final_amount')::numeric, 2) = params.small
  ORDER BY a.created_at DESC LIMIT 1
), ins AS (
  INSERT INTO sales (id, items, total_amount, discount, final_amount, payment_method, cash_amount,
                     digital_amount, customer_id, is_credit, amount_paid, extra_charges, round_off,
                     created_by, created_at)
  SELECT params.new_id,
         (SELECT jsonb_agg(x - 'allocs' - 'cost_total' - 'base_qty' - 'returned_base' - 'oversold_qty')
          FROM jsonb_array_elements(small.d->'items') x),
         (small.d->>'total_amount')::numeric, coalesce((small.d->>'discount')::numeric, 0),
         (small.d->>'final_amount')::numeric, small.d->>'payment_method',
         coalesce((small.d->>'cash_amount')::numeric, 0), coalesce((small.d->>'digital_amount')::numeric, 0),
         nullif(small.d->>'customer_id', '')::uuid, coalesce((small.d->>'is_credit')::boolean, false),
         coalesce((small.d->>'amount_paid')::numeric, 0), coalesce((small.d->>'extra_charges')::numeric, 0),
         coalesce((small.d->>'round_off')::numeric, 0),
         nullif(small.d->>'created_by', '')::uuid, small.at
  FROM small, params
  WHERE NOT EXISTS (SELECT 1 FROM sales WHERE id = params.new_id)
  RETURNING invoice_no, final_amount
)
SELECT 'NEW BILL' AS done, invoice_no, final_amount FROM ins
UNION ALL
SELECT 'ALREADY DONE', s.invoice_no, s.final_amount FROM sales s, params
WHERE s.id = params.new_id AND NOT EXISTS (SELECT 1 FROM ins);
