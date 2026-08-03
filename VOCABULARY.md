# Procurement Vocabulary — Vendor Rationalization Project

Domain glossary. Each entry: what the term means, and how it shows up in THIS project.

---

## Core concepts (the project's spine)

**Procurement**
The business function that buys everything an organization needs from outside suppliers — negotiating contracts, selecting vendors, managing supplier relationships. In government it's heavily rule-bound (competitive bidding requirements).
*In this project:* the "client" persona. The whole analysis answers a question a procurement office would ask.

**Vendor rationalization**
Deliberately reducing the number of suppliers an organization buys from — consolidating purchases with fewer, better vendors to cut cost and administrative overhead.
*In this project:* the title and the recommendation. Interview line: "Vendor rationalization is answering: of our 18,000 suppliers, how many do we actually need?"

**Tail spend**
The long tail of small, unmanaged purchases spread across many low-value suppliers. Typically ~20% of dollars scattered across ~80% of vendors. Expensive per dollar: each tiny vendor still costs a contract, invoices, and admin work, and small orders get no volume discount.
*In this project:* the bottom-20%-of-spend vendor group after the Pareto split. Its total spend is the input to the savings KPI.

**Strategic vendors / strategic spend**
The small set of large suppliers covering the top ~80% of spend. Already consolidated by definition — these relationships are managed, negotiated, and necessary.
*In this project:* the top tier of the Pareto split. Excluded from the savings claim — there's no consolidation move left to make with them.

**Addressable spend**
The portion of spend a given lever can actually act on. Not all spend is negotiable — you can't "get a better rate" on a legal obligation.
*In this project:* tail spend = the spend addressable by consolidation. Also why pensions and intergovernmental transfers were scoped out entirely — they're not addressable by procurement at all.

**Pareto principle (80/20 rule) / Pareto analysis**
The empirical pattern that ~80% of effect comes from ~20% of causes. In spend data: a small share of vendors carries most of the dollars. Pareto analysis = rank items by value, take cumulative share, find the cutoff.
*In this project:* the method in 03_analysis.sql — rank vendors by spend, cumulative %, split at 80%.

**Spend analysis / spend cube**
The general practice of analyzing WHO buys WHAT from WHOM for how much — usually cut by vendor, category, and business unit (the three axes of the "spend cube").
*In this project:* what the whole pipeline is. This portfolio piece IS a spend analysis.

---

## Data-side terms

**Vendor master (data)**
The canonical list of suppliers in a financial system — names, IDs, addresses. When it's dirty (duplicates, name variants), every downstream report double-counts vendors.
*In this project:* NYC's payee names were the de facto vendor master. Finding: fairly clean — 18,502 → 18,428 after normalization (74 aliases). Interview line: "Cleanliness of the vendor master determines whether your vendor count is even real."

**Normalization / deduplication (dedup)**
Standardizing name strings (case, punctuation, legal suffixes like INC/LLC) so the same real-world entity groups under one key.
*In this project:* 02_normalize.sql. Key lesson learned: stripping identity-bearing words (FOUNDATION, GROUP) caused FALSE MERGES of legally distinct entities — precision beats a bigger cleanup number.

**Fuzzy matching**
Matching near-identical strings that aren't byte-identical after normalization (typos, abbreviations — "SVCS" vs "SERVICES"), using similarity algorithms. The step BEYOND rule-based normalization.
*In this project:* deliberately out of scope; worth naming as a known limitation / future improvement.

**Data scoping / exclusions**
Deciding which rows belong in the analysis at all, driven by the business question — not by whether data "looks valid."
*In this project:* removed pensions, negative amounts, $99,999,999 placeholder rows, and government/authority payees — ~$10B+ documented exclusions. Interview line: "The pension rows were perfectly valid data; they just weren't procurement."

**Intergovernmental transfer / pass-through**
Money moving between government entities (city → state Medicaid, city → housing authority) or funds an entity is legally required to forward (charter school per-pupil funding). Not negotiable, so not procurement.
*In this project:* the biggest scoping decision — STATE OF NEW YORK alone was $6.2B (16% of scoped spend) hiding in the payee list.

**Sensitivity analysis / stated assumption**
Showing how a result changes as an assumed input varies, instead of pretending one number is certain.
*In this project:* the 5% / 10% / 15% savings-rate range. The rate is an industry benchmark, NOT derived from the data — and saying so openly is the credibility move.

---

## Broader procurement terms (breadth for interviews)

**Spend under management** — the share of total spend that procurement actively manages/negotiates (vs. spend that just happens). Rationalization increases it.

**Maverick spend** — purchases made outside approved contracts/vendors ("rogue buying"). A major creator of tail spend.

**Category management** — organizing procurement by what is bought (IT, construction, food services) so each category gets a strategy and preferred vendors. Consolidation usually happens within a category: "we buy office supplies from 200 vendors; category strategy says use 3."

**Economies of scale / volume discount** — unit price falls as order size grows. The core mechanism behind consolidation savings.

**RFP (Request for Proposal) / competitive bidding** — the formal process of inviting vendors to compete for a contract. In government, often legally required above spend thresholds.

**P-card (procurement card)** — corporate credit card for small purchases; the usual real-world tool for handling the tiniest tail transactions cheaply instead of full contracts.

**Supplier relationship management (SRM)** — the ongoing management of strategic vendors (performance, negotiation, risk). Fewer vendors → more attention per vendor → better outcomes; a second, softer benefit of rationalization.

**Fiscal year (FY)** — a government's accounting year. NYC's runs July 1 – June 30; "FY2025" = 2024-07-01 → 2025-06-30. Why the KPI can say "annual" without adjustment.
