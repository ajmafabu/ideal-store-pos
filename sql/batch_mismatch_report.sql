-- =====================================================================
-- READ-ONLY report (23 Oct 2026): products whose cost batches (FIFO
-- layers) do not add up to their stock. Old drift from before Oct 2026;
-- profit and stock value use the batches. Nothing is changed.
-- Run in Supabase -> SQL Editor; the editor shows this one result.
-- "mismatched" (every row) is how many there are in all.
--   extra_in_batches > 0: batches hold more than the stock
--   extra_in_batches < 0: batches hold less than the stock
-- The fix (after the owner's OK) is sql/batch_mismatch_fix.sql.
-- =====================================================================
WITH b AS (
  SELECT product_id, sum(remaining) AS batches
  FROM inventory_batches WHERE remaining > 0 GROUP BY product_id
)
SELECT count(*) OVER () AS mismatched,
       p.name, p.stock, coalesce(b.batches, 0) AS batches,
       round(coalesce(b.batches, 0) - greatest(p.stock, 0), 3) AS extra_in_batches,
       round(p.purchase_price, 2) AS cost_price
FROM products p
LEFT JOIN b ON b.product_id = p.id
WHERE NOT coalesce(p.has_variants, false)
  AND abs(coalesce(b.batches, 0) - greatest(p.stock, 0)) > 0.001
ORDER BY abs(coalesce(b.batches, 0) - greatest(p.stock, 0)) DESC, p.name;
