-- Fix: Allow deleting customers that have associated sales/reminders
-- Sales keep their customer_id set to NULL (sale record preserved)
-- Payment reminders are deleted when customer is deleted

-- 1. Fix sales.customer_id FK: ON DELETE SET NULL
ALTER TABLE sales DROP CONSTRAINT IF EXISTS sales_customer_id_fkey;
ALTER TABLE sales ADD CONSTRAINT sales_customer_id_fkey
  FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;

-- 2. Fix payment_reminders.customer_id FK: ON DELETE CASCADE
ALTER TABLE payment_reminders DROP CONSTRAINT IF EXISTS payment_reminders_customer_id_fkey;
ALTER TABLE payment_reminders ADD CONSTRAINT payment_reminders_customer_id_fkey
  FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE;
