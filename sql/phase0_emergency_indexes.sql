BEGIN;

-- ============================================
-- PHASE 0: EMERGENCY PERFORMANCE INDEXES
-- Run this ONCE in Supabase SQL Editor
-- ============================================

-- 1. GIN index for JSONB array operations on sales.items
-- Speeds up: get_category_sales, get_inventory_health, get_product_insights
-- These RPCs use jsonb_array_elements(sales.items) which without a GIN index
-- causes full table scans on every call.
CREATE INDEX IF NOT EXISTS idx_sales_items_gin ON sales USING GIN (items);

-- 2. Composite index for FIFO batch queries
-- Speeds up: deduct_stock_fifo, restore_stock_fifo, delete_sale_atomic
-- These functions filter on (product_id, purchase_price, remaining) in loops.
CREATE INDEX IF NOT EXISTS idx_batches_fifo ON inventory_batches(product_id, purchase_price, remaining);

-- 3. Partial index for credit sales due amount lookups
-- Speeds up: get_financial_summary receivables query
-- The receivables CTE filters: is_credit = true AND due_amount > 0
CREATE INDEX IF NOT EXISTS idx_sales_credit_due ON sales(is_credit, due_amount) WHERE is_credit = true AND due_amount > 0;


COMMIT;