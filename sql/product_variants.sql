-- ============================================
-- PRODUCT VARIANTS MIGRATION
-- Run in Supabase SQL Editor
-- ============================================

-- 1. Create product_variants table
CREATE TABLE IF NOT EXISTS product_variants (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  name TEXT NOT NULL,                    -- e.g., "500g", "1kg", "Red", "Blue"
  sku TEXT,                              -- Optional SKU for this variant
  barcode TEXT,                          -- Optional barcode for this variant
  price NUMERIC NOT NULL DEFAULT 0,      -- Sale price for this variant
  purchase_price NUMERIC NOT NULL DEFAULT 0, -- Purchase price for this variant
  stock INTEGER NOT NULL DEFAULT 0,      -- Stock for this variant
  min_stock INTEGER NOT NULL DEFAULT 0,  -- Min stock for this variant
  attributes JSONB DEFAULT '{}',         -- Flexible: {"size": "500g", "color": "Red", "weight": "1kg"}
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(product_id, name)
);

-- 2. Enable RLS
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policies
DROP POLICY IF EXISTS "Anyone can read product_variants" ON product_variants;
CREATE POLICY "Anyone can read product_variants" ON product_variants
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Admins manage product_variants" ON product_variants;
CREATE POLICY "Admins manage product_variants" ON product_variants
  FOR ALL USING (is_admin());

-- 4. Index for performance
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_barcode ON product_variants(barcode);

-- 5. Update products table - add variant support flag
ALTER TABLE products ADD COLUMN IF NOT EXISTS has_variants BOOLEAN DEFAULT false;

-- 6. Trigger to update updated_at
CREATE OR REPLACE FUNCTION update_product_variants_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_product_variants_updated_at ON product_variants;
CREATE TRIGGER trigger_update_product_variants_updated_at
  BEFORE UPDATE ON product_variants
  FOR EACH ROW
  EXECUTE FUNCTION update_product_variants_updated_at();