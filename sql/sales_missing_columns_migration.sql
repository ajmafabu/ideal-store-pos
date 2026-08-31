-- Add missing columns to sales table that toInsertJson() sends
-- These were never added via migration, causing silent insert failures

ALTER TABLE sales ADD COLUMN IF NOT EXISTS extra_charges NUMERIC(10,2) DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS round_off NUMERIC(10,2) DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS tax_exempt BOOLEAN DEFAULT false;
