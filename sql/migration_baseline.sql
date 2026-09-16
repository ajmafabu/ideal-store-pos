-- ============================================
-- MIGRATION RUNNER
-- Apply this to record existing migrations
-- Run AFTER migration_tracking.sql
-- ============================================

BEGIN;

-- Record all existing migrations as already applied
-- This creates a baseline of all migrations that were applied before tracking was added

-- Core schema migrations (pre-tracking)
PERFORM record_migration('v001', 'app_config', 'core');
PERFORM record_migration('v002', 'sales_fix_migration', 'core');
PERFORM record_migration('v003', 'fix5_reconcile_stock', 'core');
PERFORM record_migration('v004', 'data_integrity_migration', 'core');
PERFORM record_migration('v005', 'rls_consolidated', 'core');
PERFORM record_migration('v006', 'security_migration', 'core');

-- Feature migrations
PERFORM record_migration('v010', 'add_tamil_name_migration', 'feature');
PERFORM record_migration('v011', 'add_sfw_unit_migration', 'feature');
PERFORM record_migration('v012', 'gst_migration', 'feature');
PERFORM record_migration('v013', 'expiry_migration', 'feature');
PERFORM record_migration('v014', 'dual_rate_migration', 'feature');
PERFORM record_migration('v015', 'credit_tracking', 'feature');
PERFORM record_migration('v016', 'supplier_management', 'feature');
PERFORM record_migration('v017', 'product_variants', 'feature');
PERFORM record_migration('v018', 'purchase_orders', 'feature');
PERFORM record_migration('v019', 'returns_damaged', 'feature');

-- Analytics & reporting
PERFORM record_migration('v020', 'analytics_rpc', 'analytics');
PERFORM record_migration('v021', 'phase1_analytics_migration', 'analytics');
PERFORM record_migration('v022', 'accounting_improvements', 'analytics');

-- RPC migrations
PERFORM record_migration('v030', 'returns_damaged_atomic_migration', 'rpc');
PERFORM record_migration('v031', 'delete_sale_atomic_migration', 'rpc');
PERFORM record_migration('v032', 'transaction_edit_rpc_migration', 'rpc');
PERFORM record_migration('v033', 'missing_functions', 'rpc');
PERFORM record_migration('v034', 'clear_tamil_names_func', 'rpc');

-- Phase migrations (audit fixes)
PERFORM record_migration('v040', 'phase0_emergency_indexes', 'phase');
PERFORM record_migration('v041', 'phase1_financial_integrity', 'phase');
PERFORM record_migration('v042', 'phase2_concurrency_integrity', 'phase');
PERFORM record_migration('v043', 'phase3_performance', 'phase');

-- Cleanup migrations
PERFORM record_migration('v050', 'customer_delete_fk_fix', 'cleanup');
PERFORM record_migration('v051', 'fix_batch_tracking', 'cleanup');
PERFORM record_migration('v052', 'returns_v2_migration', 'cleanup');
PERFORM record_migration('v053', 'transaction_edit_migration', 'cleanup');
PERFORM record_migration('v054', 'sales_missing_columns_migration', 'cleanup');

-- Data migrations
PERFORM record_migration('v060', 'clear_tamil_names', 'data');
PERFORM record_migration('v061', 'set_tanglish_names', 'data');

COMMIT;
