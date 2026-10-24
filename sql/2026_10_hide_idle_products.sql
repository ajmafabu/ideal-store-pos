-- =====================================================================
-- 2026_10_hide_idle_products.sql — hide products that sit empty
-- (owner, 23 Oct 2026: "auto hide after 30 days but in case want to add
-- there is option")
--
-- A product at 0 stock with no sale and no purchase for 30 days is
-- hidden: it drops off the stock lists, the out-of-stock and running-out
-- counts, Stock Health and the counting list. Nothing is deleted:
--   * it still scans and can be searched at billing;
--   * any stock change shows it again by itself (a purchase, Stock In,
--     a count, a sale, a return);
--   * the owner can show it again by hand (show_product); it then stays
--     visible for another 30 days before it can be hidden again.
--
-- hide_idle_products() is called by the admin's app once a day.
--
-- Idempotent; one transaction. Apply in Supabase -> SQL Editor:
--   back up, run verify_schema.sql, run this file, run verify_schema.sql.
-- =====================================================================
BEGIN;

-- 1. when it was hidden (NULL = shown) and when it was last shown by hand
ALTER TABLE products ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ;
ALTER TABLE products ADD COLUMN IF NOT EXISTS shown_at TIMESTAMPTZ;

-- 2. any stock change shows a hidden product again (runs after
--    guard_products_stock, which keeps the stock on plain edits)
CREATE OR REPLACE FUNCTION public.unhide_product_on_stock() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF OLD.hidden_at IS NOT NULL AND NEW.stock IS DISTINCT FROM OLD.stock THEN
    NEW.hidden_at := NULL;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.unhide_product_on_stock() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS unhide_products_on_stock ON products;
CREATE TRIGGER unhide_products_on_stock BEFORE UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION public.unhide_product_on_stock();

-- 3. hide the products that have sat at 0 for p_days; returns how many
CREATE OR REPLACE FUNCTION public.hide_idle_products(p_days integer DEFAULT 30)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_since timestamptz;
  v_count integer;
BEGIN
  PERFORM public.assert_admin();
  IF p_days IS NULL OR p_days < 7 THEN
    RAISE EXCEPTION 'Hide after at least 7 days (got %)', p_days;
  END IF;
  v_since := now() - make_interval(days => p_days);

  WITH sold AS (
    SELECT DISTINCT (x->>'product_id')::uuid AS product_id
    FROM sales s, jsonb_array_elements(s.items) x
    WHERE s.created_at >= v_since
      AND (x->>'product_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  ), bought AS (
    SELECT DISTINCT product_id FROM inventory_batches WHERE created_at >= v_since
  )
  UPDATE products p SET hidden_at = now()
  WHERE p.hidden_at IS NULL
    AND NOT coalesce(p.has_variants, false)
    AND p.stock = 0
    AND coalesce(p.created_at, '-infinity') < v_since
    AND coalesce(p.shown_at, '-infinity') < v_since
    AND NOT EXISTS (SELECT 1 FROM sold WHERE sold.product_id = p.id)
    AND NOT EXISTS (SELECT 1 FROM bought WHERE bought.product_id = p.id);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END $$;
REVOKE EXECUTE ON FUNCTION public.hide_idle_products(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.hide_idle_products(integer) TO authenticated;

-- 4. show a hidden product again by hand
CREATE OR REPLACE FUNCTION public.show_product(p_product uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_admin();
  UPDATE products SET hidden_at = NULL, shown_at = now() WHERE id = p_product;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product not found' USING ERRCODE = 'P0002'; END IF;
END $$;
REVOKE EXECUTE ON FUNCTION public.show_product(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.show_product(uuid) TO authenticated;

COMMIT;
