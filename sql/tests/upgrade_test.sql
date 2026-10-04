-- Runs AFTER legacy_seed.sql and the migration. Old documents must be
-- editable/deletable with the right cash and stock effects.
\i scenario_helpers.sql
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000aa',false);
SELECT set_config('request.jwt.claim.role','authenticated',false);
-- before: cash = 5000 -4500 +1000 -200 -700 +100 = 700 ; stock = 50 -10 -5 +2 = 37
SELECT t.eq(t.bal('cash'), 600, 'legacy cash balance kept');
SELECT t.eq(t.stock('Oil'), 37, 'legacy stock kept (now numeric)');
SELECT t.ok((SELECT role='admin' AND active FROM profiles WHERE id='00000000-0000-0000-0000-0000000000aa'), 'existing admin still admin');
SELECT t.eq((SELECT count(*) FROM legacy_postings), 7, 'old postings estimated (credit sale had none)');
SET ROLE authenticated;
-- delete legacy cash sale with a legacy return: -1000 sale, +200 refund back
SELECT delete_sale_atomic('e0000000-0000-0000-0000-000000000001');
RESET ROLE;
SELECT t.eq(t.stock('Oil'), 37 + 8, 'legacy sale delete restores only the unreturned 8');
SELECT t.eq(t.bal('cash'), 600 - 1000 + 200, 'legacy sale + refund reversed exactly once');
SET ROLE authenticated;
-- legacy credit sale: the old app never booked the 200, so deleting it must not take 200 out
SELECT delete_sale_atomic('e0000000-0000-0000-0000-000000000002');
RESET ROLE;
SELECT t.eq(t.bal('cash'), 600 - 1000 + 200 - 100, 'only the booked 100 collection is reversed');
SELECT t.eq((SELECT total_credit FROM customers WHERE name='Old Customer'), 0, 'credit cleared');
SET ROLE authenticated;
-- legacy expense edit: amount 700 -> 650 gives back 50 to cash
UPDATE expenses SET amount = 650 WHERE id = 'ee000000-0000-0000-0000-000000000001';
RESET ROLE;
SELECT t.eq(t.bal('cash'), 600 - 1000 + 200 - 100 + 50, 'legacy expense edit posts only the delta');
SET ROLE authenticated;
-- legacy "digital" purchase: old app paid it from cash; deleting refunds CASH; stock back out
-- both sales were deleted above, so the batch is whole again and the purchase may go
SELECT delete_purchase_atomic('d0000000-0000-0000-0000-000000000001');
RESET ROLE;
SELECT t.eq(t.stock('Oil'), 0, 'legacy purchase delete removes its stock');
SELECT t.eq(t.bal('cash'), 600 - 1000 + 200 - 100 + 50 + 4500, 'legacy "digital" purchase refunded to CASH, where the old app paid it from');
SELECT t.eq(t.bal('bank'), 0, 'bank untouched');
SELECT t.eq((SELECT sum(balance) FROM accounts) - 5000,
            (SELECT sum(CASE WHEN type='in' THEN amount ELSE -amount END) FROM account_transactions),
            'balances = opening 5000 + journal');
SET ROLE authenticated;
SELECT t.ok((SELECT abs(difference) < 0.1 FROM get_balance_sheet()), 'balance sheet balances after upgrade');
RESET ROLE;
SELECT t.eq(t.batches('Dal'), 3, 'phantom batch units trimmed to stock');
SELECT t.eq((SELECT sum(b.remaining * b.purchase_price) FROM inventory_batches b JOIN products p ON p.id = b.product_id WHERE p.name = 'Dal'), 240,
            'Dal stock valued at 3 x 80, not 10 x 80');
SELECT t.ok(EXISTS (SELECT 1 FROM stock_reconciliation r JOIN products p ON p.id = r.product_id WHERE p.name = 'Dal' AND r.system_qty = 10 AND r.physical_qty = 3),
            'trim logged in stock_reconciliation');
\echo ALL UPGRADE TESTS PASSED
