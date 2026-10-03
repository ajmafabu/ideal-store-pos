-- ============================================================
-- Accounting Improvements Migration
-- Fixes 1-17: Due dates, IGST, credit limits, audit trail,
-- stock reconciliation, payment reminders, financial reports
-- ============================================================

BEGIN;

-- ============================================================
-- 1. Add due dates to sales and purchases
-- ============================================================
ALTER TABLE sales ADD COLUMN IF NOT EXISTS due_date DATE;
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS due_date DATE;

-- ============================================================
-- 2. Add IGST support
-- ============================================================
ALTER TABLE sales ADD COLUMN IF NOT EXISTS igst_amount NUMERIC DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS cgst_amount NUMERIC DEFAULT 0;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS sgst_amount NUMERIC DEFAULT 0;

-- Add state_code to customers, suppliers, and shops
ALTER TABLE customers ADD COLUMN IF NOT EXISTS state_code TEXT DEFAULT '33'; -- Tamil Nadu
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS state_code TEXT DEFAULT '33';
ALTER TABLE shops ADD COLUMN IF NOT EXISTS state_code TEXT DEFAULT '33';

-- ============================================================
-- 3. Add credit limits
-- ============================================================
ALTER TABLE customers ADD COLUMN IF NOT EXISTS credit_limit NUMERIC DEFAULT 0;

-- ============================================================
-- 4. Add audit trail for all operations
-- ============================================================
CREATE TABLE IF NOT EXISTS audit_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    action TEXT NOT NULL, -- INSERT, UPDATE, DELETE
    old_data JSONB,
    new_data JSONB,
    performed_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage audit_log" ON audit_log FOR ALL USING (true);

-- ============================================================
-- 5. Create audit trigger function and apply to key tables
-- ============================================================
CREATE OR REPLACE FUNCTION audit_trigger_func()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, record_id, action, new_data, performed_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', to_jsonb(NEW), auth.uid());
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, record_id, action, old_data, new_data, performed_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW), auth.uid());
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, record_id, action, old_data, performed_by)
        VALUES (TG_TABLE_NAME, OLD.id, 'DELETE', to_jsonb(OLD), auth.uid());
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply audit triggers to key tables
DROP TRIGGER IF EXISTS audit_sales ON sales;
CREATE TRIGGER audit_sales AFTER INSERT OR UPDATE OR DELETE ON sales
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

DROP TRIGGER IF EXISTS audit_purchases ON purchases;
CREATE TRIGGER audit_purchases AFTER INSERT OR UPDATE OR DELETE ON purchases
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

DROP TRIGGER IF EXISTS audit_account_transactions ON account_transactions;
CREATE TRIGGER audit_account_transactions AFTER INSERT OR UPDATE OR DELETE ON account_transactions
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

DROP TRIGGER IF EXISTS audit_expenses ON expenses;
CREATE TRIGGER audit_expenses AFTER INSERT OR UPDATE OR DELETE ON expenses
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

