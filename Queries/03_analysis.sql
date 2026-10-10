-- 03_analysis.sql
-- Analysis layer. Runs against payments_normalized from 02_normalize.sql.
--
-- Method: vendors are ranked by total spend and assigned a running cumulative
-- share. Vendors inside the top 80% of spend are treated as strategic; the
-- remainder is tail spend: many suppliers, small individual volumes, no
-- negotiating leverage. Savings are tail spend multiplied by a consolidation
-- discount rate.
--
-- The discount rate is an assumption, not a result. Published benchmarks for
-- tail-spend consolidation run 5-15%; all three are reported and the 10%
-- midpoint is used for the headline.
--
-- Blocks 4 and 8 produce two different savings figures and both are reported.
-- Block 4 is a ceiling that assumes all tail spend is consolidatable. Block 8
-- restricts to a rule-defined basket of categories and is the realistic
-- number. See block 8 for why the difference is roughly fourfold.

USE vendor_rationalization;


-- 1. Scope counters for the analysis population.
-- Output: Exports/1_headline-counter.csv
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
-- Output: Exports/2_vendor-pareto.csv
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
-- share of spend and of vendor count. The gap between those two
-- percentages is the main finding.
-- Output: Exports/3_strategic-vs-tail-summary.csv
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


-- 4. Savings ceiling. Addressable spend is taken as all tail spend, which
-- assumes every tail dollar can be consolidated. That isn't true once you
-- look at what the tail contains (see block 8). Kept so the two figures can be
-- compared.
-- Output: Exports/4_kpi.csv
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


-- 5. Category fragmentation, to find categories where consolidation is
-- practical. top_vendor_share_pct is the share held by the
-- single largest supplier in each category: a low share means no incumbent
-- has to be displaced, which is what makes a category actionable.
--
-- Grouped on expense_category rather than spending_category: the latter is
-- effectively single-valued ('Contracts') once non-procurement rows are
-- removed, so it carries no signal (see 01 block 4).
-- Output: Exports/5_where-to-consolidate.csv
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

-- 5b. Same scan across all categories with the basket rule applied, so the
-- included and excluded categories can be compared side by side.
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
    CASE WHEN expense_category IN (
        'CONTRACTUAL SERVICES GENERAL',
        'SUPPLIES + MATERIALS - GENERAL',
        'PROF SERV OTHER',
        'EQUIPMENT GENERAL',
        'DATA PROCESSING EQUIPMENT MAINTENANCE',
        'DATA PROCESSING SUPPLIES',
        'FOOD & FORAGE SUPPLIES',
        'AUTOMOTIVE SUPPLIES & MATERIAL',
        'MAINTENANCE SUPPLIES',
        'OFFICE EQUIPMENT MAINTENANCE',
        'OFFICE EQUIPMENT',
        'PRINTING SUPPLIES',
        'TELECOMMUNICATIONS EQUIPMENT',
        'SECURITY EQUIPMENT',
        'CLEANING SUPPLIES',
        'MOTOR VEHICLE EQUIPMENT',
        'FOOD SERVICE EQUIPMENT',
        'INSTRUCTIONAL SUPPLIES',
        'MAINTENANCE SUPPLIES--WTC ONLY',
        -- added after full-category scan (2026-07-13):
        'SECURITY SERVICES',
        'MAINT & REP GENERAL',
        'PROF SERV COMPUTER SERVICES',
        'MOTOR VEHICLE FUEL'
    ) THEN 'Target'
      ELSE 'Excluded'
    END AS basket_status,
    COUNT(*)                                              AS vendor_count,
    ROUND(SUM(vendor_total), 2)                           AS category_spend,
    ROUND(MAX(vendor_total), 2)                           AS top_vendor_spend,
    ROUND(100 * MAX(vendor_total) / SUM(vendor_total), 2) AS top_vendor_share_pct
FROM cat_vendor
GROUP BY expense_category
ORDER BY category_spend DESC;

-- 6. Vendors whose spend was split across multiple raw payee names. Quantifies
-- what the normalization work in 02 recovered: these suppliers appeared smaller
-- than they are, and several move materially up the ranking once merged.
-- Output: Exports/6_hidden-concentration-from-name-cleaning.csv
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
-- Output: Exports/7_top-20-vendors.csv
SELECT
    vendor_norm,
    ROUND(SUM(check_amount), 2)   AS total_spend,
    COUNT(*)                      AS payment_count,
    COUNT(DISTINCT agency)        AS agencies_served
