-- Run this in Supabase SQL Editor first (https://supabase.com/dashboard → SQL Editor)
-- This recreates the update_tamil_names function with the correct parameter type

DROP FUNCTION IF EXISTS update_tamil_names(jsonb);

CREATE OR REPLACE FUNCTION update_tamil_names(products_json jsonb)
RETURNS void AS $$
DECLARE
    item jsonb;
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(products_json)
    LOOP
        UPDATE products
        SET tamil_name = item->>'tamil_name'
        WHERE id = (item->>'id')::uuid
          AND (tamil_name IS NULL OR tamil_name = '');
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Also ensure the anon role can call this function
GRANT EXECUTE ON FUNCTION update_tamil_names(jsonb) TO anon;
GRANT EXECUTE ON FUNCTION update_tamil_names(jsonb) TO authenticated;
