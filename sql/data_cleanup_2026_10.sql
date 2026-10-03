-- =====================================================================
-- data_cleanup_2026_10.sql — product master data clean-up (#33)
-- Run AFTER 2026_10_audit_fixes.sql. Part A only reads; part B creates
-- helper functions; part C (commented) applies changes after you review.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A. REPORT (read-only) — run each query and fix what it lists
-- ---------------------------------------------------------------------

-- A1. Products that cost money but sell for 0 (22 in the August export)
SELECT id, name, purchase_price, selling_price, stock
FROM products WHERE coalesce(selling_price, 0) <= 0 AND coalesce(purchase_price, 0) > 0
ORDER BY name;

-- A2. Products sold below cost
SELECT id, name, purchase_price, selling_price
FROM products WHERE selling_price > 0 AND selling_price < purchase_price ORDER BY name;

-- A3. Category spellings that differ only by case / plural / spaces
SELECT regexp_replace(lower(btrim(category)), 's$', '') AS group_key,
       array_agg(DISTINCT category) AS spellings, count(*) AS products
FROM products WHERE category IS NOT NULL AND btrim(category) <> ''
GROUP BY 1 HAVING count(DISTINCT category) > 1 ORDER BY 3 DESC;

-- A4. Products with no category (700 of 1,000 in the export)
SELECT count(*) AS uncategorised FROM products WHERE category IS NULL OR btrim(category) = '';

-- A5. Duplicate product names (case-insensitive) — merge with merge_products()
SELECT lower(btrim(name)) AS name_key, array_agg(id ORDER BY created_at) AS ids,
       array_agg(stock ORDER BY created_at) AS stocks, count(*) AS copies
FROM products GROUP BY 1 HAVING count(*) > 1 ORDER BY 1;

-- A6. GST readiness: every product needs an HSN code and a rate before GST
--     invoices/returns are meaningful (all 1,000 had rate 0 and no HSN)
SELECT count(*) FILTER (WHERE hsn_code IS NULL OR btrim(hsn_code) = '') AS missing_hsn,
       count(*) FILTER (WHERE coalesce(gst_rate, 0) = 0) AS zero_rate,
       count(*) AS products
FROM products;

-- A7. Tamil names that are just the English name copied (224 in the export)
SELECT count(*) AS tamil_equals_english FROM products WHERE tamil_name IS NOT NULL AND tamil_name = name;
SELECT id, name, tamil_name FROM products WHERE tamil_name IN ('test', '') ORDER BY name;

-- A8. Customers missing a phone number (all 32 in the export)
SELECT count(*) AS customers_without_phone FROM customers WHERE phone IS NULL OR btrim(phone) = '';

-- ---------------------------------------------------------------------
-- B. HELPERS (admin-only functions)
-- ---------------------------------------------------------------------

-- Canonical spelling per group = the spelling used by most products,
-- written in Title Case. p_apply = false only reports what would change.
CREATE OR REPLACE FUNCTION public.normalize_product_categories(p_apply boolean DEFAULT false)
RETURNS TABLE (old_category text, new_category text, products bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.assert_admin();
  CREATE TEMP TABLE IF NOT EXISTS _cat_map (old_category text, new_category text, products bigint) ON COMMIT DROP;
  TRUNCATE _cat_map;
  INSERT INTO _cat_map
  WITH g AS (
    SELECT category, regexp_replace(lower(btrim(category)), 's$', '') AS k, count(*) AS n
    FROM products WHERE category IS NOT NULL AND btrim(category) <> '' GROUP BY category
  ), best AS (
    SELECT DISTINCT ON (k) k, initcap(lower(btrim(category))) AS canon FROM g ORDER BY k, n DESC, category
  )
  SELECT g.category, best.canon, g.n FROM g JOIN best USING (k) WHERE g.category IS DISTINCT FROM best.canon;
  IF p_apply THEN
    UPDATE products p SET category = m.new_category FROM _cat_map m WHERE p.category = m.old_category;
  END IF;
  RETURN QUERY SELECT * FROM _cat_map ORDER BY 2, 1;
END $$;

-- Merge a duplicate product into the one you keep: stock, batches, sale
-- lines, returns, damaged records and variants move over; the duplicate
-- is deleted. Sale history and reports stay intact.
CREATE OR REPLACE FUNCTION public.merge_products(p_keep uuid, p_duplicate uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_admin();
  IF p_keep = p_duplicate THEN RAISE EXCEPTION 'Choose two different products'; END IF;
  PERFORM 1 FROM products WHERE id IN (p_keep, p_duplicate) FOR UPDATE;
  IF (SELECT count(*) FROM products WHERE id IN (p_keep, p_duplicate)) <> 2 THEN
    RAISE EXCEPTION 'Product not found';
  END IF;
  PERFORM set_config('app.doc_rpc', 'on', true);
  UPDATE products SET stock = stock + (SELECT stock FROM products WHERE id = p_duplicate) WHERE id = p_keep;
  UPDATE inventory_batches SET product_id = p_keep WHERE product_id = p_duplicate;
  UPDATE product_returns SET product_id = p_keep WHERE product_id = p_duplicate;
  UPDATE damaged_products SET product_id = p_keep WHERE product_id = p_duplicate;
  UPDATE stock_reconciliation SET product_id = p_keep WHERE product_id = p_duplicate;
  UPDATE product_variants v SET product_id = p_keep
   WHERE product_id = p_duplicate
     AND NOT EXISTS (SELECT 1 FROM product_variants x WHERE x.product_id = p_keep AND x.name = v.name);
  UPDATE sales s SET items = (
      SELECT jsonb_agg(CASE WHEN x->>'product_id' = p_duplicate::text
                            THEN jsonb_set(x, '{product_id}', to_jsonb(p_keep::text)) ELSE x END ORDER BY o)
      FROM jsonb_array_elements(s.items) WITH ORDINALITY AS e(x, o))
   WHERE s.items @> jsonb_build_array(jsonb_build_object('product_id', p_duplicate::text));
  UPDATE purchases p SET items = (
      SELECT jsonb_agg(CASE WHEN x->>'product_id' = p_duplicate::text
                            THEN jsonb_set(x, '{product_id}', to_jsonb(p_keep::text)) ELSE x END ORDER BY o)
      FROM jsonb_array_elements(p.items) WITH ORDINALITY AS e(x, o))
   WHERE p.items @> jsonb_build_array(jsonb_build_object('product_id', p_duplicate::text));
  UPDATE products SET stock = 0 WHERE id = p_duplicate;
  DELETE FROM products WHERE id = p_duplicate;
  PERFORM set_config('app.doc_rpc', 'off', true);
END $$;

REVOKE EXECUTE ON FUNCTION public.normalize_product_categories(boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.merge_products(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.normalize_product_categories(boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.merge_products(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- C. APPLY (uncomment one line at a time after checking part A)
-- ---------------------------------------------------------------------
-- SELECT * FROM normalize_product_categories(false);   -- preview
-- SELECT * FROM normalize_product_categories(true);    -- apply
-- SELECT merge_products('<id to keep>', '<duplicate id>');
-- UPDATE products SET tamil_name = NULL WHERE tamil_name = name OR tamil_name IN ('test', '');  -- re-translate later
-- UPDATE products SET category = 'Uncategorized' WHERE category IS NULL OR btrim(category) = '';
-- Zero selling prices, HSN codes and GST rates need real values from you:
-- fix them in the app (Inventory → edit product) or with a CSV import.
