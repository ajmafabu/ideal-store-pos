-- Add GST columns to products table
ALTER TABLE products ADD COLUMN IF NOT EXISTS gst_rate NUMERIC DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS hsn_code TEXT;

-- Add GSTIN and shop info columns to profiles table
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS gstin TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS shop_name TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS shop_address TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS shop_phone TEXT;
