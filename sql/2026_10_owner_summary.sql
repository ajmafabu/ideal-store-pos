-- =====================================================================
-- 2026_10_owner_summary.sql — read-only owner summary for IdealCash
-- (owner, 19 Oct 2026)
--
-- The owner's personal finance app (IdealCash) shows Ideal Store next to
-- the owner's other money. It needs the shop's headline figures, and
-- nothing else:
--   * today, this month, last month and this financial year:
--     sales, GST-free revenue, cost of goods, gross profit, expenses,
--     net profit, bills;
--   * position now: cash, bank, stock value, customer dues, supplier
--     dues, GST payable;
--   * a few health checks for the owner (balance sheet balanced, cash
--     account below zero, products below zero stock, customer dues over
--     90 days).
--
-- One new function, get_owner_summary(), returns all of it as JSON.
-- Every figure comes from the SAME definitions the shop app uses
-- (period_figures, get_stock_value, the balance-sheet figures), so the
-- two apps can never disagree.
--
-- Who may call it:
--   * an active admin (you, in the shop app), or
--   * a "viewer" login listed in the new table owner_viewers.
--     A viewer must NOT be an active shop member: the login IdealCash
--     uses can read this one summary and nothing else. It cannot bill,
--     see products, customers or any other shop data, or change anything.
--
-- Also changed (same result, no data touched):
--   get_balance_sheet() now reads its figures from the new internal
--   balance_sheet_figures(), so the summary and the Balance Sheet screen
--   use one definition. Only admins can still call get_balance_sheet().
--
-- Nothing is deleted and no stored figure is rewritten.
-- If 2026_10_audit_fixes.sql is ever run again, run this file again
-- afterwards (that file resets every function permission).
--
-- Idempotent; one transaction. Apply in Supabase -> SQL Editor:
--   back up, run verify_schema.sql, run this file, run verify_schema.sql.
-- Then create the viewer login (steps at the end of this file).
-- =====================================================================
BEGIN;

