-- =====================================================================
-- 2026_10_sale_time_guard.sql  —  a wrong PC clock cannot misdate a bill
--
-- The app sends the time a bill was made (offline bills keep the time they
-- were rung up). A shop PC with a wrong clock (e.g. a dead motherboard
-- battery resets it to an old date) put bills on the wrong day and in the
-- wrong GST month, and nothing stopped a backdated bill.
--
-- New sales now get the server's time when the time sent is
--   * more than 10 minutes in the future, or
--   * more than 7 days in the past (offline bills sync within hours or days).
-- Restores (bulk mode) keep every bill's original time.
--
-- Apply in Supabase → SQL Editor: back up, run verify_schema.sql, run this
-- file, run verify_schema.sql again. Safe to run more than once.
-- =====================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.sales_guard_time() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.app_bulk_mode() THEN RETURN NEW; END IF;
  IF NEW.created_at IS NULL
     OR NEW.created_at > now() + interval '10 minutes'
     OR NEW.created_at < now() - interval '7 days' THEN
    NEW.created_at := now();
  END IF;
  RETURN NEW;
END $$;

-- trigger functions are not called directly
REVOKE EXECUTE ON FUNCTION public.sales_guard_time() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS a_sales_guard_time ON sales;
CREATE TRIGGER a_sales_guard_time BEFORE INSERT ON sales
  FOR EACH ROW EXECUTE FUNCTION public.sales_guard_time();

DO $$ BEGIN PERFORM public.record_migration('v101', '2026_10_sale_time_guard'); END $$;

COMMIT;
