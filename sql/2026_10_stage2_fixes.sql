-- =====================================================================
-- 2026_10_stage2_fixes.sql  —  a wrong damaged entry can be deleted
--
-- QA test 8 Oct 2026, finding 86: a damaged-stock entry could not be
-- deleted or corrected. A wrong entry stayed forever, kept its loss in the
-- profit figures, and the stock it used blocked deleting or editing the
-- purchase it came from.
--
-- delete_damaged_atomic(p_id) removes the entry and puts its quantity back
-- in stock and in the purchase batches it most likely came from (the
-- newest partly used ones, same as other undo steps without a record of
-- the exact batches). The loss leaves the profit figures with it. To
-- correct an entry: delete it and enter it again.
--
-- Apply in Supabase → SQL Editor: back up, run verify_schema.sql, run this
-- file, run verify_schema.sql again (check 18 must say OK).
-- Safe to run more than once.
-- =====================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.delete_damaged_atomic(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE d record;
BEGIN
  PERFORM public.assert_admin();
  SELECT * INTO d FROM damaged_products WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;          -- already gone: nothing to undo

  IF d.product_id IS NOT NULL AND coalesce(d.quantity, 0) > 0 THEN
    PERFORM 1 FROM products WHERE id = d.product_id FOR UPDATE;
    IF FOUND THEN
      UPDATE products SET stock = stock + d.quantity WHERE id = d.product_id;
      PERFORM public.restore_stock_fifo(d.product_id, d.quantity, d.unit_price);
    END IF;
  END IF;

  DELETE FROM damaged_products WHERE id = p_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.delete_damaged_atomic(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_damaged_atomic(uuid) TO authenticated;

COMMIT;
