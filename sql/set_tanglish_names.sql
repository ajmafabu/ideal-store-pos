-- Set Tamil name to product name for products with no Tamil translation
-- This uses the product's English name as Tanglish Tamil name
UPDATE products
SET tamil_name = name
WHERE tamil_name IS NULL;

-- Verify
SELECT COUNT(*) as total_products,
       COUNT(tamil_name) as products_with_tamil_name
FROM products;
