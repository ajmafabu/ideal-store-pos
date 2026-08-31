-- Add tamil_name column to products table
ALTER TABLE products ADD COLUMN IF NOT EXISTS tamil_name text;

-- Add tamil_name to product_variants if needed
ALTER TABLE product_variants ADD COLUMN IF NOT EXISTS tamil_name text;
