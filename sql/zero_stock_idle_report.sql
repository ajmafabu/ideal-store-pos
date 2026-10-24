-- =====================================================================
-- READ-ONLY report (23 Oct 2026): products at 0 stock with no sale and no
-- purchase in the last 30 days. These are the ones the owner wants off
-- the stock lists. Nothing is changed.
-- Run in Supabase -> SQL Editor; the editor shows this one result.
-- "idle_products" (every row) is how many there are in all.
-- =====================================================================
WITH last_sale AS (
  SELECT (x->>'product_id')::uuid AS product_id, max(s.created_at) AS sold_at
  FROM sales s, jsonb_array_elements(s.items) x
  WHERE (x->>'product_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  GROUP BY 1
), last_buy AS (
  SELECT product_id, max(created_at) AS bought_at FROM inventory_batches GROUP BY 1
), idle AS (
  SELECT p.name, p.barcode, p.category, p.selling_price,
         ls.sold_at::date AS last_sold,
         lb.bought_at::date AS last_bought,
         (current_date - greatest(ls.sold_at, lb.bought_at, p.created_at)::date) AS idle_days
  FROM products p
  LEFT JOIN last_sale ls ON ls.product_id = p.id
  LEFT JOIN last_buy lb ON lb.product_id = p.id
  WHERE NOT coalesce(p.has_variants, false)
    AND p.stock = 0
    AND coalesce(ls.sold_at, '-infinity') < now() - interval '30 days'
    AND coalesce(lb.bought_at, '-infinity') < now() - interval '30 days'
    AND p.created_at < now() - interval '30 days'
)
SELECT count(*) OVER () AS idle_products, *
FROM idle
ORDER BY idle_days DESC, name;
