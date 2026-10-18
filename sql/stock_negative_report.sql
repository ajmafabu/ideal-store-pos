-- =====================================================================
-- stock_negative_report.sql — READ ONLY. Changes nothing.
--
-- Before 2026_10_stock_negative.sql, a sale of more than the stock set the
-- stock to 0 and only noted the shortfall on the bill line (oversold_qty).
-- When the purchase was entered later, its full quantity was added, so
-- these products may show MORE stock than is really on the shelf, by up to
-- the units in "oversold_units".
--
-- Only bills made BEFORE 2026_10_stock_negative.sql was applied matter:
-- after it, a sale below zero is normal (the stock shows minus and the
-- purchase makes it up), so ignore rows whose bills are all newer.
--
-- One row per product. "counted_after" = a physical count was done after
-- the last such bill (that count already corrected the stock). For the
-- others, count the shelf and enter it with Physical Count.
-- Run in Supabase -> SQL Editor; the editor shows this one result.
-- =====================================================================
WITH over AS (
  SELECT (x->>'product_id')::uuid AS product_id,
         public.jnum(x, 'oversold_qty', 0) AS units,
         s.created_at, s.invoice_no
  FROM sales s, jsonb_array_elements(s.items) x
  WHERE x ? 'oversold_qty'
    AND (x->>'product_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
), per_product AS (
  SELECT product_id, sum(units) AS oversold_units, count(*) AS bills,
         min(created_at) AS first_bill, max(created_at) AS last_bill,
         string_agg(coalesce(invoice_no::text, '?'), ', ' ORDER BY created_at) AS bill_numbers
  FROM over GROUP BY product_id
), last_count AS (
  SELECT product_id, max(created_at) AS counted_at FROM stock_reconciliation GROUP BY product_id
)
SELECT p.name,
       p.stock AS stock_now,
       round(o.oversold_units, 3) AS oversold_units,
       o.bills,
       to_char(o.first_bill AT TIME ZONE 'Asia/Kolkata', 'DD Mon YYYY') AS first_bill,
       to_char(o.last_bill AT TIME ZONE 'Asia/Kolkata', 'DD Mon YYYY') AS last_bill,
       to_char(c.counted_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon YYYY') AS last_count,
       CASE WHEN c.counted_at > o.last_bill THEN 'counted after — probably correct'
            ELSE 'CHECK: stock may be too high by up to ' || round(o.oversold_units, 3) END AS status,
       o.bill_numbers
FROM per_product o
JOIN products p ON p.id = o.product_id
LEFT JOIN last_count c ON c.product_id = o.product_id
ORDER BY (c.counted_at > o.last_bill) NULLS FIRST, o.oversold_units DESC;
