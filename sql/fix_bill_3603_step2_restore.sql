-- STEP 2 of 2 (1 Nov 2026) — puts bill #3603 back to the ₹13,874 bill
-- (31 Oct, 10:20 PM version) from the copy kept in audit_log. Back up first.
-- Uses the app's own edit step (edit_sale_atomic): the stock of the ₹390
-- version is given back, the stock of the 30 items is taken, and the cash
-- book follows. Runs only while #3603 is still ₹390, so running it again
-- does nothing. Shows #3603 after the repair.
WITH params AS (SELECT 3603::bigint AS bill, 13874::numeric AS big, 390::numeric AS small),
big AS (
  SELECT a.new_data AS d
  FROM audit_log a, params
  WHERE a.table_name = 'sales' AND (a.new_data->>'invoice_no')::bigint = params.bill
    AND round((a.new_data->>'final_amount')::numeric, 2) = params.big
  ORDER BY a.created_at DESC LIMIT 1
), cur AS (
  SELECT s.id FROM sales s, params
  WHERE s.invoice_no = params.bill AND round(s.final_amount, 2) = params.small
), fixed AS (
  SELECT e.invoice_no, e.final_amount, jsonb_array_length(e.items) AS items
  FROM cur, big, LATERAL public.edit_sale_atomic(
    cur.id,
    (SELECT jsonb_agg(x - 'allocs' - 'cost_total' - 'base_qty' - 'returned_base' - 'oversold_qty')
     FROM jsonb_array_elements(big.d->'items') x),
    (big.d->>'total_amount')::numeric,
    coalesce((big.d->>'discount')::numeric, 0),
    (big.d->>'final_amount')::numeric,
    nullif(big.d->>'customer_id', '')::uuid,
    coalesce((big.d->>'is_credit')::boolean, false),
    coalesce((big.d->>'amount_paid')::numeric, 0),
    coalesce((big.d->>'due_amount')::numeric, 0),
    big.d->>'payment_method',
    coalesce((big.d->>'cash_amount')::numeric, 0),
    coalesce((big.d->>'digital_amount')::numeric, 0),
    'Restored: on 1 Nov a new sale was saved over this bill by mistake',
    (big.d->>'extra_charges')::numeric,
    (big.d->>'round_off')::numeric,
    (big.d->>'tax_exempt')::boolean,
    nullif(big.d->>'due_date', '')::date
  ) e
)
SELECT 'RESTORED' AS done, invoice_no, final_amount, items FROM fixed
UNION ALL
SELECT 'NOTHING TO DO (#3603 is not ₹390 now)', s.invoice_no, s.final_amount, jsonb_array_length(s.items)
FROM sales s, params WHERE s.invoice_no = params.bill AND NOT EXISTS (SELECT 1 FROM fixed);
