-- Add SFW (Short Finding Words) and Unit Type columns to products table
-- Run this in Supabase SQL Editor

-- Add SFW column for quick product search
ALTER TABLE products ADD COLUMN IF NOT EXISTS sfw text;

-- Add unit type column (pieces/pack/saram/box)
ALTER TABLE products ADD COLUMN IF NOT EXISTS unit_type text DEFAULT 'pieces';

-- Add pieces per unit column (how many pieces in 1 pack/saram/box)
ALTER TABLE products ADD COLUMN IF NOT EXISTS pieces_per_unit int DEFAULT 1;

-- Create index on SFW for fast search
CREATE INDEX IF NOT EXISTS idx_products_sfw ON products (sfw);

-- Auto-generate SFW from existing product names (first letter of each word)
UPDATE products
SET sfw = (
  SELECT string_agg(substr(word, 1, 1), '')
  FROM unnest(string_to_array(lower(name), ' ')) AS word
)
WHERE sfw IS NULL;
