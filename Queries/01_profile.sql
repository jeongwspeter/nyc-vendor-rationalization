-- 01_profile.sql
-- Profiling pass over payments_raw, before any cleaning or exclusion.
--
-- Purpose is to establish what the extract actually contains and to find the
-- artifacts that scoping in 02_normalize.sql has to handle: placeholder
-- amounts, negative values, non-procurement agencies, and payee-name variants.
-- Output: Results/01_profile_results.csv

USE vendor_rationalization;

-- 1. Coverage. Confirms the extract is a single fiscal year and that
-- issue_date parsed as DATE rather than falling back to NULL.
SELECT
    COUNT(*)                  AS total_rows,
    MIN(issue_date)           AS earliest_date,
    MAX(issue_date)           AS latest_date,
    COUNT(DISTINCT fiscal_year) AS distinct_fiscal_years
FROM payments_raw;


-- 2. Spend distribution. min/max are the important columns here: negative
-- minimums indicate refunds and reversals, and a maximum sitting exactly on
-- a round boundary indicates a system cap rather than a real payment.
SELECT
    ROUND(SUM(check_amount), 2)   AS total_spend,
    ROUND(AVG(check_amount), 2)   AS avg_check_amount,
    MIN(check_amount)             AS min_check_amount,
    MAX(check_amount)             AS max_check_amount,
    COUNT(*)                      AS total_rows,
    COUNT(check_amount)			  AS total_payments
FROM payments_raw;

-- 3. Baseline payee counts. distinct_payee_names_raw is the "before" figure
-- for the normalization work in 02; the blank/null count establishes whether
-- name cleanup has to handle missing values.
SELECT
	COUNT(payee_name) AS total_payee_names_raw,
	COUNT(DISTINCT payee_name) AS distinct_payee_names_raw,
	COUNT(CASE WHEN payee_name IS NULL
			OR TRIM(payee_name) = ''
			THEN 1 END)
	AS blank_or_null_payees,
	COUNT(DISTINCT associated_prime_vendor) AS distinct_prime_vendors_raw
FROM payments_raw;


-- 4. Spending category composition. Checked here because the field turns out
-- to be single-valued once non-procurement rows are removed, which is why the
-- fragmentation analysis in 03 uses expense_category instead.
SELECT
	spending_category,
	COUNT(*) AS payment_count,
	ROUND(SUM(check_amount), 2) AS total_spend
FROM payments_raw
GROUP BY spending_category
ORDER BY total_spend DESC;

-- 5. Fiscal year split, to confirm no adjacent-year rows leaked into the extract.
SELECT
    fiscal_year,
    COUNT(*)                    AS payment_count,
    ROUND(SUM(check_amount), 2) AS total_spend
FROM payments_raw
GROUP BY fiscal_year
ORDER BY fiscal_year;

-- 6. Agency concentration. Surfaces the pension and intergovernmental agencies
-- that dominate raw spend and are excluded during scoping.
SELECT
	agency,
	COUNT(*) AS payment_count,
	ROUND(SUM(check_amount), 2) AS total_spend
FROM payments_raw
GROUP by agency
ORDER by total_spend DESC
LIMIT 15;

-- 7. Largest payees by spend, pre-normalization. Establishes how concentrated
-- raw spend is before any cleaning, and surfaces the intergovernmental payees
-- (State of New York, NYCHA, NYPA) that the agency filter in 02 does not catch
-- because they are counterparties rather than agencies.
SELECT
	payee_name,
	COUNT(*) AS payment_count,
	ROUND(SUM(check_amount), 2) AS total_spend
FROM payments_raw
WHERE payee_name IS NOT NULL AND TRIM(payee_name) != ''
GROUP BY payee_name
ORDER BY total_spend DESC
LIMIT 20;


-- 8. Alphabetical payee scan. Sorting by name clusters punctuation, suffix and
-- spacing variants together, which is how the specific REPLACE rules in 02
-- were chosen.
SELECT
	payee_name,
	ROUND(SUM(check_amount), 2) AS total_spend
FROM payments_raw
WHERE payee_name IS NOT NULL AND TRIM(payee_name) != ''
GROUP BY payee_name
ORDER BY payee_name
LIMIT 100;
