-- Transaction editing and audit trail
-- Run in Supabase SQL Editor before using history edit.

CREATE TABLE IF NOT EXISTS transaction_edits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('sale', 'purchase')),
  transaction_id UUID NOT NULL,
  reason TEXT NOT NULL,
  old_data JSONB NOT NULL DEFAULT '{}',
  new_data JSONB NOT NULL DEFAULT '{}',
  edited_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_transaction_edits_transaction
  ON transaction_edits(transaction_type, transaction_id, created_at DESC);

ALTER TABLE transaction_edits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage transaction edits" ON transaction_edits;
CREATE POLICY "Admins manage transaction edits" ON transaction_edits
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- This migration intentionally creates the audit storage first.
-- Stock/account-safe edit RPCs are added in the next migration after
-- the exact payment and batch rules are confirmed against the live schema.
