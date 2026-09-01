-- Add dual selling price support to products
-- Run this in Supabase SQL Editor

ALTER TABLE products ADD COLUMN IF NOT EXISTS selling_price_2 double precision;
ALTER TABLE products ADD COLUMN IF NOT EXISTS selling_price_2_label text;

COMMENT ON COLUMN products.selling_price_2 IS 'Optional second selling price (e.g., old rate)';
COMMENT ON COLUMN products.selling_price_2_label IS 'Label for second selling price (e.g., "Old Rate", "MRP")';
