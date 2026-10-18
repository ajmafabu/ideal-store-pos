-- =====================================================================
-- End-to-end scenario test for sql/2026_10_audit_fixes.sql
-- Run on a THROWAWAY database (never production):
--   psql -v ON_ERROR_STOP=1 -f sql/tests/supabase_stub.sql   (local Postgres only)
--   psql -v ON_ERROR_STOP=1 -f sql/2026_10_audit_fixes.sql
--   psql -v ON_ERROR_STOP=1 -f sql/tests/scenario_test.sql
-- Every check raises an exception on failure; success ends with "ALL SCENARIO TESTS PASSED".
-- =====================================================================
\set QUIET on
SET client_min_messages = warning;

\i scenario_helpers.sql


-- ---------------------------------------------------------------- users
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('00000000-0000-0000-0000-00000000000a', 'owner@shop.in', '{"name":"Owner"}'),
  ('00000000-0000-0000-0000-00000000000b', 'staff@shop.in', '{"name":"Staff","role":"admin"}'),
  ('00000000-0000-0000-0000-00000000000c', 'intruder@x.in', '{"name":"Intruder","role":"admin"}');
SELECT t.ok((SELECT role='admin' AND active FROM profiles WHERE id='00000000-0000-0000-0000-00000000000a'), 'first signup of a new shop becomes the active admin');
SELECT t.ok((SELECT role='staff' AND NOT active FROM profiles WHERE id='00000000-0000-0000-0000-00000000000c'), 'signup metadata role=admin is ignored (#2)');

-- ---------------------------------------------------------------- staff, inactive
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000b',false);
SELECT set_config('request.jwt.claim.role','authenticated',false);
SET ROLE authenticated;
SELECT t.fails($$INSERT INTO sales(items, final_amount) VALUES ('[]', 10)$$, 'not active', 'inactive staff cannot sell');
SELECT t.fails($$UPDATE profiles SET role='admin', active=true WHERE id=auth.uid()$$, 'Only an admin', 'staff cannot promote or activate self (#3)');
SELECT t.eq((SELECT count(*) FROM products), 0, 'inactive account reads no products');
RESET ROLE;

-- ---------------------------------------------------------------- admin setup
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
SET ROLE authenticated;
SELECT admin_set_staff('00000000-0000-0000-0000-00000000000b', NULL, NULL, true, NULL);
UPDATE shop_settings SET shop_name = 'Ideal Store', state_code = '33', gstin = '33ABCDE1234F1Z5' WHERE id = 1;
INSERT INTO products (id, name, purchase_price, selling_price, stock, unit_type, gst_rate) VALUES
  ('10000000-0000-0000-0000-000000000001', 'Rice 1kg', 0, 60, 0, 'pieces', 0),
  ('10000000-0000-0000-0000-000000000002', 'Soap', 0, 30, 0, 'pieces', 18),
  ('10000000-0000-0000-0000-000000000003', 'Biscuit', 0, 10, 0, 'pieces', 0);
INSERT INTO suppliers (id, name, state_code) VALUES ('20000000-0000-0000-0000-000000000001', 'Agency', '33');
INSERT INTO customers (id, name, state_code) VALUES
  ('30000000-0000-0000-0000-000000000001', 'Ravi', '33'),
  ('30000000-0000-0000-0000-000000000002', 'Kerala Traders', '32');

-- purchase 1: credit purchase, 1000 of 1500 paid by UPI — one insert does everything (#11)
INSERT INTO purchases (id, supplier_id, supplier_name, items, total_amount, is_credit, amount_paid, payment_method)
VALUES ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Agency',
  '[{"product_id":"10000000-0000-0000-0000-000000000001","name":"Rice 1kg","qty":20,"price":50},
    {"product_id":"10000000-0000-0000-0000-000000000002","name":"Soap","qty":20,"price":25}]', 1500, true, 1000, 'digital');
RESET ROLE;
SELECT t.eq(t.stock('Rice 1kg'), 20, 'purchase adds stock');
SELECT t.eq(t.batches('Rice 1kg'), 20, 'purchase creates a batch with the purchase id');
SELECT t.eq((SELECT due_amount FROM purchases WHERE id='40000000-0000-0000-0000-000000000001'), 500, 'purchase due = total - paid');
SELECT t.eq((SELECT total_dues FROM suppliers WHERE name='Agency'), 500, 'supplier dues follow');
SELECT t.eq(t.bal('bank'), -1000, 'digital purchase payment leaves the BANK, not cash (#12)');
SELECT t.eq(t.bal('cash'), 0, 'cash untouched by a UPI purchase');

-- purchase 2: same rice at a higher price, cash, with a bill discount spread as landed cost
SET ROLE authenticated;
INSERT INTO purchases (id, supplier_name, items, total_amount, payment_method)
VALUES ('40000000-0000-0000-0000-000000000002', 'Market',
  '[{"product_id":"10000000-0000-0000-0000-000000000001","name":"Rice 1kg","qty":10,"price":56,"batch_number":"B2","expiry_date":"2026-10-20"},
    {"product_id":"10000000-0000-0000-0000-000000000003","name":"Biscuit","qty":240,"price":5}]', 1680, 'cash');
RESET ROLE;
SELECT t.eq(t.bal('cash'), -1680, 'cash purchase posts once, server-side');
SELECT t.eq((SELECT purchase_price FROM inventory_batches WHERE batch_number='B2'), 56 * 1680 / 1760.0, 'bill discount spread into landed batch cost');

