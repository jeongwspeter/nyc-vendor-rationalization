-- 00_load.sql
-- Builds payments_raw and loads the four NYC Checkbook extract files.
--
-- Source: NYC Checkbook spending export, retrieved 2026-06-09. The export
-- tool splits results into four parts; all four are loaded into one table.

CREATE DATABASE IF NOT EXISTS vendor_rationalization;
USE vendor_rationalization;

-- Dropped and recreated rather than truncated: schema changed several times
-- during development and TRUNCATE would have left stale columns in place.
DROP TABLE IF EXISTS payments_raw;

-- check_amount is DECIMAL, not FLOAT — this table has to reconcile to the
-- published source totals to the cent, and float drift over 1.5M rows would
-- make that impossible. Text widths are generous; the export documents no
-- maximum length for the payee and vendor fields.
CREATE TABLE payments_raw (
    agency                    VARCHAR(300),
    associated_prime_vendor   VARCHAR(500),
    check_amount              DECIMAL(18,2),
    document_id               VARCHAR(150),
    contract_id               VARCHAR(150),
    budget_code               VARCHAR(150),
    capital_project           VARCHAR(300),
    contract_purpose          VARCHAR(500),
    department                VARCHAR(300),
    emerging_business         VARCHAR(50),
    expense_category          VARCHAR(300),
    fiscal_year               VARCHAR(10),
    industry                  VARCHAR(300),
    issue_date                DATE,
    mwbe_category             VARCHAR(150),
    mocs_registered           VARCHAR(50),
    payee_name                VARCHAR(500),
    spending_category         VARCHAR(150),
    sub_contract_reference_id VARCHAR(150),
    sub_vendor                VARCHAR(500),
    woman_owned_business      VARCHAR(50)
);

-- LOAD DATA LOCAL INFILE needs local_infile enabled server-side; the client
-- connection must be re-established after this takes effect.
SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE 'Data/Raw/spending_10133_06092026_220004_part_0.csv'
INTO TABLE payments_raw
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(agency, associated_prime_vendor, check_amount, document_id, contract_id, budget_code,
 capital_project, contract_purpose, department, emerging_business, expense_category,
 fiscal_year, industry, issue_date, mwbe_category, mocs_registered, payee_name,
 spending_category, sub_contract_reference_id, sub_vendor, woman_owned_business);

LOAD DATA LOCAL INFILE 'Data/Raw/spending_10133_06092026_220004_part_1.csv'
INTO TABLE payments_raw
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(agency, associated_prime_vendor, check_amount, document_id, contract_id, budget_code,
 capital_project, contract_purpose, department, emerging_business, expense_category,
 fiscal_year, industry, issue_date, mwbe_category, mocs_registered, payee_name,
 spending_category, sub_contract_reference_id, sub_vendor, woman_owned_business);

LOAD DATA LOCAL INFILE 'Data/Raw/spending_10133_06092026_220004_part_2.csv'
INTO TABLE payments_raw
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(agency, associated_prime_vendor, check_amount, document_id, contract_id, budget_code,
 capital_project, contract_purpose, department, emerging_business, expense_category,
 fiscal_year, industry, issue_date, mwbe_category, mocs_registered, payee_name,
 spending_category, sub_contract_reference_id, sub_vendor, woman_owned_business);

LOAD DATA LOCAL INFILE 'Data/Raw/spending_10133_06092026_220004_part_3.csv'
INTO TABLE payments_raw
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(agency, associated_prime_vendor, check_amount, document_id, contract_id, budget_code,
 capital_project, contract_purpose, department, emerging_business, expense_category,
 fiscal_year, industry, issue_date, mwbe_category, mocs_registered, payee_name,
 spending_category, sub_contract_reference_id, sub_vendor, woman_owned_business);

-- Load reconciliation. Expected 1,560,597 rows against the source files.
-- Any shortfall here means a malformed row was silently skipped and the
-- load must be re-run before profiling.
SELECT COUNT(*) AS total_rows FROM payments_raw;
