-- cleanup_report.sql — READ-ONLY. Changes nothing.
-- One row per product that needs attention. Run in the Supabase SQL editor,
-- then use "Download CSV" (or Export → CSV) and send the file to Claude.
WITH p AS (
  SELECT p.*,
         lower(btrim(p.name)) AS name_key,
         count(*) OVER (PARTITION BY lower(btrim(p.name))) AS name_copies,
         dense_rank() OVER (ORDER BY lower(btrim(p.name))) AS name_group
  FROM products p
)
SELECT
  p.id,
  p.name,
  p.tamil_name,
  p.category,
  p.unit,
  p.purchase_price,
  p.selling_price,
  p.stock,
  p.hsn_code,
  p.gst_rate,
  p.barcode,
  CASE WHEN p.name_copies > 1 THEN p.name_group END                AS duplicate_group,
  concat_ws(', ',
    CASE WHEN coalesce(p.selling_price,0) <= 0 AND coalesce(p.purchase_price,0) > 0 THEN 'SELLING PRICE 0' END,
    CASE WHEN p.selling_price > 0 AND p.selling_price < p.purchase_price THEN 'SELLS BELOW COST' END,
    CASE WHEN p.name_copies > 1 THEN 'DUPLICATE NAME' END,
    CASE WHEN p.category IS NULL OR btrim(p.category) = '' THEN 'NO CATEGORY' END,
    CASE WHEN p.category IS NOT NULL AND p.category <> initcap(lower(btrim(p.category))) THEN 'CATEGORY SPELLING' END,
    CASE WHEN p.tamil_name IS NOT NULL AND (p.tamil_name = p.name OR p.tamil_name IN ('test','')) THEN 'TAMIL NAME COPIED' END,
    CASE WHEN p.hsn_code IS NULL OR btrim(p.hsn_code) = '' THEN 'NO HSN' END,
    CASE WHEN coalesce(p.gst_rate,0) = 0 THEN 'GST 0' END
  ) AS problems
FROM p
WHERE (coalesce(p.selling_price,0) <= 0 AND coalesce(p.purchase_price,0) > 0)
   OR (p.selling_price > 0 AND p.selling_price < p.purchase_price)
   OR p.name_copies > 1
   OR p.category IS NULL OR btrim(p.category) = ''
   OR p.category <> initcap(lower(btrim(p.category)))
   OR (p.tamil_name IS NOT NULL AND (p.tamil_name = p.name OR p.tamil_name IN ('test','')))
   OR p.hsn_code IS NULL OR btrim(p.hsn_code) = ''
   OR coalesce(p.gst_rate,0) = 0
ORDER BY p.name_key, p.created_at;
