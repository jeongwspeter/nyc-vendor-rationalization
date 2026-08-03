# NYC Vendor Rationalization: Tail-Spend Consolidation Analysis

**New York City could realistically save ~$149M per year by consolidating tail-vendor spend** in consolidatable goods and general-services categories — $75M–$224M across a 5–15% benchmark range. The theoretical ceiling is ~$620M if every tail dollar were consolidatable, which it is not.

Just **797 vendors (4.3%) hold 80%** of the city's $31.0B addressable procurement spend. The other **17,626 vendors (95.7%) share the remaining $6.2B**. That tail also contains rents, legal settlements and human-services contracts that no volume agreement can touch, so the headline number counts only tail spend inside a rule-defined basket of 23 categories ($1.49B addressable). Both frames are reported. The 4x haircut against the ceiling is deliberate.

![NYC Vendor Rationalization dashboard](images/dashboard.png)

**[Interactive dashboard on Tableau Public](https://public.tableau.com/views/NYCVendorRationalization/Dashboard1)**

## The business question

A few large vendors carry most of a city's procurement dollars. Thousands of small suppliers share the rest. That long tail is expensive: every additional vendor means another contract to administer, more invoices to process, and no volume leverage.

> **If NYC consolidated its long tail of small suppliers, how much could it save per year?**

This is a standard procurement exercise — vendor rationalization, or tail-spend management (see [VOCABULARY.md](VOCABULARY.md)).

## Data and scope

**Source:** NYC Checkbook (checkbooknyc.com) citywide spending export, FY2025 (2024-07-01 to 2025-06-30), retrieved 2026-06-09. Four CSV parts, ~415 MB.

**Stack:** MySQL (local) + DBeaver, Tableau for the dashboard.

Gross spend is $49.40B. The analysis runs on $31.00B. Everything removed in between is documented, and the reasoning for each exclusion is in the cleaning decisions log:

| Stage | Rows | Spend | Removed |
|---|---|---|---|
| Raw extract | 1,560,597 | $49.40B | — |
| After scoping (pensions, negatives, placeholder caps) | 1,554,107 | $39.43B | 6,490 rows / $9.97B |
| After intergovernmental payee exclusions | 1,552,117 | $31.00B | 1,990 rows / $8.43B |
| **Analysis base** (`payments_normalized`) | **1,552,117** | **$31.00B** | 18,423 distinct vendors |

Two exclusions carry most of the difference and both are genuinely outside the question: $5.0B of placeholder values emitted by the pension system, and $8.43B of transfers to other governments and public authorities. The city cannot put its Medicaid obligation out to bid.

## Reproducing this analysis

1. Download the FY2025 citywide spending export from [checkbooknyc.com](https://www.checkbooknyc.com). The export tool splits large results into multiple CSV parts; place them in `Data/Raw/`. Raw data is not committed — it exceeds GitHub's file size limit.
2. The four `LOAD DATA LOCAL INFILE` statements in `00_load.sql` use paths relative to the repo root (`Data/Raw/…`); run the script from the repo root or substitute absolute paths.
3. Run the scripts in order against a local MySQL 8 instance. `LOAD DATA LOCAL INFILE` requires `local_infile` enabled server-side and a client reconnect afterward.
4. Each script ends with a reconciliation query. If a row count does not match the value stated in the comment, stop and re-run the load rather than continuing — a silently skipped malformed row will propagate into every figure downstream.

| File | Purpose |
|---|---|
| `00_load.sql` | Create the database and `payments_raw`, load the four CSV parts. Verified: MySQL totals match a direct sum of the source files to the penny |
| `01_profile.sql` | Profiling — row counts, date range, nulls, spend distribution, agency and payee concentration, duplicate-name scan |
| `02_normalize.sql` | Scope out non-procurement rows → `payments_scoped`; normalize payee names; entity-level exclusions → `payments_normalized` |
| `03_analysis.sql` | Pareto split, tail-spend KPI, category fragmentation, top vendors |

Block results are exported to `Exports/` as CSVs, which are what the Tableau workbook reads.

## Findings

**Profiling (01)**
- Exactly one fiscal year (FY2025), so the KPI is annual with no annualization needed.
- Zero null payment amounts. Clean load.
- 18,502 distinct raw payee names.
- Payment amounts run from **-$13.3M** (reversals/refunds) to exactly **$99,999,999.00**, a system cap used as a placeholder (50 rows, all pension funding, $5.0B total). Repeated round amounts (ten identical $43,000,000 checks) show large obligations paid in installments. This is why the unit of analysis is vendor-level sums, not individual checks.

**Scoping (02, stage 1)**
- Removed 6,490 rows (0.4% of rows) carrying **$9.97B (20% of dollars)**: pension contributions, negative amounts, and the $99,999,999 placeholders. A handful of rows carried a fifth of the money.
- **Biggest surprise:** the top remaining "vendors" were not vendors. **State of New York ($6.2B**, mostly Medicaid transfers), NYC Housing Authority, NY Power Authority, MTA Bus. These are intergovernmental transfers, not addressable procurement.
- Scoping rule: **exclude entities that are themselves governments or public authorities; keep nonprofits and companies holding competed contracts.** Borderline pass-throughs (charter schools, library subsidies) stay in. All of them are strategic-tier size, and the savings KPI touches only tail spend.

**Name normalization (02, stage 2)**
- Rule chain: uppercase → strip punctuation → collapse whitespace → drop leading "THE" → drop one trailing legal suffix (INC, LLC, CORP, …).
- Result: **18,502 → 18,428 distinct vendors, 74 aliases collapsed.** The aliases carried real money: School Specialty $26.9M, Wilson Language $14.7M, Imagine Learning $11.9M, each split across two spellings.
- **Precision over count.** An earlier suffix list also stripped identity-bearing words (FOUNDATION, GROUP, SERVICES, ASSOC) and falsely merged legally distinct entities — a Chamber of Commerce with its charitable Foundation, an LLC with an unrelated nonprofit. Removing those words cut the merge count from 77 to 74 and made every remaining merge defensible one by one.
- No fuzzy or edit-distance matching. On a spend file a false merge silently overstates one vendor and understates another, and neither error is visible downstream. NYC's vendor master proved clean enough that rule-based normalization was sufficient.

## Cleaning decisions log

| Exclusion | Why | Impact |
|---|---|---|
| Pension Contributions agency | Intergovernmental transfer, not procurement | part of $9.97B below |
| `check_amount <= 0` | Refunds and reversals, not outbound spend; $0 rows distort counts | -$82M negatives |
| `check_amount = 99,999,999` | System-cap placeholder values, all pension funding | 50 rows, $5.0B |
| **Subtotal (stage 1)** | | **6,490 rows / $9.97B removed; $39.43B remains** |
| Government and authority payees (State of NY, NYCHA, NYPA, MTA Bus, Office of Labor Relations) | Intergovernmental transfers that survived the agency filter; not addressable | 1,990 rows / **$8.43B** (21% of remaining dollars in 0.13% of rows) |
| **Final analysis table (`payments_normalized`)** | | **1,552,117 rows / 18,423 vendors / $31.00B** |

## Analysis results (03)

**Pareto and KPI (blocks 2–4)**
- 797 of 18,423 vendors (4.33%) cover exactly 80% of spend ($24.80B). The remaining 17,626 (95.67%) share $6.20B.
- **Ceiling KPI (block 4)**, all tail spend treated as addressable: $6,199,890,536 → savings at 5/10/15% = $310.0M / $620.0M / $930.0M.
- **Realistic KPI (block 8)**, tail spend within a rule-defined basket of **23 consolidatable goods and general-services categories**: **$1,491,973,800 addressable → $74.6M / $149.2M (headline) / $223.8M.** The basket came from a full scan of every expense category. Every category matching the rule is included, tiny ones too, so the basket is rule-defined rather than tuned to reach a number. Borderline categories were conservatively excluded with reasons recorded in the SQL: legal services (court-driven and specialized), telecom (utility-like, few suppliers), curriculum and professional development (genuinely ambiguous), and "Othr Serv and Chrgs - General" ($516M, an unclassifiable residual flagged as a data limitation).
- The 4x gap against the ceiling reflects that most tail dollars — rents, settlements, one-off payments, human-services contracts — are not consolidatable at all.
- Borderline pass-through entities kept at scoping (charter schools, libraries, UFT Welfare Fund) all landed in the strategic tier as predicted. None touch the tail the KPI is computed on.

**Where to consolidate (block 5, by `expense_category`)** — high vendor count, no dominant supplier, buyer-chosen goods and services:
1. **Contractual Services – General**: $1.30B / 1,985 vendors / largest supplier holds only 6.0%
2. **Supplies + Materials – General**: $1.04B / 3,853 vendors / largest supplier 11.8%. The textbook tail-spend category.
3. **Prof Serv – Other**: $730M / 1,326 vendors (caveat: largest supplier already at 26.7%)
4. **Equipment – General**: same pattern, further down the spend ranking

Ruled out despite fragmentation: Charter Schools ($3.4B, mandated per-pupil pass-throughs), Payments to Delegate Agencies, and homeless-services categories (social-service provider networks, not bundleable purchases). Maintenance & Operation of Infrastructure is already concentrated at 57%.

**Fragmented purchasing in action (blocks 6–7)**
- CDW Government: 48,208 separate payments from 48 different agencies, $399M. SHI International: 60 agencies. Dozens of agencies independently buying IT from the same suppliers.
- Name-cleanup payoff: School Specialty looked like two mid-size vendors. It is one $26.9M relationship, among 74 alias merges totaling $100M+.
- `spending_category` turned out to be single-valued ("Contracts") in the scoped data, so fragmentation analysis uses `expense_category` instead.

## Dashboard

Built in Tableau against the CSVs in `Exports/`. Layout in reading order: KPI tiles ($149M realistic, $620M ceiling) → Pareto curve with the flip marked at 797 vendors / 4.3% → Strategic-vs-Tail bars (4.33% of vendors against 80% of spend) → category chart, "Where the money is and what's consolidatable," colored by basket decision.

Chart rules:
- The category chart shows **all 23 target categories plus every excluded category ≥ $1B**. Excluded giants stay visible so the chart shows what the analysis chose not to count — Charter Schools sits at the top of the chart, in grey.
- The four smallest target categories round to **$0M at label precision**. The basket is rule-defined, so tiny matching categories are included rather than trimmed for appearance.
- The category chart scrolls rather than squeezing every bar above the fold. Everything decision-relevant sits at the top.

## Limitations

1. **Single fiscal year.** FY2025 only. No trend or repeat-purchase view. A vendor that looks like tail this year may be mid-ramp.
2. **The savings rate is a benchmark, not a result.** 5/10/15% is an industry sensitivity range applied to the addressable pot. The data determines the pot ($1.49B realistic, $6.20B ceiling); the rate is an assumption stated up front. Any other rate can be substituted and the KPI scales linearly.
3. **"Othr Serv and Chrgs - General" ($516M) is an unclassifiable residual.** Some of it is likely consolidatable, but the category label cannot say which part. Excluded from the basket and flagged rather than guessed at.
4. **An N/A expense category exists in the raw data.** Small dollars, below the category chart's display threshold. Kept in totals, unclassifiable for basket purposes.
5. **No fuzzy name matching.** Normalization is rule-based (case, punctuation, legal suffixes). Abbreviations and typos — "NY" against "New York" — are out of scope.
6. **The 80% Pareto cutoff is a convention.** The Strategic/Tail boundary at rank 797 is a stated choice, not a property of the data. Nearby cutoffs shift the split but not the conclusion.

---

*Companion doc: [VOCABULARY.md](VOCABULARY.md) — the procurement domain glossary behind the terms used here. A print-tuned one-page PDF of the dashboard is in `Data Viz/`.*