FROM payments_normalized
GROUP BY vendor_norm
ORDER BY total_spend DESC
LIMIT 20;


-- 8. Savings restricted to a rule-defined basket.
--
-- The ceiling in block 4 treats all tail spend as addressable. Inspection of
-- the tail shows it also contains rents, legal settlements, one-off payments
-- and human-services contracts, none of which respond to bulk negotiation.
-- Applying the discount rate to that spend overstates the opportunity by
-- roughly a factor of four.
--
-- This block recomputes on tail spend within categories that meet a stated
-- rule: buyer-chosen goods and general services, no mandated or court-driven
-- payments. Every category matching the rule is included, including small ones,
-- so the list comes from the rule and wasn't picked to reach a number.
-- Output: Exports/8b_realistic-kpi.csv

-- 8a. Category strings verified before use. IN is exact-match, and an earlier
-- pass silently dropped the State of New York Medicaid rows on a near-miss
-- string, so the names below are checked against the data.
SELECT expense_category, COUNT(*) AS payments,
       ROUND(SUM(check_amount), 2) AS dollars
FROM payments_normalized
WHERE expense_category LIKE '%CONTRACTUAL SERVICES%'
   OR expense_category LIKE '%SUPPLIES%'
   OR expense_category LIKE '%PROF SERV OTHER%'
   OR expense_category LIKE '%EQUIPMENT%'
GROUP BY expense_category
ORDER BY dollars DESC;

-- 8b. Same Pareto CTEs as block 4, but filtering at payment level rather than
-- vendor level: a row counts only if it is paid to a tail vendor and falls in a
-- target category. Filtering at vendor level would have counted a tail vendor's
-- non-consolidatable spend as addressable.
WITH vendor_spend AS (
    SELECT vendor_norm, SUM(check_amount) AS vendor_total
    FROM payments_normalized
    GROUP BY vendor_norm
),
ranked AS (
    SELECT
        vendor_norm,
        SUM(vendor_total) OVER (ORDER BY vendor_total DESC)
            / SUM(vendor_total) OVER () AS cumulative_share
    FROM vendor_spend
),
tail_vendors AS (
    SELECT vendor_norm
    FROM ranked
    WHERE cumulative_share > 0.80
),
target_tail AS (
    SELECT p.check_amount
    FROM payments_normalized p
    JOIN tail_vendors t ON p.vendor_norm = t.vendor_norm
    WHERE p.expense_category IN (
        'CONTRACTUAL SERVICES GENERAL',
        'SUPPLIES + MATERIALS - GENERAL',
        'PROF SERV OTHER',
        'EQUIPMENT GENERAL',
        'DATA PROCESSING EQUIPMENT MAINTENANCE',
        'DATA PROCESSING SUPPLIES',
        'FOOD & FORAGE SUPPLIES',
        'AUTOMOTIVE SUPPLIES & MATERIAL',
        'MAINTENANCE SUPPLIES',
        'OFFICE EQUIPMENT MAINTENANCE',
        'OFFICE EQUIPMENT',
        'PRINTING SUPPLIES',
        'TELECOMMUNICATIONS EQUIPMENT',
        'SECURITY EQUIPMENT',
        'CLEANING SUPPLIES',
        'MOTOR VEHICLE EQUIPMENT',
        'FOOD SERVICE EQUIPMENT',
        'INSTRUCTIONAL SUPPLIES',
        'MAINTENANCE SUPPLIES--WTC ONLY',
        -- added after full-category scan (2026-07-13):
        'SECURITY SERVICES',
        'MAINT & REP GENERAL',
        'PROF SERV COMPUTER SERVICES',
        'MOTOR VEHICLE FUEL'
        -- Considered and excluded, conservatively:
        --   PROF SERV LEGAL SERVICES     court-driven and specialized
        --   TELEPHONE & OTHER COMMUNICATNS  utility-like, few suppliers
        --   PROF SERV CURRIC & PROF DEVEL   borderline, so left out
        --   OTHR SERV AND CHRGS-GENERAL     unclassifiable residual category
    )
)
SELECT
    ROUND(SUM(check_amount), 2)          AS realistic_addressable_spend,
    ROUND(SUM(check_amount) * 0.05, 2)   AS savings_at_5pct,
    ROUND(SUM(check_amount) * 0.10, 2)   AS savings_at_10pct_REALISTIC,
    ROUND(SUM(check_amount) * 0.15, 2)   AS savings_at_15pct
FROM target_tail;
