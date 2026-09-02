-- ============================================
-- FIX: Customer credit not reversed on sale deletion
-- Run this in: Supabase Dashboard → SQL Editor
-- ============================================
-- The trigger on_sale_credit_update only fired on INSERT/UPDATE,
-- not DELETE. This meant deleting a credit sale left the customer's
-- total_credit stale (still including the deleted sale's due_amount).
-- ============================================

-- 1. Update the function to handle both NEW and OLD records
CREATE OR REPLACE FUNCTION update_customer_credit()
RETURNS trigger AS $$
DECLARE
  cust_id UUID;
BEGIN
  cust_id := COALESCE(NEW.customer_id, OLD.customer_id);
  IF cust_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  UPDATE customers
  SET total_credit = (
    SELECT COALESCE(SUM(due_amount), 0)
    FROM sales
    WHERE customer_id = cust_id AND due_amount > 0
  )
  WHERE id = cust_id;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Recreate the trigger to also fire on DELETE
DROP TRIGGER IF EXISTS on_sale_credit_update ON sales;
CREATE TRIGGER on_sale_credit_update
  AFTER INSERT OR UPDATE OR DELETE ON sales
  FOR EACH ROW EXECUTE FUNCTION update_customer_credit();

-- 3. Recalculate all customer credits to fix any existing stale data
UPDATE customers c
SET total_credit = (
  SELECT COALESCE(SUM(due_amount), 0)
  FROM sales s
  WHERE s.customer_id = c.id AND s.due_amount > 0
);
