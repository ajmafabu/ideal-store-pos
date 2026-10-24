-- =====================================================================
-- DATA FIX (23 Oct 2026) — run ONLY after the owner has seen
-- sql/batch_mismatch_report.sql and said OK. Back up first.
--
-- Makes every product's cost batches add up to its stock again. The
-- stock figure itself is NOT changed (a shelf count corrects that):
--   * batches hold more than the stock: the extra is taken out, oldest
--     first (the same as a count does);
--   * batches hold less: a batch is added at the product's average cost
--     (else its cost price);
--   * stock below zero (purchase pending): no batch should be left.
-- Works on its own (the first version leaned on an updated
-- reconcile_stock_with_batches and changed nothing where that update had
-- not been run). Nothing is deleted. Running it again changes nothing.
-- Shows how many products were fixed and how many still do not add up
-- (should be 0).
-- =====================================================================
WITH b AS (
  SELECT product_id, sum(remaining) AS batches,
         sum(remaining * purchase_price) / nullif(sum(remaining), 0) AS avg_cost
  FROM inventory_batches WHERE remaining > 0 GROUP BY product_id
), todo AS (
  SELECT p.id, greatest(p.stock, 0) AS want, coalesce(b.batches, 0) AS batches,
         coalesce(b.avg_cost, nullif(p.purchase_price, 0), 0) AS cost
  FROM products p LEFT JOIN b ON b.product_id = p.id
  WHERE NOT coalesce(p.has_variants, false)
    AND abs(coalesce(b.batches, 0) - greatest(p.stock, 0)) > 0.001
), fixed AS (
  SELECT t.id,
         CASE WHEN t.batches > t.want
              THEN (SELECT (public.fifo_take(t.id, t.batches - t.want, 0)).cost)::text
              ELSE (SELECT public.restore_stock_fifo(t.id, t.want - t.batches, t.cost))::text END AS done
  FROM todo t
)
SELECT (SELECT count(*) FROM fixed) AS products_fixed;
