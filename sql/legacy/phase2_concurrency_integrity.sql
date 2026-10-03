-- ============================================
-- PHASE 2: CONCURRENCY & DATA INTEGRITY
-- Run this ONCE in Supabase SQL Editor
-- ============================================

BEGIN;

-- ============================================
-- CON-3: Add CHECK (remaining >= 0) on inventory_batches
-- ============================================
-- Prevents batch remaining from going negative under concurrent sales.
-- ============================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'inventory_batches_remaining_non_negative'
  ) THEN
    ALTER TABLE inventory_batches
      ADD CONSTRAINT inventory_batches_remaining_non_negative
      CHECK (remaining >= 0);
  END IF;
END $$;

-- ============================================
-- P1-2: Add FOR UPDATE to deduct_stock_fifo
-- ============================================
-- Without FOR UPDATE, two concurrent sales can read the same batch
-- remaining value, then both deduct, causing remaining to go negative.
-- FOR UPDATE locks each batch row before the UPDATE, serializing access.
-- ============================================

CREATE OR REPLACE FUNCTION deduct_stock_fifo(
  p_product_id UUID,
  p_qty INTEGER
)
RETURNS void AS $$
DECLARE
  remaining_to_deduct INTEGER := p_qty;
  batch RECORD;
BEGIN
  FOR batch IN
    SELECT id, remaining
    FROM inventory_batches
    WHERE product_id = p_product_id AND remaining > 0
    ORDER BY created_at ASC
    FOR UPDATE
  LOOP
    EXIT WHEN remaining_to_deduct <= 0;

    IF batch.remaining >= remaining_to_deduct THEN
      UPDATE inventory_batches SET remaining = remaining - remaining_to_deduct WHERE id = batch.id;
      remaining_to_deduct := 0;
    ELSE
      remaining_to_deduct := remaining_to_deduct - batch.remaining;
      UPDATE inventory_batches SET remaining = 0 WHERE id = batch.id;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- P1-2 + P2-9: Fix restore_stock_fifo
-- ============================================
-- CHANGES:
-- 1. Added FOR UPDATE to prevent concurrent restore races
-- 2. Changed batch matching: removed purchase_price filter
--    WHY: When sale stores purchase_price=150 (latest) but FIFO deducted
--    from batch with price=100 (oldest), restore can't find batch price=150.
--    Now matches any partially-depleted batch for the product, restoring
--    to the batch with the most room (newest-first).
-- 3. Overflow still creates orphan batch with the sale's stored price
--    for audit trail purposes.
-- ============================================

CREATE OR REPLACE FUNCTION restore_stock_fifo(
  p_product_id UUID,
  p_qty INTEGER,
  p_price NUMERIC(10,2)
)
RETURNS void AS $$
DECLARE
  remaining_to_restore INTEGER := p_qty;
  batch RECORD;
BEGIN
  FOR batch IN
    SELECT id, remaining, quantity
    FROM inventory_batches
    WHERE product_id = p_product_id AND remaining < quantity
    ORDER BY created_at DESC
    FOR UPDATE
  LOOP
    EXIT WHEN remaining_to_restore <= 0;

    DECLARE
      can_add INTEGER;
    BEGIN
      can_add := batch.quantity - batch.remaining;
      IF can_add >= remaining_to_restore THEN
        UPDATE inventory_batches SET remaining = remaining + remaining_to_restore WHERE id = batch.id;
        remaining_to_restore := 0;
      ELSE
        remaining_to_restore := remaining_to_restore - can_add;
        UPDATE inventory_batches SET remaining = quantity WHERE id = batch.id;
      END IF;
    END;
  END LOOP;

  -- Overflow: create orphan batch for unmatched remainder
  IF remaining_to_restore > 0 THEN
    INSERT INTO inventory_batches (product_id, quantity, remaining, purchase_price)
    VALUES (p_product_id, remaining_to_restore, remaining_to_restore, p_price);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- P1-9: Also fix deduct_stock_on_sale trigger
-- ============================================
-- The trigger deducts products.stock AND inventory_batches.remaining.
-- With FOR UPDATE in deduct_stock_fifo, this is now safe under concurrency.
-- No logic changes needed — just ensuring the trigger uses the updated function.
-- ============================================

-- (deduct_stock_on_sale already calls deduct_stock_fifo which now has FOR UPDATE)

COMMIT;
