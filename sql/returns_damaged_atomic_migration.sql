-- ============================================
-- RETURNS & DAMAGED ATOMIC MIGRATION
-- Creates create_return_atomic() and
-- create_damaged_atomic() functions that
-- atomically handle inventory + batch changes
-- in a single PostgreSQL transaction.
--
-- Run this ONCE in Supabase SQL Editor
-- ============================================

-- 1. create_return_atomic()
-- ============================================

CREATE OR REPLACE FUNCTION create_return_atomic(
  p_id UUID,
  p_product_id UUID,
  p_sale_id UUID,
  p_product_name TEXT,
  p_quantity INTEGER,
  p_unit_price NUMERIC(10,2),
  p_refund_amount NUMERIC(10,2),
  p_reason TEXT,
  p_created_by UUID
)
RETURNS TABLE (
  id UUID,
  product_id UUID,
  sale_id UUID,
  product_name TEXT,
  quantity INTEGER,
  refund_amount NUMERIC(10,2),
  reason TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ
) AS $$
DECLARE
  v_sale_items JSONB;
  v_original_qty INTEGER;
  v_returned_qty INTEGER;
  v_returnable INTEGER;
  v_match_count INTEGER;
  v_distinct_prices INTEGER;
  v_price NUMERIC(10,2);
BEGIN
  -- 0. Idempotency: if this return already exists, return it immediately
  RETURN QUERY
  SELECT pr.id, pr.product_id, pr.sale_id, pr.product_name, pr.quantity,
         pr.refund_amount, pr.reason, pr.created_by, pr.created_at
  FROM product_returns pr
  WHERE pr.id = p_id;

  IF FOUND THEN
    RETURN;
  END IF;

  -- 1. Lock original sale and read items
  SELECT s.items INTO v_sale_items
  FROM sales s
  WHERE s.id = p_sale_id
  FOR UPDATE;

  IF v_sale_items IS NULL THEN
    RAISE EXCEPTION 'Sale % not found', p_sale_id;
  END IF;

  -- 2. Validate quantity
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Return quantity must be positive, got %', p_quantity;
  END IF;

  -- 3. Check product exists in sale
  v_match_count := (
    SELECT COUNT(*) FROM jsonb_array_elements(v_sale_items) AS item
    WHERE (item->>'product_id')::UUID = p_product_id
  );

  IF v_match_count = 0 THEN
    RAISE EXCEPTION 'Product % not found in sale %', p_product_id, p_sale_id;
  END IF;

  -- 4. Original sold quantity for this product in this sale
  v_original_qty := (
    SELECT COALESCE(SUM((item->>'qty')::INTEGER), 0)
    FROM jsonb_array_elements(v_sale_items) AS item
    WHERE (item->>'product_id')::UUID = p_product_id
  );

  IF v_original_qty <= 0 THEN
    RAISE EXCEPTION 'Original sold quantity for product % in sale % is % (must be positive)',
      p_product_id, p_sale_id, v_original_qty;
  END IF;

  -- 5. Previously returned quantity for this product in this sale
  v_returned_qty := (
    SELECT COALESCE(SUM(pr.quantity), 0)
    FROM product_returns pr
    WHERE pr.original_sale_id = p_sale_id
      AND pr.product_id = p_product_id
  );

  -- 6. Remaining returnable
  v_returnable := v_original_qty - v_returned_qty;

  IF p_quantity > v_returnable THEN
    RAISE EXCEPTION 'Cannot return % units of product %. Original sold: %, already returned: %, remaining returnable: %',
      p_quantity, p_product_id, v_original_qty, v_returned_qty, v_returnable;
  END IF;

  -- 7. Determine purchase_price from sale items
  IF v_match_count = 1 THEN
    -- Single match: use its purchase_price
    v_price := (
      SELECT (item->>'purchase_price')::NUMERIC(10,2)
      FROM jsonb_array_elements(v_sale_items) AS item
      WHERE (item->>'product_id')::UUID = p_product_id
    );
  ELSE
    -- Multiple matches: check if all same price
    v_distinct_prices := (
      SELECT COUNT(DISTINCT (item->>'purchase_price')::NUMERIC(10,2))
      FROM jsonb_array_elements(v_sale_items) AS item
      WHERE (item->>'product_id')::UUID = p_product_id
    );

    IF v_distinct_prices = 1 THEN
      v_price := (
        SELECT (item->>'purchase_price')::NUMERIC(10,2)
        FROM jsonb_array_elements(v_sale_items) AS item
        WHERE (item->>'product_id')::UUID = p_product_id
        LIMIT 1
      );
    ELSE
      -- Different prices: weighted average
      v_price := (
        SELECT SUM((item->>'purchase_price')::NUMERIC(10,2) * (item->>'qty')::INTEGER)
               / SUM((item->>'qty')::INTEGER)
        FROM jsonb_array_elements(v_sale_items) AS item
        WHERE (item->>'product_id')::UUID = p_product_id
      );
    END IF;
  END IF;

  IF v_price IS NULL OR v_price <= 0 THEN
    RAISE EXCEPTION 'Invalid purchase_price % for product % in sale %', v_price, p_product_id, p_sale_id;
  END IF;

  -- 8. Insert return record with client-supplied UUID
  INSERT INTO product_returns (id, product_id, original_sale_id, product_name, quantity, refund_amount, reason, created_by)
  VALUES (p_id, p_product_id, p_sale_id, p_product_name, p_quantity, p_refund_amount, p_reason, p_created_by);

  -- 9. Restore products.stock
  UPDATE products
  SET stock = stock + p_quantity
  WHERE id = p_product_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product % not found — cannot restore stock', p_product_id;
  END IF;

  -- 10. Restore inventory_batches (existing FIFO function, not modified)
  PERFORM restore_stock_fifo(p_product_id, p_quantity, v_price);

  -- 11. Return created record
  RETURN QUERY
  SELECT pr.id, pr.product_id, pr.sale_id, pr.product_name, pr.quantity,
         pr.refund_amount, pr.reason, pr.created_by, pr.created_at
  FROM product_returns pr
  WHERE pr.id = p_id;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = public;

