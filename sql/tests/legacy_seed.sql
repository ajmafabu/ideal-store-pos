-- Data written the way app <= 1.0.122 wrote it, on the OLD schema/functions.
SET client_min_messages = warning;
-- the live DB got these out-of-band (the old app reads and writes them)
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'cash';
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS round_off NUMERIC(10,2) DEFAULT 0;
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('00000000-0000-0000-0000-0000000000aa', 'owner@shop.in', '{"name":"Owner","role":"admin"}');
INSERT INTO accounts (id, name, account_type, balance) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'Cash in Hand', 'cash', 5000),     -- opening 5000, no journal row
  ('a0000000-0000-0000-0000-000000000002', 'Bank Account', 'bank', 0);
INSERT INTO products (id, name, purchase_price, selling_price, stock) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'Oil', 90, 100, 0);
INSERT INTO customers (id, name) VALUES ('c0000000-0000-0000-0000-000000000001', 'Old Customer');
-- legacy purchase: 50 oil @90, "digital" (old app posted it to CASH)
INSERT INTO purchases (id, supplier_name, items, total_amount, is_credit, amount_paid)
VALUES ('d0000000-0000-0000-0000-000000000001', 'Agency', '[{"product_id":"b0000000-0000-0000-0000-000000000001","name":"Oil","qty":50,"price":90,"total":4500}]', 4500, false, 4500);
UPDATE purchases SET payment_method = 'digital' WHERE id = 'd0000000-0000-0000-0000-000000000001';
SELECT increment_stock('b0000000-0000-0000-0000-000000000001', 50);
SELECT add_inventory_batch('b0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 50, 90, NULL, NULL);
SELECT add_account_transaction('a0000000-0000-0000-0000-000000000001', 'out', 4500, 'purchase', 'Purchase');
-- legacy cash sale of 10 oil = 1000 (old trigger deducts stock; app posts cash)
INSERT INTO sales (id, items, total_amount, final_amount, payment_method)
VALUES ('e0000000-0000-0000-0000-000000000001', '[{"product_id":"b0000000-0000-0000-0000-000000000001","name":"Oil","qty":10,"price":100,"total":1000,"purchase_price":90}]', 1000, 1000, 'cash');
SELECT add_account_transaction('a0000000-0000-0000-0000-000000000001', 'in', 1000, 'sale', 'Sale #e0000000');
-- legacy credit sale 5 oil = 500, 200 paid upfront (old app posted NOTHING)
INSERT INTO sales (id, items, total_amount, final_amount, payment_method, customer_id, is_credit, amount_paid, due_amount)
VALUES ('e0000000-0000-0000-0000-000000000002', '[{"product_id":"b0000000-0000-0000-0000-000000000001","name":"Oil","qty":5,"price":100,"total":500,"purchase_price":90}]', 500, 500, 'credit', 'c0000000-0000-0000-0000-000000000001', true, 200, 300);
-- legacy return of 2 oil from the cash sale, refund 200 out of cash
-- (the repo's create_return_atomic fails with "column reference id is ambiguous",
--  so we write what it intended directly)
INSERT INTO product_returns (id, product_id, original_sale_id, product_name, quantity, refund_amount, reason)
VALUES ('f0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'Oil', 2, 200, 'leak');
SELECT increment_stock('b0000000-0000-0000-0000-000000000001', 2);
SELECT restore_stock_fifo('b0000000-0000-0000-0000-000000000001', 2, 90);
SELECT add_account_transaction('a0000000-0000-0000-0000-000000000001', 'out', 200, 'return_refund', 'Return: Oil');
-- legacy expense (cash) and a "bank" customer payment the old app booked to cash
INSERT INTO expenses (id, category, amount) VALUES ('ee000000-0000-0000-0000-000000000001', 'Rent', 700);
SELECT add_account_transaction('a0000000-0000-0000-0000-000000000001', 'out', 700, 'expense', 'Rent');
INSERT INTO payments (id, customer_id, sale_id, amount, payment_method) VALUES
  ('aa000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 100, 'bank');
SELECT add_account_transaction('a0000000-0000-0000-0000-000000000001', 'in', 100, 'credit_collection', 'Collection');

-- Dal: bought 10 (cash), sold 7 by the old app, but its batches still say 10
INSERT INTO products (id, name, purchase_price, selling_price, stock) VALUES ('b0000000-0000-0000-0000-000000000009', 'Dal', 80, 100, 0);
INSERT INTO purchases (id, supplier_name, items, total_amount)
VALUES ('d0000000-0000-0000-0000-000000000009', 'Mill', '[{"product_id":"b0000000-0000-0000-0000-000000000009","name":"Dal","qty":10,"price":80}]', 800);
SELECT increment_stock('b0000000-0000-0000-0000-000000000009', 10);
SELECT add_inventory_batch('b0000000-0000-0000-0000-000000000009', 'd0000000-0000-0000-0000-000000000009', 10, 80, NULL, NULL);
SELECT add_account_transaction('a0000000-0000-0000-0000-000000000001', 'out', 800, 'purchase', 'Purchase Dal');
INSERT INTO sales (id, items, total_amount, final_amount, payment_method)
VALUES ('e0000000-0000-0000-0000-000000000009', '[{"product_id":"b0000000-0000-0000-0000-000000000009","name":"Dal","qty":7,"price":100,"total":700,"purchase_price":80}]', 700, 700, 'cash');
SELECT add_account_transaction('a0000000-0000-0000-0000-000000000001', 'in', 700, 'sale', 'Sale Dal');
-- the old app left the batch untouched: 10 in batches, 3 in stock
UPDATE inventory_batches SET remaining = 10 WHERE product_id = 'b0000000-0000-0000-0000-000000000009';
UPDATE products SET stock = 3 WHERE id = 'b0000000-0000-0000-0000-000000000009';
