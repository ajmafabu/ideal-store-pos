-- Returns V2 Migration
-- Adds link to original sale and return amount tracking

ALTER TABLE product_returns ADD COLUMN IF NOT EXISTS original_sale_id UUID REFERENCES sales(id);
ALTER TABLE product_returns ADD COLUMN IF NOT EXISTS return_amount NUMERIC DEFAULT 0;

-- Index for faster lookups
CREATE INDEX IF NOT EXISTS idx_product_returns_original_sale_id ON product_returns(original_sale_id);