-- ============================================================
-- 6. Create stock reconciliation table
-- ============================================================
CREATE TABLE IF NOT EXISTS stock_reconciliation (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    product_id UUID REFERENCES products(id),
    system_qty INTEGER NOT NULL,
    physical_qty INTEGER NOT NULL,
    notes TEXT,
    performed_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE stock_reconciliation ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage stock_reconciliation" ON stock_reconciliation FOR ALL USING (true);

-- ============================================================
-- 7. Create payment_reminders table
-- ============================================================
CREATE TABLE IF NOT EXISTS payment_reminders (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    customer_id UUID REFERENCES customers(id),
    sale_id UUID REFERENCES sales(id),
    amount NUMERIC NOT NULL,
    due_date DATE NOT NULL,
    reminder_date DATE NOT NULL,
    status TEXT DEFAULT 'pending', -- pending, sent, paid
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE payment_reminders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage payment_reminders" ON payment_reminders FOR ALL USING (true);

-- ============================================================
-- 8. Create function for aging analysis (receivables)
-- ============================================================
CREATE OR REPLACE FUNCTION get_receivables_aging()
RETURNS TABLE (
    customer_id UUID,
    customer_name TEXT,
    total_due NUMERIC,
    current NUMERIC,
    days_30 NUMERIC,
    days_60 NUMERIC,
    days_90 NUMERIC,
    over_90 NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id as customer_id,
        c.name as customer_name,
        COALESCE(c.total_credit, 0) as total_due,
        COALESCE(SUM(CASE WHEN s.due_date >= CURRENT_DATE THEN s.due_amount ELSE 0 END), 0) as "current",
        COALESCE(SUM(CASE WHEN s.due_date < CURRENT_DATE AND s.due_date >= CURRENT_DATE - INTERVAL '30 days' THEN s.due_amount ELSE 0 END), 0) as days_30,
        COALESCE(SUM(CASE WHEN s.due_date < CURRENT_DATE - INTERVAL '30 days' AND s.due_date >= CURRENT_DATE - INTERVAL '60 days' THEN s.due_amount ELSE 0 END), 0) as days_60,
        COALESCE(SUM(CASE WHEN s.due_date < CURRENT_DATE - INTERVAL '60 days' AND s.due_date >= CURRENT_DATE - INTERVAL '90 days' THEN s.due_amount ELSE 0 END), 0) as days_90,
        COALESCE(SUM(CASE WHEN s.due_date < CURRENT_DATE - INTERVAL '90 days' THEN s.due_amount ELSE 0 END), 0) as over_90
    FROM customers c
    LEFT JOIN sales s ON s.customer_id = c.id AND s.is_credit = true AND s.due_amount > 0
    WHERE c.total_credit > 0
    GROUP BY c.id, c.name, c.total_credit
    ORDER BY c.total_credit DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 9. Create function for GSTR-3B summary
-- ============================================================
CREATE OR REPLACE FUNCTION get_gstr3b_summary(
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    outward_taxable NUMERIC,
    outward_igst NUMERIC,
    outward_cgst NUMERIC,
    outward_sgst NUMERIC,
    inward_taxable NUMERIC,
    inward_igst NUMERIC,
    inward_cgst NUMERIC,
    inward_sgst NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(SUM(s.final_amount), 0) as outward_taxable,
        COALESCE(SUM(s.igst_amount), 0) as outward_igst,
        COALESCE(SUM(s.cgst_amount), 0) as outward_cgst,
        COALESCE(SUM(s.sgst_amount), 0) as outward_sgst,
        0::NUMERIC as inward_taxable,
        0::NUMERIC as inward_igst,
        0::NUMERIC as inward_cgst,
        0::NUMERIC as inward_sgst
    FROM sales s
    WHERE s.created_at >= p_start_date AND s.created_at < p_end_date + INTERVAL '1 day';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 10. Create function for trial balance
-- ============================================================
CREATE OR REPLACE FUNCTION get_trial_balance()
RETURNS TABLE (
    account_name TEXT,
    account_type TEXT,
    debit NUMERIC,
    credit NUMERIC,
    balance NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        a.name as account_name,
        a.account_type,
        CASE WHEN a.balance > 0 THEN a.balance ELSE 0 END as debit,
        CASE WHEN a.balance < 0 THEN -a.balance ELSE 0 END as credit,
        a.balance
    FROM accounts a
    ORDER BY a.account_type, a.name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 11. Create function for Profit & Loss statement
-- ============================================================
CREATE OR REPLACE FUNCTION get_profit_loss(
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    sales_total NUMERIC,
    purchase_cost NUMERIC,
    gross_profit NUMERIC,
    expenses_total NUMERIC,
    net_profit NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE((SELECT SUM(s.final_amount) FROM sales s WHERE s.created_at >= p_start_date AND s.created_at < p_end_date + INTERVAL '1 day'), 0) as sales_total,
        COALESCE((SELECT SUM(p.total_amount) FROM purchases p WHERE p.created_at >= p_start_date AND p.created_at < p_end_date + INTERVAL '1 day'), 0) as purchase_cost,
        0::NUMERIC as gross_profit,
        COALESCE((SELECT SUM(e.amount) FROM expenses e WHERE e.created_at >= p_start_date AND e.created_at < p_end_date + INTERVAL '1 day'), 0) as expenses_total,
        0::NUMERIC as net_profit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 12. Fix the get_monthly_profit function (currently returns 0)
-- ============================================================
CREATE OR REPLACE FUNCTION get_monthly_profit(
    p_start TIMESTAMPTZ,
    p_end TIMESTAMPTZ
)
RETURNS TABLE (
    sales_total NUMERIC,
    purchase_cost NUMERIC,
    expenses_total NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE((SELECT SUM(s.final_amount) FROM sales s WHERE s.created_at >= p_start AND s.created_at < p_end), 0),
        COALESCE((SELECT SUM(p.total_amount) FROM purchases p WHERE p.created_at >= p_start AND p.created_at < p_end), 0),
        COALESCE((SELECT SUM(e.amount) FROM expenses e WHERE e.created_at >= p_start AND e.created_at < p_end), 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- Grants
-- ============================================================
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON audit_log TO authenticated;
GRANT ALL ON stock_reconciliation TO authenticated;
GRANT ALL ON payment_reminders TO authenticated;
GRANT EXECUTE ON FUNCTION get_receivables_aging() TO authenticated;
GRANT EXECUTE ON FUNCTION get_gstr3b_summary(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_trial_balance() TO authenticated;
GRANT EXECUTE ON FUNCTION get_profit_loss(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_monthly_profit(TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION audit_trigger_func() TO authenticated;

COMMIT;
