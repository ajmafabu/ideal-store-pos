-- =====================================================================
-- profit_check_report.sql — READ ONLY. Changes nothing.
-- Is the profit the app shows true? (owner, 22 Oct 2026)
--
-- One row per month (Indian time), the same formula as the dashboard:
--   profit = sales without GST, after returns - cost of what was sold
--            - expenses - damaged stock
-- plus the things that make that profit wrong:
--   zero_cost_*   lines sold with NO cost (product purchase price was 0):
--                 counted as almost 100% profit -> profit too HIGH
--   below_cost_*  lines sold for less than their cost -> real loss, or a
--                 wrong cost price
--   expense_entries  very few entries in a month usually means expenses
--                 (rent, salary, power, tea) were not entered -> too HIGH
--   purchases     money spent on stock that month, to compare with cost
--                 of goods sold (stock growing = profit sitting in stock)
-- Run in Supabase -> SQL Editor and download the result as CSV.
-- =====================================================================
WITH lines AS (
  SELECT date_trunc('month', s.created_at AT TIME ZONE 'Asia/Kolkata') AS m,
         public.item_line_total(x) AS line_total,
         public.item_cost(x) AS line_cost
  FROM sales s, jsonb_array_elements(s.items) x
), per_line AS (
  SELECT m,
         count(*) FILTER (WHERE line_cost <= 0 AND line_total > 0) AS zero_cost_lines,
         coalesce(sum(line_total) FILTER (WHERE line_cost <= 0 AND line_total > 0), 0) AS zero_cost_sales,
         count(*) FILTER (WHERE line_cost > line_total + 0.01 AND line_total > 0) AS below_cost_lines,
         coalesce(sum(line_cost - line_total) FILTER (WHERE line_cost > line_total + 0.01 AND line_total > 0), 0) AS below_cost_loss
  FROM lines GROUP BY m
), months AS (
  SELECT DISTINCT date_trunc('month', created_at AT TIME ZONE 'Asia/Kolkata') AS m FROM sales
), fig AS (
  SELECT mo.m, f.*
  FROM months mo,
  LATERAL public.period_figures(mo.m AT TIME ZONE 'Asia/Kolkata',
                                (mo.m + interval '1 month') AT TIME ZONE 'Asia/Kolkata') f
), pur AS (
  SELECT date_trunc('month', created_at AT TIME ZONE 'Asia/Kolkata') AS m,
         sum(total_amount) AS purchases, count(*) AS purchase_bills
  FROM purchases GROUP BY 1
), exp AS (
  SELECT date_trunc('month', created_at AT TIME ZONE 'Asia/Kolkata') AS m, count(*) AS expense_entries
  FROM expenses WHERE NOT public.is_tax_payment_category(category) GROUP BY 1
)
SELECT to_char(f.m, 'Mon YYYY') AS month,
       f.orders AS bills,
       round(f.net_revenue) AS sales_without_gst,
       round(f.net_cogs) AS cost_of_goods_sold,
       round(100 * (f.net_revenue - f.net_cogs) / nullif(f.net_revenue, 0), 1) AS gross_margin_pct,
       round(f.expenses) AS expenses,
       coalesce(e.expense_entries, 0) AS expense_entries,
       round(f.damaged_loss) AS damaged,
       round(f.net_profit) AS profit_shown,
       coalesce(p.zero_cost_lines, 0) AS zero_cost_lines,
       round(coalesce(p.zero_cost_sales, 0)) AS zero_cost_sales,
       coalesce(p.below_cost_lines, 0) AS below_cost_lines,
       round(coalesce(p.below_cost_loss, 0)) AS below_cost_loss,
       round(coalesce(pu.purchases, 0)) AS purchases,
       coalesce(pu.purchase_bills, 0) AS purchase_bills
FROM fig f
LEFT JOIN per_line p ON p.m = f.m
LEFT JOIN pur pu ON pu.m = f.m
LEFT JOIN exp e ON e.m = f.m
ORDER BY f.m;
