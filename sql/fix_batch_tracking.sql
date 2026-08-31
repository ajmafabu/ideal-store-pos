-- ============================================
-- Fix: Batch tracking - add batch_number and expiry_date
-- ============================================

-- 1. Add missing columns to inventory_batches
ALTER TABLE inventory_batches ADD COLUMN IF NOT EXISTS batch_number TEXT;
ALTER TABLE inventory_batches ADD COLUMN IF NOT EXISTS expiry_date DATE;

-- 2. Update add_inventory_batch to accept batch_number and expiry_date
CREATE OR REPLACE FUNCTION add_inventory_batch(
  p_product_id UUID,
  p_purchase_id UUID,
  p_quantity INTEGER,
  p_purchase_price NUMERIC(10,2),
  p_batch_number TEXT DEFAULT NULL,
  p_expiry_date DATE DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
  INSERT INTO inventory_batches (product_id, purchase_id, quantity, remaining, purchase_price, batch_number, expiry_date, created_at)
  VALUES (p_product_id, p_purchase_id, p_quantity, p_quantity, p_purchase_price, p_batch_number, p_expiry_date, NOW());

  -- Update product's purchase price to the latest
  UPDATE products SET purchase_price = p_purchase_price WHERE id = p_product_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
