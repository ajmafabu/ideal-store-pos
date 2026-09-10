-- ============================================================
-- Fix #5: Stock Reconciliation Batch Sync
-- Atomic function that updates both products.stock AND inventory_batches.remaining
-- ============================================================

BEGIN;

-- Reconcile stock: update products.stock AND sync inventory_batches.remaining
CREATE OR REPLACE FUNCTION reconcile_stock_with_batches(
  p_product_id UUID,
  p_physical_qty INTEGER
)
RETURNS void AS $$
DECLARE
  v_current_stock INTEGER;
  v_diff INTEGER;
  v_product RECORD;
BEGIN
  -- Get current stock
  SELECT stock INTO v_current_stock FROM products WHERE id = p_product_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product not found: %', p_product_id;
  END IF;

  -- No change needed
  IF v_current_stock = p_physical_qty THEN
    RETURN;
  END IF;

  v_diff := p_physical_qty - v_current_stock;

  -- Update products.stock
  UPDATE products SET stock = p_physical_qty WHERE id = p_product_id;

  IF v_diff > 0 THEN
    -- Stock INCREASED: fill partially-depleted batches, then create orphan for remainder
    DECLARE
      remaining_to_add INTEGER := v_diff;
      batch RECORD;
    BEGIN
      -- Fill existing partially-depleted batches (newest first, same as restore_stock_fifo)
      FOR batch IN
        SELECT id, remaining, quantity, purchase_price
        FROM inventory_batches
        WHERE product_id = p_product_id AND remaining < quantity
        ORDER BY created_at DESC
      LOOP
        EXIT WHEN remaining_to_add <= 0;
        DECLARE
          can_add INTEGER;
        BEGIN
          can_add := batch.quantity - batch.remaining;
          IF can_add >= remaining_to_add THEN
            UPDATE inventory_batches SET remaining = remaining + remaining_to_add WHERE id = batch.id;
            remaining_to_add := 0;
          ELSE
            remaining_to_add := remaining_to_add - can_add;
            UPDATE inventory_batches SET remaining = quantity WHERE id = batch.id;
          END IF;
        END;
      END LOOP;

      -- Overflow: create orphan batch at average purchase price
      IF remaining_to_add > 0 THEN
        DECLARE
          v_avg_price NUMERIC;
        BEGIN
          SELECT COALESCE(AVG(purchase_price), 0) INTO v_avg_price
          FROM inventory_batches WHERE product_id = p_product_id;

          INSERT INTO inventory_batches (product_id, quantity, remaining, purchase_price)
          VALUES (p_product_id, remaining_to_add, remaining_to_add, v_avg_price);
        END;
      END IF;
    END;

  ELSE
    -- Stock DECREASED: deduct from batches FIFO (oldest first)
    DECLARE
      remaining_to_deduct INTEGER := ABS(v_diff);
      batch RECORD;
    BEGIN
      FOR batch IN
        SELECT id, remaining
        FROM inventory_batches
        WHERE product_id = p_product_id AND remaining > 0
        ORDER BY created_at ASC
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
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION reconcile_stock_with_batches(UUID, INTEGER) TO authenticated;

COMMIT;