-- a price edit sent with a stale stock figure keeps the price, not the stock (#8)
SET ROLE authenticated;
UPDATE products SET selling_price = 11, stock = 999 WHERE name = 'Biscuit';
RESET ROLE;
SELECT t.eq((SELECT selling_price FROM products WHERE name='Biscuit'), 11, 'app price edit is saved (#8)');
SELECT t.eq(t.stock('Biscuit'), 240, 'app update cannot overwrite stock (#8)');
-- the live database refused every app product edit: the guard trigger runs as
-- the app user and needs app_bulk_mode() (stage 1, QA #5)
SELECT t.ok(has_function_privilege('authenticated', 'public.app_bulk_mode()', 'EXECUTE'), 'app user may run the stock guard (QA #5)');
SELECT t.ok(NOT has_function_privilege('anon', 'public.app_bulk_mode()', 'EXECUTE'), 'anon still may not (verify check 8)');
SET ROLE authenticated;
UPDATE products SET selling_price = 10 WHERE name = 'Biscuit';
RESET ROLE;

-- Stock In / Out by quantity is locked and keeps batches in step
SET ROLE authenticated;
SELECT t.eq(adjust_stock('10000000-0000-0000-0000-000000000003', 10), 250, 'stock in by quantity');
SELECT t.fails($$SELECT adjust_stock('10000000-0000-0000-0000-000000000003', -1000)$$, 'cannot remove', 'stock out cannot go below zero');
SELECT t.eq(adjust_stock('10000000-0000-0000-0000-000000000003', -10), 240, 'stock out by quantity');
RESET ROLE;
SELECT t.eq(t.batches('Biscuit'), 240, 'batches follow stock in/out');

-- ---------------------------------------------------------------- staff sells
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000b',false);
SET ROLE authenticated;
-- 25 rice spans both batches: 20 @ 50 + 5 @ 53.4545
INSERT INTO sales (id, items, total_amount, final_amount, payment_method)
VALUES ('50000000-0000-0000-0000-000000000001',
  '[{"product_id":"10000000-0000-0000-0000-000000000001","name":"Rice 1kg","qty":25,"price":60,"total":1500,"purchase_price":1}]',
  1500, 1500, 'cash');
SELECT t.fails($$SELECT add_account_transaction('00000000-0000-0000-0000-000000000000','out',100,'other','x',NULL,'manual')$$, 'Admin permission required', 'staff cannot move money (#3)');
SELECT t.fails($$SELECT reconcile_stock_with_batches('10000000-0000-0000-0000-000000000001', 999)$$, 'Admin permission required', 'staff cannot rewrite stock (#3)');
SELECT t.fails($$SELECT increment_stock('10000000-0000-0000-0000-000000000001', 5)$$, 'permission denied', 'internal stock helpers are not callable');
SELECT t.eq((SELECT count(*) FROM purchases), 0, 'staff cannot read purchases');
SELECT t.ok((get_dashboard_summary()->>'monthly_profit') IS NULL, 'staff dashboard hides profit (#28)');
RESET ROLE;
SELECT t.eq(t.stock('Rice 1kg'), 5, 'sale deducts stock');
SELECT t.eq(t.batches('Rice 1kg'), 5, 'batches stay in step with stock');
SELECT t.eq((SELECT (items->0->>'cost_total')::numeric FROM sales WHERE id='50000000-0000-0000-0000-000000000001'),
            round(20*50 + 5*(56*1680/1760.0), 2), 'true multi-batch FIFO cost (#22)');
SELECT t.eq(t.bal('cash'), -1680 + 1500, 'cash sale posted by the database (#10)');
SELECT t.ok((SELECT invoice_no IS NOT NULL FROM sales WHERE id='50000000-0000-0000-0000-000000000001'), 'sale gets a printable invoice number (#19)');

SET ROLE authenticated;
-- credit sale with 200 paid upfront in cash (old app booked nothing)
INSERT INTO sales (id, items, total_amount, final_amount, payment_method, customer_id, is_credit, amount_paid, due_amount)
VALUES ('50000000-0000-0000-0000-000000000002',
  '[{"product_id":"10000000-0000-0000-0000-000000000002","name":"Soap","qty":10,"price":30,"total":300,"gst_rate":18}]',
  300, 300, 'credit', '30000000-0000-0000-0000-000000000001', true, 200, 100);
-- split: 600 cash + 500 UPI on a 1000 bill (100 change)
INSERT INTO sales (id, items, total_amount, final_amount, payment_method, cash_amount, digital_amount)
VALUES ('50000000-0000-0000-0000-000000000003',
  '[{"product_id":"10000000-0000-0000-0000-000000000003","name":"Biscuit","qty":100,"price":10,"total":1000}]',
  1000, 1000, 'split', 600, 500);
-- one-sided split: 0 cash + 400 UPI
INSERT INTO sales (id, items, total_amount, final_amount, payment_method, cash_amount, digital_amount)
VALUES ('50000000-0000-0000-0000-000000000004',
  '[{"product_id":"10000000-0000-0000-0000-000000000003","name":"Biscuit","qty":40,"price":10,"total":400}]',
  400, 400, 'split', 0, 400);
-- a box of 12 biscuits sold as one line (stock_factor sent by the new app)
INSERT INTO sales (id, items, total_amount, final_amount, payment_method)
VALUES ('50000000-0000-0000-0000-000000000005',
  '[{"product_id":"10000000-0000-0000-0000-000000000003","name":"Biscuit","qty":2,"price":110,"total":220,"unit_type":"box","pieces_per_unit":12,"stock_factor":12}]',
  220, 220, 'upi');
-- inter-state customer: IGST
INSERT INTO sales (id, items, total_amount, final_amount, payment_method, customer_id)
VALUES ('50000000-0000-0000-0000-000000000006',
  '[{"product_id":"10000000-0000-0000-0000-000000000002","name":"Soap","qty":2,"price":59,"total":118,"gst_rate":18}]',
  118, 118, 'cash', '30000000-0000-0000-0000-000000000002');
RESET ROLE;
SELECT t.eq(t.stock('Biscuit'), 240 - 100 - 40 - 24, 'box line deducts 12 pieces per box (#22)');
SELECT t.eq((SELECT total_credit FROM customers WHERE name='Ravi'), 100, 'customer credit = due');
SELECT t.eq(t.bal('cash'), -1680 + 1500 + 200 + 500 + 118, 'upfront credit payment + split cash net of change reach cash (#10)');
SELECT t.eq(t.bal('bank'), -1000 + 500 + 400 + 220, 'UPI parts reach the bank, one-sided split included (#10)');
SELECT t.eq((SELECT cgst_amount + sgst_amount FROM sales WHERE id='50000000-0000-0000-0000-000000000002'), round(300*18/118.0, 2), 'GST stored as CGST+SGST within state (#15)');
SELECT t.eq((SELECT igst_amount FROM sales WHERE id='50000000-0000-0000-0000-000000000006'), 18, 'IGST for an inter-state customer (#15)');

-- ---------------------------------------------------------------- admin: collections, returns, edits, deletes
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
SET ROLE authenticated;
SELECT t.fails($$INSERT INTO payments (customer_id, sale_id, amount, payment_method) VALUES ('30000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000002', 150, 'cash')$$,
               'more than the amount due', 'overpayment is rejected');
INSERT INTO payments (customer_id, sale_id, amount, payment_method) VALUES
  ('30000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000002', 40, 'bank');
RESET ROLE;
SELECT t.eq((SELECT due_amount FROM sales WHERE id='50000000-0000-0000-0000-000000000002'), 60, 'collection reduces the due');
SELECT t.eq(t.bal('bank'), -1000 + 500 + 400 + 220 + 40, '"bank" collection goes to the bank (#12)');

-- return 4 soaps on the credit sale: value 4 x 30 = 120; 60 clears the due, 60 refunded in cash
SET ROLE authenticated;
SELECT * FROM create_return_atomic('60000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002',
   '50000000-0000-0000-0000-000000000002','Soap',4, 30, 9999, 'damaged pack', NULL, NULL) \gset r_
RESET ROLE;
SELECT t.eq(:'r_return_amount', 120, 'refund value ignores the client amount and uses paid price (#14)');
SELECT t.eq(:'r_credit_adjusted', 60, 'credit customer: due is reduced first (#14)');
SELECT t.eq((SELECT total_credit FROM customers WHERE name='Ravi'), 0, 'customer balance reduced by the return (#14)');
SELECT t.eq(t.bal('cash'), -1680 + 1500 + 200 + 500 + 118 - 60, 'only the remainder is refunded from cash');
SELECT t.eq(t.stock('Soap'), 20 - 10 - 2 + 4, 'returned stock is back');
-- discounted sale refund: line 100 with 10% off, bill discount 10
SET ROLE authenticated;
INSERT INTO sales (id, items, total_amount, discount, final_amount, payment_method)
VALUES ('50000000-0000-0000-0000-000000000007',
  '[{"product_id":"10000000-0000-0000-0000-000000000003","name":"Biscuit","qty":10,"price":10,"discount":10,"discount_amount":10,"total":90}]',
  90, 10, 80, 'cash');
SELECT (create_return_atomic('60000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000003',
   '50000000-0000-0000-0000-000000000007','Biscuit',5)).return_amount AS disc_ret \gset
RESET ROLE;
SELECT t.eq(:'disc_ret', 40, 'refund of a discounted sale = what was actually paid (#14)');
SET ROLE authenticated;
SELECT t.fails($$SELECT edit_sale_atomic('50000000-0000-0000-0000-000000000007','[]'::jsonb,0,0,0,NULL,false,0,0,'cash',0,0,'x')$$,
               'at least one item', 'edit needs items');
SELECT t.fails($$SELECT edit_sale_atomic('50000000-0000-0000-0000-000000000007','[{"product_id":"10000000-0000-0000-0000-000000000003","name":"Biscuit","qty":1,"price":10,"total":10}]'::jsonb,10,0,10,NULL,false,10,0,'cash',10,0,'fix')$$,
               'has returns', 'a sale with returns cannot be edited');
SELECT t.fails($$UPDATE sales SET items = '[]' WHERE id = '50000000-0000-0000-0000-000000000001'$$,
               'edit_sale_atomic', 'plain UPDATE of items (old offline replay) is refused (#7)');

-- edit: rice 25 -> 10, cash 1500 -> 600, moved to customer Ravi on credit with 100 paid
SELECT edit_sale_atomic('50000000-0000-0000-0000-000000000001',
  '[{"product_id":"10000000-0000-0000-0000-000000000001","name":"Rice 1kg","qty":10,"price":60,"total":600}]'::jsonb,
  600, 0, 600, '30000000-0000-0000-0000-000000000001', true, 100, 500, 'credit', 100, 0, 'customer took less') \gset e_
RESET ROLE;
SELECT t.eq(t.stock('Rice 1kg'), 20, 'edit puts 15 rice back');
SELECT t.eq(t.batches('Rice 1kg'), 20, 'edit keeps batches in step');
SELECT t.eq((SELECT total_credit FROM customers WHERE name='Ravi'), 500, 'edit moves the due to the new customer');
SELECT t.eq(t.bal('cash'), -1680 + 100 + 200 + 500 + 118 - 60 + 80 - 40, 'edit posts one exact delta to one account (#13)');

-- delete the sale that has returns: everything comes back, cash nets to zero (#9)
SET ROLE authenticated;
SELECT delete_sale_atomic('50000000-0000-0000-0000-000000000002');
RESET ROLE;
SELECT t.eq(t.stock('Soap'), 20 - 2, 'delete with returns restores exactly the unreturned stock (#9)');
SELECT t.eq(t.batches('Soap'), 18, 'batches restored too');
SELECT t.eq((SELECT count(*) FROM product_returns WHERE original_sale_id='50000000-0000-0000-0000-000000000002'), 0, 'returns removed with the sale');
SELECT t.eq(t.bal('cash'), -1680 + 100 + 500 + 118 + 80 - 40, 'sale, collection and refund all reversed');
SELECT t.eq(t.bal('bank'), -1000 + 500 + 400 + 220, 'bank collection reversed');

-- purchases: delete blocked once sold, allowed when untouched, edit when untouched
SET ROLE authenticated;
SELECT t.fails($$SELECT delete_purchase_atomic('40000000-0000-0000-0000-000000000002')$$, 'already been sold', 'cannot delete a purchase whose stock was sold (#11)');
INSERT INTO purchases (id, supplier_id, supplier_name, items, total_amount, is_credit, amount_paid, payment_method)
VALUES ('40000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', 'Agency',
  '[{"product_id":"10000000-0000-0000-0000-000000000002","name":"Soap","qty":10,"price":20}]', 200, true, 0, 'cash');
INSERT INTO supplier_payments (supplier_id, purchase_id, amount, payment_method)
VALUES ('20000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001', 500, 'bank');
SELECT edit_purchase_atomic('40000000-0000-0000-0000-000000000003',
  '[{"product_id":"10000000-0000-0000-0000-000000000002","name":"Soap","qty":12,"price":20}]'::jsonb,
  240, '20000000-0000-0000-0000-000000000001', 'Agency', true, 0, 240, 'cash', 'invoice had 12');
RESET ROLE;
SELECT t.eq(t.stock('Soap'), 18 + 12, 'purchase edit replaces its stock');
SELECT t.eq((SELECT total_dues FROM suppliers WHERE name='Agency'), 240, 'dues follow payment and edit');
SELECT t.eq(t.bal('bank'), -1000 + 500 + 400 + 220 - 500, '"bank" supplier payment leaves the bank (#12)');
SET ROLE authenticated;
SELECT delete_purchase_atomic('40000000-0000-0000-0000-000000000003');
RESET ROLE;
SELECT t.eq(t.stock('Soap'), 18, 'deleting an unsold purchase removes its stock');
SELECT t.eq((SELECT total_dues FROM suppliers WHERE name='Agency'), 0, 'supplier dues recomputed after delete (#11)');

-- purchase order receive creates a real purchase (#21)
SET ROLE authenticated;
INSERT INTO purchase_orders (id, supplier_id, supplier_name, items, total_amount, status)
VALUES ('70000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Agency',
  '[{"product_id":"10000000-0000-0000-0000-000000000003","name":"Biscuit","qty":50,"price":4.5}]', 225, 'ordered');
SELECT receive_purchase_order('70000000-0000-0000-0000-000000000001', true, 0, 'cash');
SELECT t.fails($$SELECT receive_purchase_order('70000000-0000-0000-0000-000000000001')$$, 'already received', 'an order is received once');
RESET ROLE;
SELECT t.ok((SELECT purchase_id IS NOT NULL FROM purchase_orders WHERE id='70000000-0000-0000-0000-000000000001'), 'PO linked to its purchase');
SELECT t.eq((SELECT total_dues FROM suppliers WHERE name='Agency'), 225, 'received PO becomes a supplier payable');
SELECT t.ok(EXISTS (SELECT 1 FROM inventory_batches WHERE purchase_price = 4.5), 'received PO stock has a costed batch');

-- expenses, damaged, transfers
SET ROLE authenticated;
INSERT INTO expenses (id, category, amount, payment_method) VALUES ('80000000-0000-0000-0000-000000000001','Rent', 300, 'upi');
INSERT INTO expenses (category, amount, payment_method, created_at) VALUES ('Electricity', 120, 'cash', now() - interval '3 days');
DELETE FROM expenses WHERE id = '80000000-0000-0000-0000-000000000001';
SELECT * FROM create_damaged_atomic('90000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','Biscuit',6,NULL,'rats');
-- a wrong damaged entry can be deleted; its stock comes back (QA #86)
SELECT t.stock('Biscuit') AS biscuit_before \gset
SELECT t.batches('Biscuit') AS biscuit_batches_before \gset
SELECT * FROM create_damaged_atomic('90000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000003','Biscuit',2.5,NULL,'typo');
SELECT t.eq(t.stock('Biscuit'), :biscuit_before - 2.5, 'damaged entry takes stock');
SELECT delete_damaged_atomic('90000000-0000-0000-0000-000000000002');
SELECT t.eq(t.stock('Biscuit'), :biscuit_before, 'deleting it puts the stock back');
SELECT t.eq(t.batches('Biscuit'), :biscuit_batches_before, 'and back into the batches');
SELECT t.eq((SELECT count(*) FROM damaged_products WHERE id = '90000000-0000-0000-0000-000000000002'), 0, 'entry is gone');
SELECT delete_damaged_atomic('90000000-0000-0000-0000-000000000002');
SELECT transfer_between_accounts(t.acc('cash'), t.acc('bank'), 50, 'deposit');
SELECT t.fails($$SELECT transfer_between_accounts(t.acc('cash'), t.acc('cash'), 5)$$, 'two different', 'transfer needs two accounts');
SELECT t.eq((SELECT total_in FROM get_account_summary(now() - interval '1 day', now() + interval '1 day')),
            (SELECT sum(amount) FROM account_transactions WHERE type='in' AND category<>'transfer' AND created_at > now() - interval '1 day'),
            'account summary is server-side and excludes transfers (#20)');
-- an OLD app re-posting a sale itself is ignored
SELECT add_account_transaction(t.acc('cash'), 'in', 1500, 'sale', 'Sale #old');
INSERT INTO account_transactions (account_id, type, amount, category, description) VALUES (t.acc('cash'), 'in', 999, 'sale', 'offline replay');
RESET ROLE;
SELECT t.eq((SELECT count(*) FROM account_transactions WHERE description IN ('Sale #old','offline replay')), 0, 'old-app duplicate postings are dropped');
SELECT t.eq((SELECT sum(balance) FROM accounts), (SELECT sum(CASE WHEN type='in' THEN amount ELSE -amount END) FROM account_transactions),
            'balances equal the journal exactly (#10)');

-- ---------------------------------------------------------------- reports
SET ROLE authenticated;
SELECT t.ok((SELECT balance_check FROM get_balance_sheet()), 'balance sheet balances (#16)');
SELECT t.ok((SELECT abs(difference) < 0.1 FROM get_balance_sheet()), 'no unreconciled difference beyond paise rounding');
SELECT t.ok((SELECT count(*) > 0 FROM get_inventory_health()), 'inventory health runs (#16)');
SELECT t.ok((SELECT total_tax_payable >= 0 FROM get_gstr3b_summary(now() - interval '1 day', now() + interval '1 day')), 'GSTR-3B runs with app argument names (#16)');
SELECT t.ok((SELECT count(*) >= 1 FROM get_receivables_aging()), 'receivables aging runs (#16)');
SELECT t.ok((SELECT closing_balance = (SELECT sum(balance) FROM accounts) FROM get_cash_flow(now() - interval '30 days', now() + interval '1 day')),
            'cash flow closing balance = cash book');
SELECT t.eq((SELECT count(*) FROM get_daily_sales_trend(now() - interval '6 days', now())), 7, 'daily trend has one row per IST day');
SELECT t.ok((SELECT count(*) = 12 FROM get_monthly_sales_summary()), 'monthly summary has 12 months with month_start');
SELECT t.ok((SELECT count(*) > 0 FROM get_category_sales()), 'category sales has one definition (no-arg call works) (#17)');
SELECT t.ok((get_dashboard_summary()->>'monthly_profit') IS NOT NULL, 'admin dashboard has profit');
SELECT t.eq((SELECT sales_total FROM get_monthly_profit(now() - interval '1 day', now() + interval '1 day')),
            (SELECT sum(final_amount - cgst_amount - sgst_amount - igst_amount) FROM sales)
              - (SELECT sum(return_amount - tax_amount) FROM product_returns),
            'profit uses revenue net of GST and returns (#15, #17)');
SELECT t.ok((SELECT count(*) > 0 FROM get_trial_balance()), 'trial balance runs');
SELECT t.ok((SELECT count(*) = 1 FROM get_financial_summary()), 'financial summary runs');
SELECT t.ok((SELECT count(*) = 1 FROM get_sales_forecast()), 'forecast runs');
SELECT t.ok((SELECT count(*) > 0 FROM get_product_insights()), 'product insights run');
SELECT t.ok((SELECT count(*) > 0 FROM get_customer_insights()), 'customer insights run');
SELECT t.ok(jsonb_typeof(get_product_sales_stats()) = 'object', 'product sales stats run');
SELECT t.ok((SELECT count(*) >= 1 FROM get_expiring_batches(30)), 'batch expiry alerts reach the dashboard (#24)');
SELECT t.ok((SELECT count(*) >= 2 FROM get_account_reconciliation()), 'account reconciliation runs');
RESET ROLE;

-- ---------------------------------------------------------------- anon
SELECT set_config('request.jwt.claim.sub','',false);
SET ROLE anon;
SELECT t.eq((SELECT count(*) FROM products), 0, 'anon cannot read products or cost prices (#3)');
SELECT t.ok(get_customer_portal((SELECT portal_token FROM public.customers LIMIT 0)) IS NULL, 'portal with unknown token returns nothing');
SELECT t.fails($$SELECT update_tamil_names('[]')$$, 'permission denied', 'anon cannot call update_tamil_names (#3)');
SELECT t.fails($$SELECT get_dashboard_summary()$$, 'permission denied', 'anon cannot read the dashboard');
RESET ROLE;
SELECT t.ok((SELECT get_customer_portal(portal_token)->>'name' = 'Ravi' FROM customers WHERE name='Ravi'), 'portal works by token');

-- ---------------------------------------------------------------- backup -> reset -> restore
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
CREATE TEMP TABLE snap (d jsonb);
INSERT INTO snap VALUES ('{}');
GRANT SELECT ON snap TO authenticated;
DO $$
DECLARE v jsonb := '{}'::jsonb; tn text; rows jsonb;
BEGIN
  FOREACH tn IN ARRAY backup_table_list() LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)), ''[]'') FROM public.%I x', tn) INTO rows;
    v := v || jsonb_build_object(tn, rows);
  END LOOP;
  UPDATE snap SET d = jsonb_build_object('tables', v);
END $$;
CREATE TEMP TABLE before AS SELECT (SELECT sum(balance) FROM accounts) AS bal, (SELECT sum(stock) FROM products) AS stk,
  (SELECT count(*) FROM sales) AS n_sales, (SELECT max(invoice_no) FROM sales) AS inv;
SET ROLE authenticated;
SELECT factory_reset('RESET', 'all');
RESET ROLE;
SELECT t.eq((SELECT count(*) FROM sales), 0, 'factory reset clears sales in one transaction (#31)');
SELECT t.eq((SELECT count(*) FROM accounts), 2, 'factory reset re-seeds the two accounts');
SET ROLE authenticated;
SELECT restore_backup((SELECT d FROM snap), 'RESTORE');
RESET ROLE;
SELECT t.eq((SELECT sum(balance) FROM accounts), (SELECT bal FROM before), 'restore brings balances back (#31)');
SELECT t.eq((SELECT sum(stock) FROM products), (SELECT stk FROM before), 'restore brings stock back');
SELECT t.eq((SELECT count(*) FROM sales), (SELECT n_sales FROM before), 'restore brings sales back');
SET ROLE authenticated;
INSERT INTO sales (items, total_amount, final_amount) VALUES
  ('[{"product_id":"10000000-0000-0000-0000-000000000003","name":"Biscuit","qty":1,"price":10,"total":10}]', 10, 10);
RESET ROLE;
SELECT t.ok((SELECT max(invoice_no) FROM sales) > (SELECT inv FROM before), 'invoice numbers continue after restore');
SELECT t.ok((SELECT balance_check FROM get_balance_sheet()), 'books still balance after restore + new sale');

-- duplicate account merge keeps signed balances and history (#20)
INSERT INTO accounts (id, name, account_type, balance, created_at) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'Cash 2', 'cash', -25, now() + interval '1 hour');
INSERT INTO account_transactions (account_id, type, amount, category, source) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'out', 5, 'other', 'manual');
CREATE TEMP TABLE b2 AS SELECT sum(balance) AS s, (SELECT count(*) FROM account_transactions) AS n FROM accounts WHERE account_type='cash';
SET ROLE authenticated;
SELECT t.eq(merge_duplicate_accounts(), 1, 'one duplicate merged');
RESET ROLE;
SELECT t.eq((SELECT sum(balance) FROM accounts WHERE account_type='cash'), (SELECT s FROM b2), 'merge keeps the signed total');
SELECT t.eq((SELECT count(*) FROM account_transactions), (SELECT n FROM b2), 'merge keeps every journal row');

-- a wrong PC clock cannot misdate a bill (2026_10_sale_time_guard.sql)
SET ROLE authenticated;
INSERT INTO sales (id, items, total_amount, final_amount, created_at) VALUES
  ('50000000-0000-0000-0000-0000000000f1', '[{"product_id":"10000000-0000-0000-0000-000000000003","name":"Biscuit","qty":1,"price":10,"total":10}]', 10, 10, now() + interval '2 days'),
  ('50000000-0000-0000-0000-0000000000f2', '[{"product_id":"10000000-0000-0000-0000-000000000003","name":"Biscuit","qty":1,"price":10,"total":10}]', 10, 10, now() - interval '400 days'),
  ('50000000-0000-0000-0000-0000000000f3', '[{"product_id":"10000000-0000-0000-0000-000000000003","name":"Biscuit","qty":1,"price":10,"total":10}]', 10, 10, now() - interval '2 days');
RESET ROLE;
SELECT t.ok((SELECT created_at FROM sales WHERE id='50000000-0000-0000-0000-0000000000f1') <= now() + interval '1 minute', 'a bill dated in the future gets the server time');
SELECT t.ok((SELECT created_at FROM sales WHERE id='50000000-0000-0000-0000-0000000000f2') > now() - interval '1 day', 'a bill dated over a year back (reset PC clock) gets the server time');
SELECT t.ok((SELECT created_at FROM sales WHERE id='50000000-0000-0000-0000-0000000000f3') < now() - interval '1 day', 'an offline bill from 2 days ago keeps its time');
SELECT set_config('app.bulk_mode', 'on', false);   -- what restore_backup does
INSERT INTO sales (id, items, total_amount, final_amount, created_at) VALUES
  ('50000000-0000-0000-0000-0000000000f4', '[]', 10, 10, now() - interval '400 days');
SELECT set_config('app.bulk_mode', 'off', false);
SELECT t.ok((SELECT created_at FROM sales WHERE id='50000000-0000-0000-0000-0000000000f4') < now() - interval '399 days', 'a restore keeps old bills on their own dates');

-- loose goods by weight: buy 2.5 kg, sell 1.5 kg, return 0.5 kg (decimal purchases/returns)
SET ROLE authenticated;
INSERT INTO products (id, name, purchase_price, selling_price, stock, unit, unit_type, gst_rate) VALUES
  ('10000000-0000-0000-0000-0000000000d1', 'Toor Dal loose', 0, 140, 0, 'kg', 'pieces', 0);
INSERT INTO purchases (id, supplier_id, supplier_name, items, total_amount, payment_method)
VALUES ('40000000-0000-0000-0000-0000000000d1', '20000000-0000-0000-0000-000000000001', 'Agency',
  '[{"product_id":"10000000-0000-0000-0000-0000000000d1","name":"Toor Dal loose","qty":2.5,"price":120}]', 300, 'cash');
INSERT INTO sales (id, items, total_amount, final_amount, payment_method)
VALUES ('50000000-0000-0000-0000-0000000000d1',
  '[{"product_id":"10000000-0000-0000-0000-0000000000d1","name":"Toor Dal loose","qty":1.5,"price":140,"total":210}]', 210, 210, 'cash');
RESET ROLE;
SELECT t.eq(t.stock('Toor Dal loose'), 1.0, 'decimal purchase 2.5 kg - sale 1.5 kg leaves 1 kg');
SELECT t.eq(t.batches('Toor Dal loose'), 1.0, 'batches follow the decimal sale');
SET ROLE authenticated;
SELECT (create_return_atomic('60000000-0000-0000-0000-0000000000d1','10000000-0000-0000-0000-0000000000d1',
   '50000000-0000-0000-0000-0000000000d1','Toor Dal loose',0.5)).return_amount AS dal_ret \gset
RESET ROLE;
SELECT t.eq(:'dal_ret', 70, 'returning 0.5 kg refunds half a kilo');
SELECT t.eq(t.stock('Toor Dal loose'), 1.5, 'the returned 0.5 kg is back in stock');
SET ROLE authenticated;
SELECT t.fails($$SELECT create_return_atomic('60000000-0000-0000-0000-0000000000d2','10000000-0000-0000-0000-0000000000d1',
   '50000000-0000-0000-0000-0000000000d1','Toor Dal loose',1.25)$$, 'Cannot return', 'cannot return more than is left of the line (1 kg)');
RESET ROLE;

-- a supplier bill paid part cash, part UPI (2026_10_purchase_split.sql)
CREATE TEMP TABLE sp0 AS SELECT t.bal('cash') AS c, t.bal('bank') AS b,
  (SELECT total_dues FROM suppliers WHERE name='Agency') AS d;
SET ROLE authenticated;
INSERT INTO purchases (id, supplier_id, supplier_name, items, total_amount, payment_method, cash_amount, digital_amount)
VALUES ('40000000-0000-0000-0000-0000000000e1', '20000000-0000-0000-0000-000000000001', 'Agency',
  '[{"product_id":"10000000-0000-0000-0000-000000000002","name":"Soap","qty":15,"price":20}]', 300, 'split', 100, 200);
RESET ROLE;
SELECT t.eq(t.bal('cash'), (SELECT c FROM sp0) - 100, 'split purchase: the cash part leaves the cash book');
SELECT t.eq(t.bal('bank'), (SELECT b FROM sp0) - 200, 'split purchase: the UPI part leaves the bank');
SELECT t.eq((SELECT digital_amount FROM purchases WHERE id='40000000-0000-0000-0000-0000000000e1'), 200, 'the UPI part is kept on the purchase');

-- part paid (cash 50 + UPI 100), the rest on credit
SET ROLE authenticated;
INSERT INTO purchases (id, supplier_id, supplier_name, items, total_amount, is_credit, amount_paid, payment_method, cash_amount, digital_amount)
VALUES ('40000000-0000-0000-0000-0000000000e2', '20000000-0000-0000-0000-000000000001', 'Agency',
  '[{"product_id":"10000000-0000-0000-0000-000000000002","name":"Soap","qty":20,"price":20}]', 400, true, 150, 'split', 50, 100);
RESET ROLE;
SELECT t.eq(t.bal('cash'), (SELECT c FROM sp0) - 150, 'credit purchase paid part cash: cash book');
SELECT t.eq(t.bal('bank'), (SELECT b FROM sp0) - 300, 'credit purchase paid part UPI: bank');
SELECT t.eq((SELECT total_dues FROM suppliers WHERE name='Agency'), (SELECT d FROM sp0) + 250, 'the unpaid 250 is owed to the supplier');

-- UPI typed bigger than the bill is capped; editing without amounts (older app) = not a split
SET ROLE authenticated;
INSERT INTO purchases (id, supplier_id, supplier_name, items, total_amount, payment_method, cash_amount, digital_amount)
VALUES ('40000000-0000-0000-0000-0000000000e3', '20000000-0000-0000-0000-000000000001', 'Agency',
  '[{"product_id":"10000000-0000-0000-0000-000000000002","name":"Soap","qty":5,"price":20}]', 100, 'split', 0, 999);
RESET ROLE;
SELECT t.eq((SELECT digital_amount FROM purchases WHERE id='40000000-0000-0000-0000-0000000000e3'), 100, 'UPI part never more than the bill');
SELECT t.eq(t.bal('bank'), (SELECT b FROM sp0) - 400, 'capped UPI part leaves the bank');
SET ROLE authenticated;
SELECT edit_purchase_atomic('40000000-0000-0000-0000-0000000000e3',
  '[{"product_id":"10000000-0000-0000-0000-000000000002","name":"Soap","qty":5,"price":20}]'::jsonb,
  100, '20000000-0000-0000-0000-000000000001', 'Agency', false, 100, 0, 'cash', 'paid cash after all');
RESET ROLE;
SELECT t.eq(t.bal('bank'), (SELECT b FROM sp0) - 300, 'edit to plain cash gives the UPI part back to the bank');
SELECT t.eq(t.bal('cash'), (SELECT c FROM sp0) - 250, '… and takes it from cash');

-- edit a purchase after part of its stock was sold (2026_10_purchase_split.sql, 14 Oct update)
SET ROLE authenticated;
INSERT INTO products (id, name, purchase_price, selling_price, stock, unit, unit_type, gst_rate) VALUES
  ('10000000-0000-0000-0000-0000000000a1', 'Edit Oil', 0, 30, 0, 'pcs', 'pieces', 0),
  ('10000000-0000-0000-0000-0000000000a2', 'Edit Soap', 0, 12, 0, 'pcs', 'pieces', 0);
INSERT INTO purchases (id, supplier_id, supplier_name, items, total_amount, payment_method)
VALUES ('40000000-0000-0000-0000-0000000000a1', '20000000-0000-0000-0000-000000000001', 'Agency',
  '[{"product_id":"10000000-0000-0000-0000-0000000000a1","name":"Edit Oil","qty":10,"price":20}]', 200, 'cash');
INSERT INTO sales (id, items, total_amount, final_amount, payment_method)
VALUES ('50000000-0000-0000-0000-0000000000a1',
  '[{"product_id":"10000000-0000-0000-0000-0000000000a1","name":"Edit Oil","qty":4,"price":30,"total":120}]', 120, 120, 'cash');
RESET ROLE;
SELECT t.eq(t.stock('Edit Oil'), 6, 'purchase 10, sold 4');

-- add a forgotten item and raise the qty: allowed although 4 were sold
SET ROLE authenticated;
SELECT edit_purchase_atomic('40000000-0000-0000-0000-0000000000a1',
  '[{"product_id":"10000000-0000-0000-0000-0000000000a1","name":"Edit Oil","qty":12,"price":20},
    {"product_id":"10000000-0000-0000-0000-0000000000a2","name":"Edit Soap","qty":5,"price":8}]'::jsonb,
  280, '20000000-0000-0000-0000-000000000001', 'Agency', false, 280, 0, 'cash', 'forgot the soap, oil was 12');
