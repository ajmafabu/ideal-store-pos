-- REPAIR (1 Nov 2026) — bill #3610. Back up first.
-- On 1 Nov 8:22 AM the ₹7,695 bill was saved over by ₹600 of items that
-- belonged to the SAME customer (owner). This puts #3610 back as ONE bill
-- with the items of both versions, for the amount the customer paid
-- (paid := …). Uses the app's own edit step: stock and cash follow.
-- Runs only while #3610 is still ₹600, so running it again does nothing.
WITH params AS (SELECT 3610::bigint AS bill, 7695::numeric AS big, 600::numeric AS small,
                       8295::numeric AS paid),
versions AS (
  SELECT a.created_at, a.new_data AS d FROM audit_log a, params
  WHERE a.table_name = 'sales' AND (a.new_data->>'invoice_no')::bigint = params.bill
), big AS (
  SELECT v.d FROM versions v, params
  WHERE round((v.d->>'final_amount')::numeric, 2) = params.big ORDER BY v.created_at DESC LIMIT 1
), small AS (
  SELECT v.d FROM versions v, params
  WHERE round((v.d->>'final_amount')::numeric, 2) = params.small ORDER BY v.created_at DESC LIMIT 1
), cur AS (
  SELECT s.id FROM sales s, params
  WHERE s.invoice_no = params.bill AND round(s.final_amount, 2) = params.small
), merged AS (
  SELECT (SELECT jsonb_agg(x - 'allocs' - 'cost_total' - 'base_qty' - 'returned_base' - 'oversold_qty')
          FROM (SELECT jsonb_array_elements(big.d->'items') AS x
                UNION ALL SELECT jsonb_array_elements(small.d->'items')) xs) AS items,
         coalesce((big.d->>'total_amount')::numeric, 0) + coalesce((small.d->>'total_amount')::numeric, 0) AS total,
         coalesce((big.d->>'extra_charges')::numeric, 0) AS extra,
         coalesce((big.d->>'round_off')::numeric, 0) AS round_off,
         big.d
  FROM big, small
), fixed AS (
  SELECT e.invoice_no, e.final_amount, jsonb_array_length(e.items) AS items
  FROM cur, merged m, params, LATERAL public.edit_sale_atomic(
    cur.id, m.items, m.total,
    greatest(m.total + m.extra + m.round_off - params.paid, 0),      -- discount
    params.paid,
    nullif(m.d->>'customer_id', '')::uuid,
    coalesce((m.d->>'is_credit')::boolean, false),
    CASE WHEN coalesce((m.d->>'is_credit')::boolean, false)
         THEN least(coalesce((m.d->>'amount_paid')::numeric, 0), params.paid) ELSE params.paid END,
    CASE WHEN coalesce((m.d->>'is_credit')::boolean, false)
         THEN params.paid - least(coalesce((m.d->>'amount_paid')::numeric, 0), params.paid) ELSE 0 END,
    m.d->>'payment_method',
    CASE WHEN coalesce((m.d->>'cash_amount')::numeric, 0) + coalesce((m.d->>'digital_amount')::numeric, 0) > 0
         THEN params.paid - coalesce((m.d->>'digital_amount')::numeric, 0) ELSE 0 END,
    coalesce((m.d->>'digital_amount')::numeric, 0),
    'Restored: on 1 Nov the rest of this customer''s items were saved over this bill',
    m.extra, m.round_off,
    (m.d->>'tax_exempt')::boolean,
    nullif(m.d->>'due_date', '')::date
  ) e
)
SELECT 'RESTORED' AS done, invoice_no, final_amount, items FROM fixed
UNION ALL
SELECT 'NOTHING TO DO (#3610 is not ₹600 now)', s.invoice_no, s.final_amount, jsonb_array_length(s.items)
FROM sales s, params WHERE s.invoice_no = params.bill AND NOT EXISTS (SELECT 1 FROM fixed);
