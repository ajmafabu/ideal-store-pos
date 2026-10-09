-- =====================================================================
-- verify_schema.sql — READ-ONLY health check of the live database (#1)
-- Run in the Supabase SQL editor before and after 2026_10_audit_fixes.sql.
-- Every row should say OK after the migration. Nothing is changed.
-- =====================================================================
WITH
req_cols(tbl, col) AS (VALUES
  ('sales','invoice_no'),('sales','paid_at_sale'),('sales','taxable_amount'),('sales','cgst_amount'),
  ('sales','sgst_amount'),('sales','igst_amount'),('sales','due_date'),('sales','extra_charges'),
  ('sales','round_off'),('sales','updated_at'),('sales','cash_amount'),('sales','digital_amount'),
  ('purchases','payment_method'),('purchases','round_off'),('purchases','paid_at_purchase'),
  ('purchases','taxable_amount'),('expenses','payment_method'),('customers','gstin'),
  ('customers','state_code'),('customers','credit_limit'),('customers','portal_token'),
  ('products','unit_type'),('products','pieces_per_unit'),('products','selling_price_2'),
  ('products','sfw'),('products','tamil_name'),('product_returns','original_sale_id'),
  ('product_returns','return_amount'),('product_returns','credit_adjusted'),('product_returns','refund_method'),
  ('product_returns','cost_amount'),('account_transactions','ref_type'),('account_transactions','ref_id'),
  ('account_transactions','source'),('audit_log','entity_type'),('purchase_orders','purchase_id'),
  ('shop_settings','state_code'),('legacy_postings','amount')),
req_funcs(sig) AS (VALUES
  ('delete_sale_atomic(uuid)'),('create_return_atomic(uuid,uuid,uuid,text,numeric,numeric,numeric,text,uuid,text)'),
  ('return_full_sale(uuid,text)'),('create_damaged_atomic(uuid,uuid,text,numeric,numeric,text,uuid)'),
  ('delete_purchase_atomic(uuid)'),('receive_purchase_order(uuid,boolean,numeric,text,jsonb)'),
  ('transfer_between_accounts(uuid,uuid,numeric,text,uuid)'),('get_account_summary(timestamp with time zone,timestamp with time zone,uuid)'),
  ('merge_duplicate_accounts()'),('get_balance_sheet()'),('get_cash_flow(timestamp with time zone,timestamp with time zone)'),
  ('get_gstr3b_summary(timestamp with time zone,timestamp with time zone)'),('get_reports_summary(timestamp with time zone,timestamp with time zone)'),
  ('get_inventory_health()'),('get_receivables_aging()'),('get_dashboard_summary()'),('restore_backup(jsonb,text)'),
  ('factory_reset(text,text)'),('admin_set_staff(uuid,text,text,boolean,text)'),('admin_delete_staff(uuid)'),
  ('get_customer_portal(uuid)'),('adjust_stock(uuid,numeric)'),('guard_product_stock()')),
checks AS (
  SELECT 1 AS ord, 'migration v100 recorded' AS check_name,
         CASE WHEN (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND (table_name, column_name) IN (('schema_migrations','version'))) = 1
                   AND (xpath('//v/text()', query_to_xml('SELECT count(*) AS v FROM public.schema_migrations WHERE version = ''v100''', false, true, '')))[1]::text::int > 0
              THEN 'OK' ELSE 'MISSING' END AS status,
         '2026_10_audit_fixes.sql applied' AS detail
  UNION ALL
  SELECT 2, 'required columns',
         CASE WHEN count(*) = 0 THEN 'OK' ELSE 'MISSING' END,
         coalesce(string_agg(tbl || '.' || col, ', '), 'all present')
  FROM req_cols r
  WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns c
                    WHERE c.table_schema = 'public' AND c.table_name = r.tbl AND c.column_name = r.col)
  UNION ALL
  SELECT 3, 'required functions',
         CASE WHEN count(*) = 0 THEN 'OK' ELSE 'MISSING' END,
         coalesce(string_agg(sig, ', '), 'all present')
  FROM req_funcs f
  WHERE NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
                    AND replace(p.oid::regprocedure::text, 'public.', '') = f.sig)
  UNION ALL
  SELECT 4, 'no duplicate overloads of report functions',
         CASE WHEN count(*) = 0 THEN 'OK' ELSE 'PROBLEM' END,
         coalesce(string_agg(proname || ' x' || n, ', '), 'one definition each')
  FROM (SELECT proname, count(*) n FROM pg_proc WHERE pronamespace = 'public'::regnamespace
          AND proname IN ('get_monthly_profit','get_category_sales','get_daily_sales_trend','get_monthly_sales_summary',
                          'add_inventory_batch','edit_sale_atomic','create_return_atomic','get_receivables_aging')
        GROUP BY proname HAVING count(*) > 1) d
  UNION ALL
  SELECT 5, 'signup ignores client-supplied role',
         CASE WHEN to_regprocedure('public.handle_new_user()') IS NULL THEN 'MISSING'
              WHEN pg_get_functiondef(to_regprocedure('public.handle_new_user()')) ILIKE '%raw_user_meta_data->>''role''%'
              THEN 'PROBLEM' ELSE 'OK' END,
         'handle_new_user must not read raw_user_meta_data->>role'
  UNION ALL
  SELECT 6, 'RLS enabled on every public table',
         CASE WHEN count(*) = 0 THEN 'OK' ELSE 'PROBLEM' END,
         coalesce(string_agg(relname, ', '), 'all tables protected')
  FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind = 'r' AND NOT relrowsecurity
  UNION ALL
  SELECT 7, 'no "allow everything" policies',
         CASE WHEN count(*) = 0 THEN 'OK' ELSE 'PROBLEM' END,
         coalesce(string_agg(tablename || ':' || policyname, ', '), 'none')
  FROM pg_policies
  WHERE schemaname = 'public' AND (qual = 'true' OR with_check = 'true')
    AND NOT (tablename = 'app_config' AND cmd = 'SELECT')
  UNION ALL
  SELECT 8, 'anon can execute only the allowed functions',
         CASE WHEN count(*) = 0 THEN 'OK' ELSE 'PROBLEM' END,
         coalesce(string_agg(proname, ', '), 'only is_admin, is_active_member, get_customer_portal')
  FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND p.proname NOT IN ('is_admin','is_active_member','get_customer_portal')
  UNION ALL
  SELECT 9, 'staff cannot call money/stock mutators directly',
         CASE WHEN count(*) = 0 THEN 'OK' ELSE 'PROBLEM' END,
         coalesce(string_agg(proname, ', '), 'internal helpers are not exposed')
  FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
    AND p.proname IN ('increment_stock','decrement_stock','deduct_stock_fifo','restore_stock_fifo','add_inventory_batch',
                      'resolve_account','reconcile_postings','sale_apply_items','fifo_take','populate_daily_analytics')
  UNION ALL
  SELECT 10, 'document triggers installed',
         CASE WHEN count(*) >= 6 THEN 'OK' ELSE 'MISSING' END,
         count(*) || ' posting triggers'
  FROM pg_trigger WHERE NOT tgisinternal AND tgname LIKE 'b\_%postings'
  UNION ALL
  SELECT 11, 'stock matches batches',
         CASE WHEN NOT (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND (table_name, column_name) IN (('products','stock'),('products','id'),('inventory_batches','remaining'),('inventory_batches','product_id'))) = 4 THEN 'MISSING'
              WHEN (xpath('//v/text()', query_to_xml('SELECT count(*) AS v FROM public.products p WHERE p.stock < coalesce((SELECT sum(remaining) FROM public.inventory_batches b WHERE b.product_id = p.id), 0) - 0.001', false, true, '')))[1]::text::int = 0 THEN 'OK' ELSE 'INFO' END,
         CASE WHEN NOT (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND (table_name, column_name) IN (('products','stock'),('products','id'),('inventory_batches','remaining'),('inventory_batches','product_id'))) = 4 THEN 'products/inventory_batches not set up yet'
              ELSE (xpath('//v/text()', query_to_xml('SELECT count(*) AS v FROM public.products p WHERE p.stock < coalesce((SELECT sum(remaining) FROM public.inventory_batches b WHERE b.product_id = p.id), 0) - 0.001', false, true, '')))[1]::text || ' product(s) where stock < units in batches (use Stock Count to fix)' END
  UNION ALL
  SELECT 12, 'cash book: balance vs journal',
         CASE WHEN NOT (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND (table_name, column_name) IN (('accounts','id'),('accounts','name'),('accounts','balance'),('account_transactions','account_id'),('account_transactions','type'),('account_transactions','amount'))) = 6 THEN 'MISSING'
              WHEN coalesce((xpath('//v/text()', query_to_xml('SELECT coalesce(string_agg(name || '' differs by '' || round(diff, 2), ''; ''), '''') AS v FROM (SELECT a.name, a.balance - coalesce(sum(CASE WHEN t.type=''in'' THEN t.amount ELSE -t.amount END), 0) AS diff FROM public.accounts a LEFT JOIN public.account_transactions t ON t.account_id = a.id GROUP BY a.id, a.name, a.balance) x WHERE abs(diff) >= 0.01', false, true, '')))[1]::text, '') = '' THEN 'OK' ELSE 'INFO' END,
         CASE WHEN NOT (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND (table_name, column_name) IN (('accounts','id'),('accounts','name'),('accounts','balance'),('account_transactions','account_id'),('account_transactions','type'),('account_transactions','amount'))) = 6 THEN 'accounts/account_transactions not set up yet'
              WHEN coalesce((xpath('//v/text()', query_to_xml('SELECT coalesce(string_agg(name || '' differs by '' || round(diff, 2), ''; ''), '''') AS v FROM (SELECT a.name, a.balance - coalesce(sum(CASE WHEN t.type=''in'' THEN t.amount ELSE -t.amount END), 0) AS diff FROM public.accounts a LEFT JOIN public.account_transactions t ON t.account_id = a.id GROUP BY a.id, a.name, a.balance) x WHERE abs(diff) >= 0.01', false, true, '')))[1]::text, '') = '' THEN 'balances equal the journal'
              ELSE (xpath('//v/text()', query_to_xml('SELECT coalesce(string_agg(name || '' differs by '' || round(diff, 2), ''; ''), '''') AS v FROM (SELECT a.name, a.balance - coalesce(sum(CASE WHEN t.type=''in'' THEN t.amount ELSE -t.amount END), 0) AS diff FROM public.accounts a LEFT JOIN public.account_transactions t ON t.account_id = a.id GROUP BY a.id, a.name, a.balance) x WHERE abs(diff) >= 0.01', false, true, '')))[1]::text || ' (opening balance or past drift)' END
  UNION ALL
  SELECT 13, 'customer balances match sales',
         CASE WHEN NOT (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND (table_name, column_name) IN (('customers','id'),('customers','total_credit'),('sales','customer_id'),('sales','due_amount'))) = 4 THEN 'MISSING'
              WHEN (xpath('//v/text()', query_to_xml('SELECT count(*) AS v FROM public.customers c WHERE abs(coalesce(c.total_credit, 0) - coalesce((SELECT sum(due_amount) FROM public.sales s WHERE s.customer_id = c.id AND s.due_amount > 0), 0)) > 0.01', false, true, '')))[1]::text::int = 0 THEN 'OK' ELSE 'PROBLEM' END,
         CASE WHEN NOT (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND (table_name, column_name) IN (('customers','id'),('customers','total_credit'),('sales','customer_id'),('sales','due_amount'))) = 4 THEN 'customers/sales columns not set up yet'
              ELSE (xpath('//v/text()', query_to_xml('SELECT count(*) AS v FROM public.customers c WHERE abs(coalesce(c.total_credit, 0) - coalesce((SELECT sum(due_amount) FROM public.sales s WHERE s.customer_id = c.id AND s.due_amount > 0), 0)) > 0.01', false, true, '')))[1]::text || ' customer(s) out of step' END
  UNION ALL
  SELECT 14, 'active admins',
         CASE WHEN NOT (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND (table_name, column_name) IN (('profiles','role'),('profiles','active'))) = 2 THEN 'MISSING'
              WHEN (xpath('//v/text()', query_to_xml('SELECT count(*) AS v FROM public.profiles WHERE role = ''admin'' AND coalesce(active, true)', false, true, '')))[1]::text::int >= 1 THEN 'OK' ELSE 'PROBLEM' END,
         CASE WHEN NOT (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND (table_name, column_name) IN (('profiles','role'),('profiles','active'))) = 2 THEN 'profiles.role/active missing'
              ELSE (xpath('//v/text()', query_to_xml('SELECT count(*) AS v FROM public.profiles WHERE role = ''admin'' AND coalesce(active, true)', false, true, '')))[1]::text || ' active admin(s)' END
  UNION ALL
  SELECT 15, 'sale time guard',
         CASE WHEN count(*) = 1 THEN 'OK' ELSE 'MISSING' END,
         CASE WHEN count(*) = 1 THEN 'a wrong PC clock cannot misdate a bill'
              ELSE 'run sql/2026_10_sale_time_guard.sql' END
  FROM pg_trigger WHERE NOT tgisinternal AND tgname = 'a_sales_guard_time'
  UNION ALL
  SELECT 16, 'app can edit products',
         CASE WHEN to_regprocedure('public.app_bulk_mode()') IS NULL THEN 'MISSING'
              WHEN has_function_privilege('authenticated', 'public.app_bulk_mode()', 'EXECUTE') THEN 'OK' ELSE 'PROBLEM' END,
         CASE WHEN to_regprocedure('public.app_bulk_mode()') IS NOT NULL
                   AND has_function_privilege('authenticated', 'public.app_bulk_mode()', 'EXECUTE')
              THEN 'stock guard can run for the app user'
              ELSE 'product edits fail ("permission denied for function app_bulk_mode") — run sql/2026_10_stage1_fixes.sql' END
  UNION ALL
  SELECT 17, 'receivables aging',
         CASE WHEN to_regprocedure('public.get_receivables_aging()') IS NULL THEN 'MISSING'
              WHEN pg_get_functiondef(to_regprocedure('public.get_receivables_aging()')) ILIKE '%due_date::date%' THEN 'OK' ELSE 'PROBLEM' END,
         CASE WHEN to_regprocedure('public.get_receivables_aging()') IS NOT NULL
                   AND pg_get_functiondef(to_regprocedure('public.get_receivables_aging()')) ILIKE '%due_date::date%'
              THEN 'works with date or timestamp due dates'
              ELSE 'fails on timestamp due_date — run sql/2026_10_stage1_fixes.sql' END
)
SELECT check_name, status, detail FROM checks ORDER BY ord;