RESET ROLE;
SELECT t.eq(t.stock('Edit Oil'), 8, 'edit after a sale: 12 bought - 4 sold = 8 (was refused before)');
SELECT t.eq(t.batches('Edit Oil'), 8, 'oil batch follows: 8 unsold');
SELECT t.eq(t.stock('Edit Soap'), 5, 'the added item comes into stock');
SELECT t.eq(t.batches('Edit Soap'), 5, 'the added item gets its batch');
SELECT t.eq((SELECT count(*) FROM inventory_batches WHERE purchase_id = '40000000-0000-0000-0000-0000000000a1'), 2,
  'one batch per product, no duplicates');

-- cannot go below what was sold; can go down to it, with a new price
SET ROLE authenticated;
SELECT t.fails($$SELECT edit_purchase_atomic('40000000-0000-0000-0000-0000000000a1',
  '[{"product_id":"10000000-0000-0000-0000-0000000000a1","name":"Edit Oil","qty":3,"price":20}]'::jsonb,
  60, '20000000-0000-0000-0000-000000000001', 'Agency', false, 60, 0, 'cash', 'typo')$$,
  'already sold', 'a purchase cannot go below what is already sold');
SELECT t.fails($$SELECT edit_purchase_atomic('40000000-0000-0000-0000-0000000000a1',
  '[{"product_id":"10000000-0000-0000-0000-0000000000a2","name":"Edit Soap","qty":5,"price":8}]'::jsonb,
  40, '20000000-0000-0000-0000-000000000001', 'Agency', false, 40, 0, 'cash', 'drop the oil')$$,
  'already sold', 'a sold item cannot be removed from the purchase');
