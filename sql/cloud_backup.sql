-- ============================================
-- CLOUD BACKUP MECHANISM
-- Run this ONCE in Supabase SQL Editor
-- ============================================

BEGIN;

-- Backup metadata table
CREATE TABLE IF NOT EXISTS backups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  backup_type VARCHAR(50) NOT NULL DEFAULT 'full', -- full, incremental, manual
  status VARCHAR(50) NOT NULL DEFAULT 'pending', -- pending, running, completed, failed
  started_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ,
  file_path TEXT,
  file_size_bytes BIGINT,
  checksum VARCHAR(64),
  tables_included TEXT[], -- list of tables backed up
  row_counts JSONB, -- {"sales": 1234, "products": 567, ...}
  error_message TEXT,
  created_by VARCHAR(255) DEFAULT current_user
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_backups_status ON backups(status);
CREATE INDEX IF NOT EXISTS idx_backups_started_at ON backups(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_backups_type ON backups(backup_type);

-- RLS
ALTER TABLE backups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role can manage backups"
  ON backups
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated can read backups"
  ON backups
  FOR SELECT
  TO authenticated
  USING (true);

-- Function to get table row counts for backup verification
CREATE OR REPLACE FUNCTION get_table_row_counts()
RETURNS JSONB AS $$
DECLARE
  result JSONB := '{}'::jsonb;
  table_name TEXT;
  row_count BIGINT;
BEGIN
  FOR table_name IN
    SELECT t.table_name
    FROM information_schema.tables t
    WHERE t.table_schema = 'public'
      AND t.table_type = 'BASE TABLE'
      AND t.table_name NOT LIKE 'pg_%'
      AND t.table_name NOT LIKE 'schema_%'
    ORDER BY t.table_name
  LOOP
    EXECUTE format('SELECT COUNT(*) FROM %I', table_name) INTO row_count;
    result := result || jsonb_build_object(table_name, row_count);
  END LOOP;
  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to create a backup record
CREATE OR REPLACE FUNCTION create_backup_record(
  p_backup_type VARCHAR DEFAULT 'manual'
) RETURNS UUID AS $$
DECLARE
  backup_id UUID;
  row_counts JSONB;
BEGIN
  -- Get current row counts
  row_counts := get_table_row_counts();

  -- Create backup record
  INSERT INTO backups (backup_type, status, row_counts)
  VALUES (p_backup_type, 'running', row_counts)
  RETURNING id INTO backup_id;

  RETURN backup_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to complete a backup record
CREATE OR REPLACE FUNCTION complete_backup(
  p_backup_id UUID,
  p_file_path TEXT,
  p_file_size_bytes BIGINT,
  p_checksum VARCHAR
) RETURNS void AS $$
BEGIN
  UPDATE backups
  SET
    status = 'completed',
    completed_at = now(),
    file_path = p_file_path,
    file_size_bytes = p_file_size_bytes,
    checksum = p_checksum
  WHERE id = p_backup_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to fail a backup record
CREATE OR REPLACE FUNCTION fail_backup(
  p_backup_id UUID,
  p_error_message TEXT
) RETURNS void AS $$
BEGIN
  UPDATE backups
  SET
    status = 'failed',
    completed_at = now(),
    error_message = p_error_message
  WHERE id = p_backup_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get backup history
CREATE OR REPLACE FUNCTION get_backup_history(
  p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
  id UUID,
  backup_type VARCHAR,
  status VARCHAR,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  file_size_bytes BIGINT,
  row_counts JSONB,
  error_message TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    b.id,
    b.backup_type,
    b.status,
    b.started_at,
    b.completed_at,
    b.file_size_bytes,
    b.row_counts,
    b.error_message
  FROM backups b
  ORDER BY b.started_at DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get database size estimate
CREATE OR REPLACE FUNCTION get_database_size_estimate()
RETURNS JSONB AS $$
DECLARE
  result JSONB;
  total_size BIGINT;
  table_sizes JSONB := '{}'::jsonb;
  table_name TEXT;
  table_size BIGINT;
BEGIN
  -- Get total database size
  SELECT pg_database_size(current_database()) INTO total_size;

  -- Get individual table sizes
  FOR table_name IN
    SELECT t.table_name
    FROM information_schema.tables t
    WHERE t.table_schema = 'public'
      AND t.table_type = 'BASE TABLE'
    ORDER BY t.table_name
  LOOP
    SELECT pg_total_relation_size(quote_ident(table_name)) INTO table_size;
    table_sizes := table_sizes || jsonb_build_object(table_name, table_size);
  END LOOP;

  result := jsonb_build_object(
    'total_size_bytes', total_size,
    'total_size_mb', round((total_size / 1024.0 / 1024.0)::numeric, 2),
    'table_sizes', table_sizes
  );

  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Record initial backup setup
PERFORM record_migration('v070', 'cloud_backup_mechanism', 'backup');

COMMIT;