-- 2. create_damaged_atomic()
-- ============================================

CREATE OR REPLACE FUNCTION create_damaged_atomic(
  p_id UUID,
  p_product_id UUID,
  p_product_name TEXT,
  p_quantity INTEGER,
  p_unit_price NUMERIC(10,2),
  p_reason TEXT,
  p_created_by UUID
)
RETURNS TABLE (
  id UUID,
  product_id UUID,
  product_name TEXT,
  quantity INTEGER,
  unit_price NUMERIC(10,2),
  reason TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ
) AS $$
DECLARE
  v_stock INTEGER;
  v_purchase_price NUMERIC(10,2);
BEGIN
  -- 0. Idempotency: if this damaged record already exists, return it immediately
  RETURN QUERY
  SELECT dp.id, dp.product_id, dp.product_name, dp.quantity, dp.unit_price,
         dp.reason, dp.created_by, dp.created_at
  FROM damaged_products dp
  WHERE dp.id = p_id;

  IF FOUND THEN
    RETURN;
  END IF;

  -- 1. Lock product row and read stock + purchase_price
  SELECT p.stock, p.purchase_price INTO v_stock, v_purchase_price
  FROM products p
  WHERE p.id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product % not found', p_product_id;
  END IF;

  -- 2. Validate quantity
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Damaged quantity must be positive, got %', p_quantity;
  END IF;

  -- 3. Validate stock
  IF v_stock < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock: available %, damaged %', v_stock, p_quantity;
  END IF;

  -- 4. Insert damaged record with client-supplied UUID
  INSERT INTO damaged_products (id, product_id, product_name, quantity, unit_price, reason, created_by)
  VALUES (p_id, p_product_id, p_product_name, p_quantity, p_unit_price, p_reason, p_created_by);

  -- 5. Deduct products.stock
  UPDATE products
  SET stock = stock - p_quantity
  WHERE id = p_product_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product % not found — cannot deduct stock', p_product_id;
  END IF;

  -- 6. Deduct inventory_batches (existing FIFO function, not modified)
  PERFORM deduct_stock_fifo(p_product_id, p_quantity);

  -- 7. Return created record
  RETURN QUERY
  SELECT dp.id, dp.product_id, dp.product_name, dp.quantity, dp.unit_price,
         dp.reason, dp.created_by, dp.created_at
  FROM damaged_products dp
  WHERE dp.id = p_id;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = public;

-- 3. GRANT EXECUTE
-- ============================================

GRANT EXECUTE ON FUNCTION create_return_atomic(UUID, UUID, UUID, TEXT, INTEGER, NUMERIC, NUMERIC, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION create_damaged_atomic(UUID, UUID, TEXT, INTEGER, NUMERIC, TEXT, UUID) TO authenticated;