SELECT edit_purchase_atomic('40000000-0000-0000-0000-0000000000a1',
  '[{"product_id":"10000000-0000-0000-0000-0000000000a1","name":"Edit Oil","qty":4,"price":25},
    {"product_id":"10000000-0000-0000-0000-0000000000a2","name":"Edit Soap","qty":5,"price":8}]'::jsonb,
  140, '20000000-0000-0000-0000-000000000001', 'Agency', false, 140, 0, 'cash', 'only 4 oil, at 25');
RESET ROLE;
SELECT t.eq(t.stock('Edit Oil'), 0, 'down to exactly what was sold');
SELECT t.eq((SELECT purchase_price FROM products WHERE name = 'Edit Oil'), 25, 'new price becomes the cost price');

-- remove an unsold item: allowed
SET ROLE authenticated;
SELECT edit_purchase_atomic('40000000-0000-0000-0000-0000000000a1',
  '[{"product_id":"10000000-0000-0000-0000-0000000000a1","name":"Edit Oil","qty":4,"price":25}]'::jsonb,
  100, '20000000-0000-0000-0000-000000000001', 'Agency', false, 100, 0, 'cash', 'soap was not delivered');
-- the whole purchase still cannot be deleted once sold
SELECT t.fails($$SELECT delete_purchase_atomic('40000000-0000-0000-0000-0000000000a1')$$,
  'already been sold', 'a purchase whose stock was sold cannot be deleted');
