-- Step 1: Clear ALL tamil_name values to NULL
-- This removes corrupted Unicode text from earlier failed attempts
UPDATE products SET tamil_name = NULL WHERE tamil_name IS NOT NULL;

-- Verify all are cleared
SELECT COUNT(*) as total_products,
       COUNT(tamil_name) as products_with_tamil_name
FROM products;