-- 1. viewer logins allowed to read the owner summary
CREATE TABLE IF NOT EXISTS public.owner_viewers (
  user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  note       text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.owner_viewers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS owner_viewers_admin ON public.owner_viewers;
CREATE POLICY owner_viewers_admin ON public.owner_viewers FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
REVOKE ALL ON public.owner_viewers FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.owner_viewers TO authenticated;

-- listed as a viewer AND not an active shop member (a staff account
-- added here by mistake must not start seeing profit)
CREATE OR REPLACE FUNCTION public.is_owner_viewer() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT auth.uid() IS NOT NULL
     AND EXISTS (SELECT 1 FROM owner_viewers WHERE user_id = auth.uid())
     AND NOT public.is_active_member()
$$;
REVOKE EXECUTE ON FUNCTION public.is_owner_viewer() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_owner_viewer() TO authenticated;

-- 2. balance-sheet figures: ONE definition for the screen and the summary
--    (body moved unchanged from get_balance_sheet; no permission check
--    here, so it is callable by no one directly)
CREATE OR REPLACE FUNCTION public.balance_sheet_figures()
RETURNS TABLE (cash_in_hand numeric, bank_balance numeric, inventory_value numeric, total_receivables numeric,
               total_assets numeric, total_payables numeric, credit_purchase_dues numeric, gst_payable numeric,
               total_liabilities numeric, owner_capital numeric, retained_earnings numeric, total_equity numeric,
               difference numeric, balance_check boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  v_cash numeric; v_bank numeric; v_inv numeric; v_ar numeric; v_ap numeric; v_gst numeric;
  v_capital numeric; v_re numeric; v_assets numeric; v_liab numeric; v_unbatched numeric;
BEGIN
  SELECT coalesce(sum(balance) FILTER (WHERE account_type = 'cash'), 0),
         coalesce(sum(balance) FILTER (WHERE account_type <> 'cash'), 0)
    INTO v_cash, v_bank FROM accounts;
  v_inv := public.get_stock_value();
  SELECT coalesce(sum(due_amount), 0) INTO v_ar FROM sales WHERE due_amount > 0;
  SELECT coalesce(sum(due_amount), 0) INTO v_ap FROM purchases WHERE due_amount > 0;
  -- GST collected − input credit − tax on returns − GST already paid
  SELECT coalesce(sum(coalesce(cgst_amount,0)+coalesce(sgst_amount,0)+coalesce(igst_amount,0)), 0)
       - coalesce((SELECT sum(coalesce(cgst_amount,0)+coalesce(sgst_amount,0)+coalesce(igst_amount,0)) FROM purchases), 0)
       - coalesce((SELECT sum(tax_amount) FROM product_returns), 0)
       - coalesce((SELECT sum(amount) FROM expenses WHERE public.is_tax_payment_category(category)), 0)
    INTO v_gst FROM sales;
  SELECT f.net_profit INTO v_re FROM public.period_figures(NULL, NULL) f;

  -- recorded capital: opening balances of the money accounts, manual
  -- capital/drawing/other entries, and opening stock with no purchase record
  SELECT coalesce(sum(a.balance - coalesce(j.net, 0)), 0) INTO v_capital
  FROM accounts a
  LEFT JOIN (SELECT account_id, sum(CASE WHEN type='in' THEN amount ELSE -amount END) AS net
             FROM account_transactions GROUP BY account_id) j ON j.account_id = a.id;
  v_capital := v_capital + coalesce((
    SELECT sum(CASE WHEN type='in' THEN amount ELSE -amount END) FROM account_transactions
    WHERE ref_type IS NULL AND coalesce(source,'manual') = 'manual' AND category <> 'transfer'), 0);
  SELECT coalesce(sum(greatest(p.stock - coalesce(b.qty, 0), 0) * coalesce(p.purchase_price, 0)), 0) INTO v_unbatched
  FROM products p LEFT JOIN (SELECT product_id, sum(remaining) AS qty FROM inventory_batches GROUP BY product_id) b
    ON b.product_id = p.id
  WHERE NOT coalesce(p.has_variants, false);
  v_capital := v_capital + v_unbatched;

  v_assets := v_cash + v_bank + v_inv + v_ar;
  v_liab := v_ap + greatest(v_gst, 0);
  RETURN QUERY SELECT v_cash, v_bank, v_inv, v_ar, v_assets, v_ap, v_ap, greatest(v_gst, 0), v_liab,
                      v_capital, v_re, v_capital + v_re,
                      round(v_assets - v_liab - v_capital - v_re, 2),
                      abs(v_assets - v_liab - v_capital - v_re) < 1;
END $$;
REVOKE EXECUTE ON FUNCTION public.balance_sheet_figures() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_balance_sheet()
RETURNS TABLE (cash_in_hand numeric, bank_balance numeric, inventory_value numeric, total_receivables numeric,
               total_assets numeric, total_payables numeric, credit_purchase_dues numeric, gst_payable numeric,
               total_liabilities numeric, owner_capital numeric, retained_earnings numeric, total_equity numeric,
               difference numeric, balance_check boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_admin();
  RETURN QUERY SELECT * FROM public.balance_sheet_figures();
END $$;
REVOKE EXECUTE ON FUNCTION public.get_balance_sheet() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_balance_sheet() TO authenticated;

-- 3. one period as JSON (internal)
CREATE OR REPLACE FUNCTION public.owner_period_json(p_start timestamptz, p_end timestamptz, p_from date, p_to date)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'from', p_from, 'to', p_to,
    'gross_sales', round(f.gross_sales, 2),          -- bill totals incl. GST
    'net_revenue', round(f.net_revenue, 2),          -- without GST and returns
    'cogs', round(f.net_cogs, 2),                    -- FIFO cost of goods sold
    'gross_profit', round(f.net_revenue - f.net_cogs, 2),
    'expenses', round(f.expenses, 2),                -- GST payments excluded
    'damaged', round(f.damaged_loss, 2),
    'net_profit', round(f.net_profit, 2),
    'returns', round(f.returns_amount, 2),
    'orders', f.orders)
  FROM public.period_figures(p_start, p_end) f
$$;
REVOKE EXECUTE ON FUNCTION public.owner_period_json(timestamptz, timestamptz, date, date) FROM PUBLIC, anon, authenticated;

-- 4. the summary IdealCash reads
CREATE OR REPLACE FUNCTION public.get_owner_summary() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_today date := public.ist_today();
  v_month date := date_trunc('month', v_today)::date;
  v_last  date := (v_month - interval '1 month')::date;
  -- Indian financial year starts on 1 April
  v_fy    date := make_date(CASE WHEN extract(month FROM v_today) >= 4
                                 THEN extract(year FROM v_today)::int
                                 ELSE extract(year FROM v_today)::int - 1 END, 4, 1);
  b record;
BEGIN
  IF NOT (auth.uid() IS NULL OR public.is_admin() OR public.is_owner_viewer()) THEN
    RAISE EXCEPTION 'Owner summary permission required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO b FROM public.balance_sheet_figures();

  RETURN jsonb_build_object(
    'version', 1,
    'generated_at', now(),
    'shop_name', (SELECT shop_name FROM shop_settings WHERE id = 1),
    'today',        public.owner_period_json(public.ist_day_start(v_today), public.ist_day_start(v_today + 1), v_today, v_today),
    'this_month',   public.owner_period_json(public.ist_day_start(v_month), public.ist_day_start(v_today + 1), v_month, v_today),
    'last_month',   public.owner_period_json(public.ist_day_start(v_last), public.ist_day_start(v_month), v_last, v_month - 1),
    'financial_year', public.owner_period_json(public.ist_day_start(v_fy), public.ist_day_start(v_today + 1), v_fy, v_today),
    'position', jsonb_build_object(
      'cash', round(b.cash_in_hand, 2),
      'bank', round(b.bank_balance, 2),
      'stock_value', round(b.inventory_value, 2),
      'receivables', round(b.total_receivables, 2),
      'payables', round(b.total_payables, 2),
      'gst_payable', round(b.gst_payable, 2),
      'total_assets', round(b.total_assets, 2),
      'total_liabilities', round(b.total_liabilities, 2),
      'net_worth', round(b.total_assets - b.total_liabilities, 2)),
    'checks', jsonb_build_object(
      'balance_sheet_balanced', b.balance_check,
      'balance_sheet_difference', b.difference,
      'accounts_below_zero', (SELECT coalesce(jsonb_agg(jsonb_build_object('name', name, 'balance', round(balance, 2))
                                                        ORDER BY balance), '[]'::jsonb)
                              FROM accounts WHERE balance < 0),
      'products_below_zero_stock', (SELECT count(*) FROM products
                                    WHERE NOT coalesce(has_variants, false) AND stock < 0),
      'receivables_over_90_days', (SELECT round(coalesce(sum(due_amount), 0), 2) FROM sales
                                   WHERE due_amount > 0
                                     AND v_today - coalesce(due_date::date, public.ist_date(created_at) + 30) > 90))
  );
END $$;
REVOKE EXECUTE ON FUNCTION public.get_owner_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_owner_summary() TO authenticated;

DO $$ BEGIN PERFORM public.record_migration('v102', '2026_10_owner_summary'); END $$;

COMMIT;

-- =====================================================================
-- After running this file: create the IdealCash viewer login (once)
--
-- 1. Supabase Dashboard -> Authentication -> Users -> Add user ->
--    Create new user. Use a NEW email (for example your own address with
--    +idealcash: you@gmail.com -> you+idealcash@gmail.com), a long
--    password, and tick "Auto Confirm User".
--    The app gives this login an INACTIVE staff profile: it sees no shop
--    data. Never activate it on the Staff screen.
-- 2. SQL Editor, replace the email and run:
--
--      INSERT INTO owner_viewers (user_id, note)
--      SELECT id, 'IdealCash phone app' FROM auth.users
--      WHERE email = 'you+idealcash@gmail.com'
--      ON CONFLICT (user_id) DO NOTHING;
--
-- 3. Enter that email and password in IdealCash -> Settings ->
--    Ideal Store connection.
--
-- To remove access later: DELETE FROM owner_viewers WHERE user_id = ...;
-- or delete the user in Authentication -> Users.
-- =====================================================================