RESET ROLE;
SELECT t.eq(t.stock('Edit Soap'), 0, 'removed unsold item leaves stock');
SELECT t.eq(t.batches('Edit Soap'), 0, '… and its batch is gone');

-- a split purchase paid more later, then edited: the later payment stays paid
CREATE TEMP TABLE sp1 AS SELECT t.bal('cash') AS c, t.bal('bank') AS b;
SET ROLE authenticated;
INSERT INTO purchases (id, supplier_id, supplier_name, items, total_amount, is_credit, amount_paid, payment_method, cash_amount, digital_amount)
VALUES ('40000000-0000-0000-0000-0000000000a3', '20000000-0000-0000-0000-000000000001', 'Agency',
  '[{"product_id":"10000000-0000-0000-0000-0000000000a2","name":"Edit Soap","qty":10,"price":10}]', 100, true, 30, 'split', 10, 20);
INSERT INTO supplier_payments (supplier_id, purchase_id, amount, payment_method)
VALUES ('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-0000000000a3', 25, 'cash');
SELECT edit_purchase_atomic('40000000-0000-0000-0000-0000000000a3',
  '[{"product_id":"10000000-0000-0000-0000-0000000000a2","name":"Edit Soap","qty":10,"price":10}]'::jsonb,
  100, '20000000-0000-0000-0000-000000000001', 'Agency', true, 30, 70, 'split', 'note only', NULL, 10, 20);
