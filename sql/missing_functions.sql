-- ============================================
-- MISSING DATABASE FUNCTIONS
-- Run this in: Supabase Dashboard → SQL Editor
-- ============================================

-- 1. DECREMENT STOCK (for manual stock deduction)
-- ============================================

CREATE OR REPLACE FUNCTION decrement_stock(p_product_id UUID, p_qty INTEGER)
RETURNS void AS $$
BEGIN
  UPDATE products
  SET stock = GREATEST(stock - p_qty, 0)
  WHERE id = p_product_id;
END;
$$ LANGUAGE plpgsql;
