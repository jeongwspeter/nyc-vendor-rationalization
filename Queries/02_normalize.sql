-- 02_normalize.sql
-- Scoping and vendor-name normalization. Runs after 01_profile.sql.
--
-- Two stages: remove rows that are not addressable procurement, then collapse
-- payee-name variants so that spend attributed to one supplier is counted once.

USE vendor_rationalization;

-- STAGE 1 — Scoping
--
-- Three exclusions, all identified in profiling:
--   check_amount <= 0        refunds and reversals; not outbound spend
--   check_amount >= 99999999 placeholder cap emitted by the pension system,
--                            not a real payment of that size
--   agency = 'Pension Contributions'
--                            employee benefit transfers, not vendor procurement
--
-- These are exclusions of scope, not of inconvenience: each removes a category
-- of row that no procurement decision could act on. Dollar and row impact is
-- recorded below so the exclusions can be audited against the published totals.

DROP TABLE IF EXISTS payments_scoped;

CREATE TABLE payments_scoped AS
SELECT *
FROM payments_raw
WHERE check_amount > 0
AND check_amount < 99999999.00
AND agency != 'Pension Contributions';


-- Scope reconciliation: rows and dollars surviving stage 1.
SELECT
	COUNT(*) AS scoped_rows,
	COUNT(DISTINCT payee_name) AS distinct_payees_scoped,
	ROUND(SUM(check_amount), 2) AS scoped_spend
FROM payments_scoped;

SELECT * FROM payments_scoped LIMIT 20;

-- STAGE 2 — Normalization rules, validated before application
--
-- The chain uppercases, strips punctuation that varies between filings
-- (periods, commas, apostrophes, parentheses, hash, semicolon), converts
-- separators to spaces, expands "&" to "AND", collapses repeated whitespace,
-- drops a leading "THE", and removes a trailing legal-entity suffix.
--
-- Rules are deliberately conservative and character-level only. No fuzzy or
-- edit-distance matching: on a spend file, a false merge silently overstates
-- one vendor and understates another, and neither error is visible downstream.
-- Every rule below corresponds to a variant pattern observed in 01 block 8.
--
-- The suffix list is pure legal boilerplate. FUND, FOUNDATION, GROUP, SERVICES,
-- ASSOC and ASSOCIATES were in an earlier version and were removed: those words
-- carry identity, and stripping them merged legally distinct entities — a
-- Chamber of Commerce with its charitable Foundation, an LLC with an unrelated
-- nonprofit. That correction reduced merges from 77 to 74 and made each
-- remaining merge defensible one by one. Fewer merges, all of them right.
--
-- Applied to a sample first so the transformation can be inspected against the
-- raw value before it is written to a table.

SELECT DISTINCT payee_name AS raw_name,
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          TRIM(REGEXP_REPLACE(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
              UPPER(payee_name),
            '.', ''),
            ',', ''),
            '-', ' '),
            '&', ' AND '),
            '/', ' '),
            '(', ''),
            ')', ''),
            '''', ''),
            '#', ''),
            ';', '')
          , '\\s+', ' ')),
        '^THE ', ''),
      ' (LLC|LLP|INC|CORP|CORPORATION|INCORPORATED|LTD|LIMITED|LP|CO|COMPANY|PC|PLLC)$',
      '')
    ) AS vendor_norm
FROM payments_scoped
ORDER BY payee_name
LIMIT 20;


-- Normalization applied to the full scoped table. Columns not used downstream
-- are dropped here to keep the analysis table narrow.

DROP TABLE IF EXISTS payments_normalized;

CREATE TABLE payments_normalized AS
SELECT
    agency,
    payee_name,
    associated_prime_vendor,
    check_amount,
    document_id,
    contract_id,
    issue_date,
    fiscal_year,
    spending_category,
    department,
    expense_category,
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          TRIM(REGEXP_REPLACE(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
              UPPER(payee_name),
            '.', ''), ',', ''), '-', ' '), '&', ' AND '), '/', ' '),
            '(', ''), ')', ''), '''', ''), '#', ''), ';', '')
          , '\\s+', ' ')),
        '^THE ', ''),
      ' (LLC|LLP|INC|CORP|CORPORATION|INCORPORATED|LTD|LIMITED|LP|CO|COMPANY|PC|PLLC)$',
      '')
    ) AS vendor_norm
FROM payments_scoped;

-- Effect of normalization: raw distinct names against normalized distinct
-- names. The difference is the count of name variants collapsed.

SELECT
    (SELECT COUNT(DISTINCT payee_name)  FROM payments_scoped)   AS raw_distinct_names,
    (SELECT COUNT(DISTINCT vendor_norm) FROM payments_normalized) AS normalized_distinct_names,
    (SELECT COUNT(DISTINCT payee_name)  FROM payments_scoped) -
    (SELECT COUNT(DISTINCT vendor_norm) FROM payments_normalized) AS names_collapsed
;

-- Every merge the rules produced, listed with its source spellings. Reviewed
-- by hand: a normalization that cannot be shown to be correct case by case is
-- not defensible, and this is the artifact that shows it.

SELECT
    vendor_norm,
    COUNT(DISTINCT payee_name)      AS alias_count,
    GROUP_CONCAT(DISTINCT payee_name ORDER BY payee_name SEPARATOR ' | ') AS raw_aliases,
    ROUND(SUM(check_amount), 2)     AS total_spend
FROM payments_normalized
GROUP BY vendor_norm
HAVING alias_count > 1
ORDER BY alias_count DESC, total_spend DESC
LIMIT 30;

SELECT
    COUNT(*) AS final_rows,
    COUNT(DISTINCT vendor_norm) AS final_vendors,
    ROUND(SUM(check_amount), 2) AS final_spend
FROM payments_normalized;


-- Second-pass exclusion: intergovernmental transfers.
--
-- These five surfaced in the top-vendor ranking after normalization, not in
-- profiling, because they are payees rather than a distinguishable agency or
-- category. They are payments between public bodies — the largest is the State
-- of New York Medicaid obligation — and no consolidation decision applies to
-- them. Removed here rather than in the stage 1 predicate because they were
-- identified from normalized output that did not exist at that point.

DELETE FROM payments_normalized
WHERE vendor_norm IN (
	'STATE OF NEW YORK',
	'NEW YORK CITY HOUSING AUTHORITY',
	'NEW YORK POWER AUTHORITY',
	'MTA BUS',
	'CITY OF NEW YORK OFFICE OF LABOR RELATIONS'
);

-- Final reconciliation. This row count and total are what 03_analysis.sql
-- reports against.
SELECT
    COUNT(*) AS final_rows,
    COUNT(DISTINCT vendor_norm) AS final_vendors,
    ROUND(SUM(check_amount), 2) AS final_spend
FROM payments_normalized;