RESET ROLE;
SELECT t.eq((SELECT amount_paid FROM purchases WHERE id = '40000000-0000-0000-0000-0000000000a3'), 55,
  'split 30 at purchase + 25 paid later stays 55 after an edit');
SELECT t.eq((SELECT due_amount FROM purchases WHERE id = '40000000-0000-0000-0000-0000000000a3'), 45, 'still 45 due');
SELECT t.eq(t.bal('cash'), (SELECT c FROM sp1) - 10 - 25, 'cash: 10 at purchase + 25 later, unchanged by the edit');
SELECT t.eq(t.bal('bank'), (SELECT b FROM sp1) - 20, 'bank: 20 at purchase, unchanged by the edit');

-- ===================================================== negative stock (2026_10_stock_negative.sql)
-- goods sold before their purchase bill is entered: stock goes below zero,
-- the purchase adds on top, nothing is counted twice
SET ROLE authenticated;
INSERT INTO products (id, name, purchase_price, selling_price, stock, unit, unit_type, gst_rate) VALUES
  ('10000000-0000-0000-0000-0000000001f1', 'Neg Zero', 8, 10, 0, 'pcs', 'pieces', 0),
  ('10000000-0000-0000-0000-0000000001f2', 'Neg Five', 8, 10, 0, 'pcs', 'pieces', 0),
  ('10000000-0000-0000-0000-0000000001f3', 'Neg Many', 8, 10, 0, 'pcs', 'pieces', 0),
  ('10000000-0000-0000-0000-0000000001f4', 'Neg Plus', 8, 10, 0, 'pcs', 'pieces', 0),
  ('10000000-0000-0000-0000-0000000001f5', 'Neg Cancel', 8, 10, 0, 'pcs', 'pieces', 0),
  ('10000000-0000-0000-0000-0000000001f6', 'Neg Edit', 8, 10, 0, 'pcs', 'pieces', 0),
  ('10000000-0000-0000-0000-0000000001f7', 'Neg Count', 8, 10, 0, 'pcs', 'pieces', 0);

