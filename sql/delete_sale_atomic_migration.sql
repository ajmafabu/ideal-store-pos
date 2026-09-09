-- ============================================
-- DELETE SALE ATOMIC MIGRATION
-- Creates delete_sale_atomic() function that
-- atomically restores stock + batches + deletes sale.
--
-- FIFO RESTORATION LIMITATION:
-- This function does NOT track which specific historical
-- batches were consumed by a sale. Sales store purchase_price
-- but not batch IDs. Restoration matches on:
--   1. product_id
--   2. purchase_price (exact match)
--   3. batches where remaining < quantity (partially depleted)
--   4. newest-first order
-- Unmatched remainder creates a new orphan batch
-- (no purchase_id) for manual reconciliation.
--
-- Run this ONCE in Supabase SQL Editor
-- ============================================

CREATE OR REPLACE FUNCTION delete_sale_atomic(
  p_sale_id UUID
)
RETURNS TABLE (
  items JSONB,
  final_amount NUMERIC(10,2),
  payment_method TEXT,
  is_credit BOOLEAN,
  cash_amount NUMERIC(10,2),
  digital_amount NUMERIC(10,2),
  customer_id UUID,
  due_amount NUMERIC(10,2)
) AS $$
DECLARE
  sale_record RECORD;
  item JSONB;
  v_product_id UUID;
  v_qty INTEGER;
  v_price NUMERIC(10,2);
  v_batch RECORD;
  v_remaining_to_restore INTEGER;
  v_can_add INTEGER;
BEGIN
  -- 1. Lock the sale row and read its data
  SELECT s.*
  INTO sale_record
  FROM sales s
  WHERE s.id = p_sale_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sale % not found — already deleted or never existed', p_sale_id;
  END IF;

  IF sale_record.items IS NULL OR jsonb_array_length(sale_record.items) = 0 THEN
    RAISE EXCEPTION 'Sale % has no items', p_sale_id;
  END IF;

  -- 2. For each item: restore products.stock AND inventory_batches.remaining
  FOR item IN SELECT * FROM jsonb_array_elements(sale_record.items)
  LOOP
    -- Validate item structure
    v_product_id := (item->>'product_id')::UUID;
    IF v_product_id IS NULL THEN
      RAISE EXCEPTION 'Sale %: item missing product_id', p_sale_id;
    END IF;

    v_qty := (item->>'qty')::INTEGER;
    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Sale %: item % has invalid qty % (must be positive integer)',
        p_sale_id, v_product_id, v_qty;
    END IF;

    v_price := (item->>'purchase_price')::NUMERIC(10,2);
    IF v_price IS NULL OR v_price <= 0 THEN
      RAISE EXCEPTION 'Cannot delete sale %: item % has invalid purchase_price % (must be positive)',
        p_sale_id, v_product_id, v_price;
    END IF;

    -- 2a. Restore products.stock (implicit row lock via UPDATE)
    UPDATE products
    SET stock = stock + v_qty
    WHERE id = v_product_id;

    IF NOT FOUND THEN
      RAISE WARNING 'Product % not found during sale deletion — product may have been deleted via CASCADE', v_product_id;
    END IF;

    -- 2b. Restore inventory_batches.remaining (FIFO, newest first)
    -- NOTE: This is price-based restoration, not batch-lineage restoration.
    -- We match batches by product_id + purchase_price + partially-depleted status.
    -- We restore newest-first (reverse of deduct order) to fill the most recent
    -- batches first. Overflow creates a new orphan batch for manual reconciliation.
    v_remaining_to_restore := v_qty;

    FOR v_batch IN
      SELECT id, remaining, quantity
      FROM inventory_batches
      WHERE product_id = v_product_id
        AND purchase_price = v_price
        AND remaining < quantity
      ORDER BY created_at DESC
      FOR UPDATE
    LOOP
      EXIT WHEN v_remaining_to_restore <= 0;

      v_can_add := v_batch.quantity - v_batch.remaining;
      IF v_can_add >= v_remaining_to_restore THEN
        UPDATE inventory_batches
        SET remaining = remaining + v_remaining_to_restore
        WHERE id = v_batch.id;
        v_remaining_to_restore := 0;
      ELSE
        UPDATE inventory_batches
        SET remaining = quantity
        WHERE id = v_batch.id;
        v_remaining_to_restore := v_remaining_to_restore - v_can_add;
      END IF;
    END LOOP;

    -- Overflow: create new batch for unmatched remainder
    -- purchase_id is NULL (orphan batch) — valid per schema (FK ON DELETE CASCADE allows NULL)
    IF v_remaining_to_restore > 0 THEN
      INSERT INTO inventory_batches (product_id, quantity, remaining, purchase_price)
      VALUES (v_product_id, v_remaining_to_restore, v_remaining_to_restore, v_price);
    END IF;
  END LOOP;

  -- 3. Delete the sale (within same transaction)
  -- Note: The on_sale_credit_update trigger fires on DELETE and automatically
  -- recalculates customers.total_credit from remaining sales. No Dart-side
  -- credit reversal is needed.
  DELETE FROM sales WHERE id = p_sale_id;

  -- 4. Return the sale data Dart needs for account reversal
  -- (credit reversal is handled by the DB trigger, not here)
  RETURN QUERY SELECT
    sale_record.items,
    sale_record.final_amount,
    sale_record.payment_method,
    sale_record.is_credit,
    sale_record.cash_amount,
    sale_record.digital_amount,
    sale_record.customer_id,
    sale_record.due_amount;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = public;
