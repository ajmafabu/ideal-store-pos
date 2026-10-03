SET client_min_messages = warning;
CREATE SCHEMA IF NOT EXISTS t;
GRANT USAGE ON SCHEMA t TO anon, authenticated;
CREATE OR REPLACE FUNCTION t.eq(actual numeric, expected numeric, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF actual IS DISTINCT FROM expected AND abs(coalesce(actual,-999999) - coalesce(expected,-999999)) > 0.011 THEN
    RAISE EXCEPTION 'FAIL %: expected %, got %', label, expected, actual;
  END IF;
  RAISE NOTICE 'ok  %', label;
END $$;
CREATE OR REPLACE FUNCTION t.ok(cond boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF;
  RAISE NOTICE 'ok  %', label;
END $$;
CREATE OR REPLACE FUNCTION t.fails(sql text, pattern text, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql;
  EXCEPTION WHEN others THEN
    IF SQLERRM ILIKE '%' || pattern || '%' THEN RAISE NOTICE 'ok  % (%)', label, SQLERRM; RETURN; END IF;
    RAISE EXCEPTION 'FAIL %: wrong error: %', label, SQLERRM;
  END;
  RAISE EXCEPTION 'FAIL %: expected an error', label;
END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA t TO anon, authenticated;

-- money helpers (read as superuser)
CREATE OR REPLACE FUNCTION t.bal(p_type text) RETURNS numeric LANGUAGE sql AS
$$ SELECT coalesce(sum(balance),0) FROM public.accounts WHERE account_type = p_type $$;
CREATE OR REPLACE FUNCTION t.stock(p_name text) RETURNS numeric LANGUAGE sql AS
$$ SELECT stock FROM public.products WHERE name = p_name $$;
CREATE OR REPLACE FUNCTION t.batches(p_name text) RETURNS numeric LANGUAGE sql AS
$$ SELECT coalesce(sum(remaining),0) FROM public.inventory_batches b JOIN public.products p ON p.id=b.product_id WHERE p.name = p_name $$;
CREATE OR REPLACE FUNCTION t.acc(p_type text) RETURNS uuid LANGUAGE sql AS
$$ SELECT id FROM public.accounts WHERE account_type = p_type ORDER BY created_at, id LIMIT 1 $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA t TO anon, authenticated;

SET client_min_messages = notice;
