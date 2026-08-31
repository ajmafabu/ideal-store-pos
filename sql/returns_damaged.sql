-- ============================================
-- PRODUCT RETURNS & DAMAGED PRODUCTS
-- RLS is in rls_consolidated.sql
-- ============================================

CREATE TABLE IF NOT EXISTS product_returns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id UUID REFERENCES sales(id),
  product_id UUID REFERENCES products(id),
  product_name TEXT NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(10,2) DEFAULT 0,
  refund_amount NUMERIC(10,2) DEFAULT 0,
  reason TEXT,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS damaged_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID REFERENCES products(id),
  product_name TEXT NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(10,2) DEFAULT 0,
  reason TEXT,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_returns_sale ON product_returns(sale_id);
CREATE INDEX IF NOT EXISTS idx_returns_product ON product_returns(product_id);
CREATE INDEX IF NOT EXISTS idx_returns_date ON product_returns(created_at);
CREATE INDEX IF NOT EXISTS idx_damaged_product ON damaged_products(product_id);
CREATE INDEX IF NOT EXISTS idx_damaged_date ON damaged_products(created_at);