-- 1. stock 0, sell 12, then purchase 100 -> 88
INSERT INTO sales (id, items, total_amount, final_amount, payment_method) VALUES ('50000000-0000-0000-0000-0000000001f1',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f1","name":"Neg Zero","qty":12,"price":10,"total":120}]', 120, 120, 'cash');
RESET ROLE;
SELECT t.eq(t.stock('Neg Zero'), -12, 'sold 12 at 0 stock: -12 (was clamped to 0)');
SELECT t.eq(t.batches('Neg Zero'), 0, '... no batch goes below zero');
SELECT t.eq((SELECT public.jnum(items->0, 'oversold_qty', 0) FROM sales WHERE id='50000000-0000-0000-0000-0000000001f1'), 12,
  '... the line notes the 12 not on hand');
SET ROLE authenticated;
INSERT INTO purchases (id, supplier_name, items, total_amount, payment_method) VALUES ('40000000-0000-0000-0000-0000000001f1', 'Agency',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f1","name":"Neg Zero","qty":100,"price":8}]', 800, 'cash');
RESET ROLE;
SELECT t.eq(t.stock('Neg Zero'), 88, 'then purchase 100: -12 + 100 = 88');
SELECT t.eq(t.batches('Neg Zero'), 88, '... batches 88: the 12 sold are not deducted twice');
SELECT t.eq((SELECT quantity FROM inventory_batches WHERE purchase_id='40000000-0000-0000-0000-0000000001f1'), 100,
  '... the purchase keeps its real quantity (100)');

-- 2. stock 5, sell 8, then purchase 100 -> 97
SET ROLE authenticated;
INSERT INTO purchases (id, supplier_name, items, total_amount, payment_method) VALUES ('40000000-0000-0000-0000-0000000001f2', 'Agency',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f2","name":"Neg Five","qty":5,"price":8}]', 40, 'cash');
INSERT INTO sales (id, items, total_amount, final_amount, payment_method) VALUES ('50000000-0000-0000-0000-0000000001f2',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f2","name":"Neg Five","qty":8,"price":10,"total":80}]', 80, 80, 'cash');
RESET ROLE;
SELECT t.eq(t.stock('Neg Five'), -3, 'stock 5, sold 8: -3');
SELECT t.eq((SELECT public.jnum(items->0, 'oversold_qty', 0) FROM sales WHERE id='50000000-0000-0000-0000-0000000001f2'), 3,
  '... 3 were not on hand');
SET ROLE authenticated;
INSERT INTO purchases (id, supplier_name, items, total_amount, payment_method) VALUES ('40000000-0000-0000-0000-0000000001f3', 'Agency',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f2","name":"Neg Five","qty":100,"price":9}]', 900, 'cash');
RESET ROLE;
SELECT t.eq(t.stock('Neg Five'), 97, 'then purchase 100: 97');
SELECT t.eq(t.batches('Neg Five'), 97, '... batches 97');

-- 3. several sales below zero, then one purchase
SET ROLE authenticated;
INSERT INTO sales (id, items, total_amount, final_amount, payment_method) VALUES
  ('50000000-0000-0000-0000-0000000001f3', '[{"product_id":"10000000-0000-0000-0000-0000000001f3","name":"Neg Many","qty":5,"price":10,"total":50}]', 50, 50, 'cash'),
  ('50000000-0000-0000-0000-0000000001f4', '[{"product_id":"10000000-0000-0000-0000-0000000001f3","name":"Neg Many","qty":4,"price":10,"total":40}]', 40, 40, 'cash'),
  ('50000000-0000-0000-0000-0000000001f5', '[{"product_id":"10000000-0000-0000-0000-0000000001f3","name":"Neg Many","qty":3,"price":10,"total":30}]', 30, 30, 'cash');
RESET ROLE;
SELECT t.eq(t.stock('Neg Many'), -12, 'sales of 5, 4 and 3 at 0 stock: -12');
SET ROLE authenticated;
INSERT INTO purchases (id, supplier_name, items, total_amount, payment_method) VALUES ('40000000-0000-0000-0000-0000000001f4', 'Agency',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f3","name":"Neg Many","qty":100,"price":8}]', 800, 'cash');
RESET ROLE;
SELECT t.eq(t.stock('Neg Many'), 88, 'then purchase 100: 88, every sale counted once');
SELECT t.eq(t.batches('Neg Many'), 88, '... batches 88');

-- 4. purchase when the stock is already positive
SET ROLE authenticated;
INSERT INTO purchases (id, supplier_name, items, total_amount, payment_method) VALUES
  ('40000000-0000-0000-0000-0000000001f5', 'Agency', '[{"product_id":"10000000-0000-0000-0000-0000000001f4","name":"Neg Plus","qty":10,"price":8}]', 80, 'cash'),
  ('40000000-0000-0000-0000-0000000001f6', 'Agency', '[{"product_id":"10000000-0000-0000-0000-0000000001f4","name":"Neg Plus","qty":20,"price":8}]', 160, 'cash');
RESET ROLE;
SELECT t.eq(t.stock('Neg Plus'), 30, 'positive stock: 10 + 20 = 30');
SELECT t.eq(t.batches('Neg Plus'), 30, '... batches 30');

-- 5. cancel (delete) a bill: while below zero, and after the purchase came
SET ROLE authenticated;
INSERT INTO sales (id, items, total_amount, final_amount, payment_method) VALUES ('50000000-0000-0000-0000-0000000001f6',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f5","name":"Neg Cancel","qty":6,"price":10,"total":60}]', 60, 60, 'cash');
SELECT delete_sale_atomic('50000000-0000-0000-0000-0000000001f6');
RESET ROLE;
SELECT t.eq(t.stock('Neg Cancel'), 0, 'sold 6 at 0 (-6), bill deleted: back to 0');
SELECT t.eq(t.batches('Neg Cancel'), 0, '... no phantom batch left');
SET ROLE authenticated;
SELECT delete_sale_atomic('50000000-0000-0000-0000-0000000001f1');
RESET ROLE;
SELECT t.eq(t.stock('Neg Zero'), 100, 'the 12 sold before the purchase, deleted later: 88 + 12 = 100');
SELECT t.eq(t.batches('Neg Zero'), 100, '... batches 100');

-- 6. sales return: after the purchase, and while still below zero
SET ROLE authenticated;
SELECT (create_return_atomic('60000000-0000-0000-0000-0000000001f1','10000000-0000-0000-0000-0000000001f3',
   '50000000-0000-0000-0000-0000000001f5','Neg Many',3)).quantity AS nr1 \gset
INSERT INTO sales (id, items, total_amount, final_amount, payment_method) VALUES ('50000000-0000-0000-0000-0000000001f7',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f5","name":"Neg Cancel","qty":10,"price":10,"total":100}]', 100, 100, 'cash');
SELECT (create_return_atomic('60000000-0000-0000-0000-0000000001f2','10000000-0000-0000-0000-0000000001f5',
   '50000000-0000-0000-0000-0000000001f7','Neg Cancel',4)).quantity AS nr2 \gset
RESET ROLE;
SELECT t.eq(t.stock('Neg Many'), 91, 'return 3 after the purchase: 88 + 3 = 91');
SELECT t.eq(t.batches('Neg Many'), 91, '... batches 91');
SELECT t.eq(t.stock('Neg Cancel'), -6, 'sold 10 at 0, 4 returned: -6');
SELECT t.eq(t.batches('Neg Cancel'), 0, '... still no batch');

-- 7. purchase edited / taken back: bought 3 while at -5, edited to 10
SET ROLE authenticated;
INSERT INTO sales (id, items, total_amount, final_amount, payment_method) VALUES ('50000000-0000-0000-0000-0000000001f8',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f6","name":"Neg Edit","qty":5,"price":10,"total":50}]', 50, 50, 'cash');
INSERT INTO purchases (id, supplier_id, supplier_name, items, total_amount, payment_method) VALUES ('40000000-0000-0000-0000-0000000001f7',
  '20000000-0000-0000-0000-000000000001', 'Agency', '[{"product_id":"10000000-0000-0000-0000-0000000001f6","name":"Neg Edit","qty":3,"price":8}]', 24, 'cash');
RESET ROLE;
SELECT t.eq(t.stock('Neg Edit'), -2, 'sold 5 at 0, bought 3: -2');
SELECT t.eq(t.batches('Neg Edit'), 0, '... all 3 went to what was sold');
SET ROLE authenticated;
SELECT edit_purchase_atomic('40000000-0000-0000-0000-0000000001f7',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f6","name":"Neg Edit","qty":10,"price":8}]'::jsonb,
  80, '20000000-0000-0000-0000-000000000001', 'Agency', false, 80, 0, 'cash', 'bill said 10');
RESET ROLE;
SELECT t.eq(t.stock('Neg Edit'), 5, 'purchase edited 3 -> 10: -2 + 7 = 5');
SELECT t.eq(t.batches('Neg Edit'), 5, '... batches 5');
SET ROLE authenticated;
SELECT t.fails($$SELECT edit_purchase_atomic('40000000-0000-0000-0000-0000000001f7',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f6","name":"Neg Edit","qty":2,"price":8}]'::jsonb,
  16, '20000000-0000-0000-0000-000000000001', 'Agency', false, 16, 0, 'cash', 'typo')$$,
  'already sold', 'a purchase cannot go below what was sold from it');
SELECT delete_purchase_atomic('40000000-0000-0000-0000-0000000001f6');
RESET ROLE;
SELECT t.eq(t.stock('Neg Plus'), 10, 'unsold purchase deleted: 30 - 20 = 10');

-- 8. retry: the same bill sent twice is applied once
SET ROLE authenticated;
SELECT t.fails($$INSERT INTO sales (id, items, total_amount, final_amount, payment_method) VALUES ('50000000-0000-0000-0000-0000000001f8',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f6","name":"Neg Edit","qty":5,"price":10,"total":50}]', 50, 50, 'cash')$$,
  'duplicate', 'a retried bill is refused');
SELECT t.fails($$INSERT INTO purchases (id, supplier_name, items, total_amount, payment_method) VALUES ('40000000-0000-0000-0000-0000000001f1', 'Agency',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f1","name":"Neg Zero","qty":100,"price":8}]', 800, 'cash')$$,
  'duplicate', 'a retried purchase is refused');
RESET ROLE;
SELECT t.eq(t.stock('Neg Edit'), 5, '... stock unchanged by the retries');
SELECT t.eq(t.stock('Neg Zero'), 100, '... purchase stock unchanged too');

-- Stock In, physical count, Stock Out and damaged while below zero
SET ROLE authenticated;
INSERT INTO sales (id, items, total_amount, final_amount, payment_method) VALUES ('50000000-0000-0000-0000-0000000001f9',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f7","name":"Neg Count","qty":12,"price":10,"total":120}]', 120, 120, 'cash');
SELECT adjust_stock('10000000-0000-0000-0000-0000000001f7', 5);
RESET ROLE;
SELECT t.eq(t.stock('Neg Count'), -7, 'Stock In 5 at -12: -7');
SELECT t.eq(t.batches('Neg Count'), 0, '... covers what was sold, no batch');
SET ROLE authenticated;
SELECT t.fails($$SELECT adjust_stock('10000000-0000-0000-0000-0000000001f7', -1)$$, 'cannot remove', 'Stock Out below zero is still refused');
SELECT t.fails($$SELECT create_damaged_atomic(gen_random_uuid(), '10000000-0000-0000-0000-0000000001f7', 'Neg Count', 1)$$,
  'Insufficient', 'damaged below zero is still refused');
SELECT reconcile_stock_with_batches('10000000-0000-0000-0000-0000000001f7', 20);
RESET ROLE;
SELECT t.eq(t.stock('Neg Count'), 20, 'physical count of 20 at -7: 20');
SELECT t.eq(t.batches('Neg Count'), 20, '... batches 20');

-- 10. reports: a negative stock adds nothing to stock value
SET ROLE authenticated;
INSERT INTO sales (id, items, total_amount, final_amount, payment_method) VALUES ('50000000-0000-0000-0000-0000000001fa',
  '[{"product_id":"10000000-0000-0000-0000-0000000001f5","name":"Neg Cancel","qty":1,"price":10,"total":10}]', 10, 10, 'cash');
RESET ROLE;
SELECT t.eq(t.stock('Neg Cancel'), -7, 'Neg Cancel at -7');
SELECT t.eq((SELECT sum(coalesce(b.val, 0) + greatest(p.stock - coalesce(b.qty, 0), 0) * p.purchase_price)
             FROM products p LEFT JOIN (SELECT product_id, sum(remaining) qty, sum(remaining * purchase_price) val
                                        FROM inventory_batches GROUP BY 1) b ON b.product_id = p.id
             WHERE p.name = 'Neg Cancel'), 0, 'stock value of a negative stock is 0, not negative');
SELECT t.ok(NOT EXISTS (SELECT 1 FROM products p
                        WHERE p.stock >= 0 AND p.name LIKE 'Neg %'
                          AND abs(p.stock - coalesce((SELECT sum(remaining) FROM inventory_batches b WHERE b.product_id = p.id), 0)) > 0.001),
  'batches equal the stock for every product that is not below zero');

\echo ALL SCENARIO TESTS PASSED
