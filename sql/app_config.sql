-- App config table for force update and remote settings
CREATE TABLE IF NOT EXISTS app_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Insert minimum version requirement
INSERT INTO app_config (key, value) VALUES ('min_version', '1.0.1')
ON CONFLICT (key) DO NOTHING;

-- RLS: allow public read, admin write
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read app_config" ON app_config
  FOR SELECT USING (true);

CREATE POLICY "Admins can update app_config" ON app_config
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Admins can insert app_config" ON app_config
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );
