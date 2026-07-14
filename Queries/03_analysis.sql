-- 03_analysis.sql
-- Analysis layer. Runs against payments_normalized from 02_normalize.sql.
--
-- Method: vendors are ranked by total spend and assigned a running cumulative
-- share. Vendors inside the top 80% of spend are treated as strategic; the
-- remainder is tail spend — many suppliers, small individual volumes, no
-- negotiating leverage. Savings are tail spend multiplied by a consolidation
-- discount rate.
--
-- The discount rate is an assumption, not a result. Published benchmarks for
-- tail-spend consolidation run 5-15%; all three are reported and the 10%
-- midpoint is used for the headline.

USE vendor_rationalization;


-- 1. Scope counters for the analysis population.
-- Output: Results/03_01_headline.csv
SELECT
    ROUND(SUM(check_amount), 2)        AS total_spend,
    COUNT(DISTINCT vendor_norm)        AS distinct_vendors,
    COUNT(DISTINCT agency)             AS distinct_agencies,
    COUNT(*)                           AS total_payments,
    ROUND(SUM(check_amount)
          / COUNT(DISTINCT vendor_norm), 2) AS avg_spend_per_vendor
FROM payments_normalized;


-- 2. Vendor ranking with cumulative spend share. Source table for the Pareto
-- chart and for the strategic/tail split used in every block below.
-- Output: Results/03_02_vendor_pareto.csv
WITH vendor_spend AS (
    SELECT
        vendor_norm,
        ROUND(SUM(check_amount), 2)        AS vendor_total,
        COUNT(*)                           AS payment_count,
        COUNT(DISTINCT agency)             AS agencies_served
    FROM payments_normalized
    GROUP BY vendor_norm
),
ranked AS (
    SELECT
        vendor_norm,
        vendor_total,
        payment_count,
        agencies_served,
        ROW_NUMBER() OVER (ORDER BY vendor_total DESC)            AS spend_rank,
        SUM(vendor_total) OVER (ORDER BY vendor_total DESC)
            / SUM(vendor_total) OVER ()                           AS cumulative_share
    FROM vendor_spend
)
SELECT
    spend_rank,
    vendor_norm,
    vendor_total,
    payment_count,
    agencies_served,
    ROUND(100 * cumulative_share, 2)       AS cumulative_pct_of_spend,
    CASE WHEN cumulative_share <= 0.80 THEN 'Strategic (top 80% of spend)'
         ELSE 'Tail (bottom 20% of spend)' END AS vendor_segment
FROM ranked
ORDER BY spend_rank;


-- 3. Strategic and tail segments collapsed to two rows, with each segment's
-- share of spend and of vendor count. The asymmetry between those two
-- percentages is the finding.
-- Output: Results/03_03_segment_summary.csv
WITH vendor_spend AS (
    SELECT vendor_norm, SUM(check_amount) AS vendor_total
    FROM payments_normalized
    GROUP BY vendor_norm
),
ranked AS (
    SELECT
        vendor_norm,
        vendor_total,
        SUM(vendor_total) OVER (ORDER BY vendor_total DESC)
            / SUM(vendor_total) OVER () AS cumulative_share
    FROM vendor_spend
),
segmented AS (
    SELECT
        CASE WHEN cumulative_share <= 0.80 THEN 'Strategic'
             ELSE 'Tail' END AS vendor_segment,
        vendor_total
    FROM ranked
)
SELECT
    vendor_segment,
    COUNT(*)                                              AS vendor_count,
    ROUND(SUM(vendor_total), 2)                           AS segment_spend,
    ROUND(100 * SUM(vendor_total)
          / SUM(SUM(vendor_total)) OVER (), 2)            AS pct_of_total_spend,
    ROUND(100 * COUNT(*)
          / SUM(COUNT(*)) OVER (), 2)                     AS pct_of_vendor_count
FROM segmented
GROUP BY vendor_segment
ORDER BY segment_spend DESC;


-- 4. Savings KPI. Addressable spend is all tail spend; savings are reported
-- at the 5/10/15% benchmark range with 10% as the headline.
-- Output: Results/03_04_savings_kpi.csv
WITH vendor_spend AS (
    SELECT vendor_norm, SUM(check_amount) AS vendor_total
    FROM payments_normalized
    GROUP BY vendor_norm
),
ranked AS (
    SELECT
        vendor_total,
        SUM(vendor_total) OVER (ORDER BY vendor_total DESC)
            / SUM(vendor_total) OVER () AS cumulative_share
    FROM vendor_spend
),
tail AS (
    SELECT SUM(vendor_total) AS addressable_tail_spend
    FROM ranked
    WHERE cumulative_share > 0.80
)
SELECT
    ROUND(addressable_tail_spend, 2)            AS addressable_tail_spend,
    ROUND(addressable_tail_spend * 0.05, 2)     AS savings_at_5pct,
    ROUND(addressable_tail_spend * 0.10, 2)     AS savings_at_10pct_HEADLINE,
    ROUND(addressable_tail_spend * 0.15, 2)     AS savings_at_15pct
FROM tail;


-- 5. Category fragmentation, to identify where consolidation is feasible
-- rather than merely large. top_vendor_share_pct is the share held by the
-- single largest supplier in each category: a low share means no incumbent
-- has to be displaced, which is what makes a category actionable.
--
-- Grouped on expense_category rather than spending_category: the latter is
-- effectively single-valued ('Contracts') once non-procurement rows are
-- removed, so it carries no signal (see 01 block 4).
-- Output: Results/03_05_category_fragmentation.csv
WITH cat_vendor AS (
    SELECT
        expense_category,
        vendor_norm,
        SUM(check_amount) AS vendor_total
    FROM payments_normalized
    WHERE expense_category IS NOT NULL AND TRIM(expense_category) <> ''
    GROUP BY expense_category, vendor_norm
)
SELECT
    expense_category,
    COUNT(*)                                           AS vendor_count,
    ROUND(SUM(vendor_total), 2)                         AS category_spend,
    ROUND(MAX(vendor_total), 2)                         AS top_vendor_spend,
    ROUND(100 * MAX(vendor_total) / SUM(vendor_total), 2) AS top_vendor_share_pct
FROM cat_vendor
GROUP BY expense_category
HAVING vendor_count >= 10            -- below this a category cannot be fragmented
ORDER BY category_spend DESC
LIMIT 25;

-- 6. Vendors whose spend was split across multiple raw payee names. Quantifies
-- what the normalization work in 02 recovered: these suppliers appeared smaller
-- than they are, and several move materially up the ranking once merged.
-- Output: Results/03_06_hidden_concentration.csv
SELECT
    vendor_norm,
    COUNT(DISTINCT payee_name)                                          AS alias_count,
    ROUND(SUM(check_amount), 2)                                         AS true_total_spend,
    GROUP_CONCAT(DISTINCT payee_name ORDER BY payee_name SEPARATOR ' | ') AS raw_aliases
FROM payments_normalized
GROUP BY vendor_norm
HAVING alias_count > 1
ORDER BY true_total_spend DESC
LIMIT 25;


-- 7. Top vendors by spend, post-normalization.
-- Output: Results/03_07_top_vendors.csv
SELECT
    vendor_norm,
    ROUND(SUM(check_amount), 2)   AS total_spend,
    COUNT(*)                      AS payment_count,
    COUNT(DISTINCT agency)        AS agencies_served
FROM payments_normalized
GROUP BY vendor_norm
ORDER BY total_spend DESC
LIMIT 20;
