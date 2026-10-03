#!/bin/bash
# Build a "legacy" database by applying the repo's historical SQL files in dependency order.
DB=${1:-legacy}
S=$(cd $(dirname $0)/../legacy && pwd)
P="psql -h ${PGHOST:-/tmp/pg} -p ${PGPORT:-5433} -U ${PGUSER:-postgres} -q -v ON_ERROR_STOP=1"
psql -h ${PGHOST:-/tmp/pg} -p ${PGPORT:-5433} -U ${PGUSER:-postgres} -q -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
$P -d $DB -f $(dirname $0)/supabase_stub.sql >/dev/null
ORDER="setup credit_tracking supplier_management accounts returns_damaged rls_consolidated app_config product_variants purchase_orders add_tamil_name_migration add_sfw_unit_migration gst_migration expiry_migration dual_rate_migration sales_fix_migration fix5_reconcile_stock data_integrity_migration analytics_rpc phase1_analytics_migration accounting_improvements security_migration returns_damaged_atomic_migration delete_sale_atomic_migration transaction_edit_migration transaction_edit_rpc_migration missing_functions clear_tamil_names_func phase0_emergency_indexes phase1_financial_integrity phase2_concurrency_integrity phase3_performance customer_delete_fk_fix fix_batch_tracking returns_v2_migration sales_missing_columns_migration credit_delete_fix fix_profit_formula receivables_aging_rpc reports_rpc balance_sheet_rpc cash_flow_rpc cloud_backup migration_tracking migration_baseline"
for f in $ORDER; do
  out=$($P -d $DB -f $S/$f.sql 2>&1)
  if [ $? -ne 0 ]; then echo "FAILED: $f :: $(echo "$out" | grep -m1 ERROR)"; fi
done
$P -d $DB -f $S/create_function.sql >/dev/null 2>&1 || echo "FAILED: create_function"
echo "legacy build done: $DB"
