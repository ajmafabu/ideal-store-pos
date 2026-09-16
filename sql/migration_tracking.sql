-- ============================================
-- MIGRATION TRACKING
-- Run this ONCE in Supabase SQL Editor
-- ============================================

BEGIN;

-- Migration tracking table
CREATE TABLE IF NOT EXISTS schema_migrations (
  id SERIAL PRIMARY KEY,
  version VARCHAR(255) NOT NULL UNIQUE,
  name VARCHAR(500) NOT NULL,
  applied_at TIMESTAMPTZ DEFAULT now(),
  applied_by VARCHAR(255),
  checksum VARCHAR(64),
  execution_ms INTEGER
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_schema_migrations_version ON schema_migrations(version);
CREATE INDEX IF NOT EXISTS idx_schema_migrations_applied_at ON schema_migrations(applied_at);

-- RLS: only service role can modify
ALTER TABLE schema_migrations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role can manage migrations"
  ON schema_migrations
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated can read migrations"
  ON schema_migrations
  FOR SELECT
  TO authenticated
  USING (true);

-- Function to record a migration
CREATE OR REPLACE FUNCTION record_migration(
  p_version VARCHAR,
  p_name VARCHAR,
  p_checksum VARCHAR DEFAULT NULL,
  p_execution_ms INTEGER DEFAULT NULL
) RETURNS void AS $$
BEGIN
  INSERT INTO schema_migrations (version, name, applied_by, checksum, execution_ms)
  VALUES (p_version, p_name, current_user, p_checksum, p_execution_ms)
  ON CONFLICT (version) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if a migration has been applied
CREATE OR REPLACE FUNCTION is_migration_applied(p_version VARCHAR)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM schema_migrations WHERE version = p_version
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get migration history
CREATE OR REPLACE FUNCTION get_migration_history()
RETURNS TABLE (
  version VARCHAR,
  name VARCHAR,
  applied_at TIMESTAMPTZ,
  applied_by VARCHAR,
  execution_ms INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT sm.version, sm.name, sm.applied_at, sm.applied_by, sm.execution_ms
  FROM schema_migrations sm
  ORDER BY sm.applied_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Record all existing migrations as already applied
-- This prevents re-running old migrations
DO $$
DECLARE
  migration_record RECORD;
BEGIN
  -- Record the migration tracking setup itself
  PERFORM record_migration('000', 'migration_tracking_setup');
END $$;

COMMIT;
