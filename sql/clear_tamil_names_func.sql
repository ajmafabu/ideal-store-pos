-- Function to clear all Tamil names (for re-translation)
CREATE OR REPLACE FUNCTION clear_all_tamil_names()
RETURNS void AS $$
BEGIN
    UPDATE products SET tamil_name = NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION clear_all_tamil_names() TO anon;
GRANT EXECUTE ON FUNCTION clear_all_tamil_names() TO authenticated;
