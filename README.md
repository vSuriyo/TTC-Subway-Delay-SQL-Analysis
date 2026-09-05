# TTC Subway Delay Analysis | SQL Data Analytics Project

*A SQL-based data cleaning and exploratory analysis of 40,000+ Toronto Transit Commission (TTC) subway delay records — uncovering where, when, and why the subway breaks down, and what the TTC could do about it. reserve 99.6 of Data after cleaning (Jan 2025 - July 2026 Dataset)*

## Project Overview

As a Toronto-based data analyst (and regular subway rider), I wanted to put real analytical rigor behind a dataset I interact with. This project takes a raw export of TTC subway delay incidents from January 2025 to July 2026 from a messy source table to a clean, analysis-ready one, then answers questions a transit service-planning team would actually care about: which stations and lines lose the most time to delays, when delays spike seasonally, and which incident types are really driving the numbers.

The work is split into three stages — database setup, data cleaning, and exploratory analysis — each documented in its own SQL script below.

## Dataset

- **Source:** Official TTC subway delay incident logs, originally published via the [City of Toronto Open Data Portal](https://open.toronto.ca/dataset/ttc-subway-delay-data/), consolidated into a single extract (with an accompanying incident-code glossary) by transit writer [Steve Munro](https://stevemunro.ca/2026/06/03/reviewing-subway-delay-data-2025-2026/)
- **Size:** 40,656 delay records since January 2025 - July 2026
- **Fields:** report date/time, day of week, station, subway line, direction (`bound`), incident type code, delay minutes (`min_delay`), gap minutes (`min_gap`)
- **Licence:** [Open Government Licence – Toronto](https://open.toronto.ca/open-data-licence/)

## Tech Stack

`MySQL` / `MariaDB` | CTEs | Window Functions | Transactions | Aggregation & Grouping | Ranking Functions | Pareto Analysis |


## Repository Structure

```
├── 01_create_database.sql    # Schema, raw data load, staging table
├── 02_data_cleaning.sql      # Completeness audit, imputation, standardization
├── 03_data_exploration.sql   # Trend, ranking, root-cause & Pareto analysis
└── README.md                 # You're here
```


## Methodology

### 1. Database Setup
Loaded the raw CSV into a `_raw` table matching the source schema, then built a `stg_subway` staging table so all cleaning happens on a working copy — the raw import stays untouched as a reference point.

### 2. Data Cleaning
Started with a completeness audit across all 11 columns. Every field was fully populated except two: `bound` (14,179 blank, ~35%) and `line` (143 blank, ~0.4%).

- **`line`:** Cross-referenced the blank rows against `incident_code` and `min_delay`. All but 2 of the 143 had zero recorded delay — safe to drop as noise. The remaining 2 were fixed by hand, using the reporting station to infer the correct subway line.
- **`bound`:** Found that roughly 97% of delay-minutes among the top 15 incident codes came from incidents that halt service in *both* directions. Used that pattern together with the `line` column to impute the missing direction (Yonge–University → N/S, Bloor–Danforth/Sheppard → W/E) inside a transaction, then manually resolved the small number of leftover cases (2 values).
- **Standardization:** Normalized inconsistent `line` labels (e.g. "LINE 1", "LINE 2" variants) to canonical line codes, and removed residual rows belonging to non-subway services (shuttle buses, the defunct SRT, maintenance subway lines and LRT (light rail trains) lines; any delayed service that fall outside the main subway) so they wouldn't double-count delays already recorded elsewhere.

The result, `stg_subway_clean`, is analysis-ready — a small fraction of rows were removed (zero-delay noise and non-subway-line records), preserving 99.6% of the original 40,656 for analysis.

### Incident Code Investigation
One important part of the cleaning process was understanding the meaning of TTC incident codes.
Several commonly occurring incident categories included:

- **PUTWZ** — Work zone-related problems
- **MUIR / MUIS / MUI** — Injured or ill customer incidents
- **SUAP / SUAE** — Assault-related incidents
- **PUCSS** — Central Office-related incidents
- **MUPAA** — No trouble found
- **MUSAN** — Unsanitary vehicle
- **SUO** — Other security-related incidents
- **SUG** — Graffiti
- **SUDP** — Disorderly patrons
- **MUO** — Miscellaneous incidents
- **EUDO** — Door or equipment-related problems
- **SUTT** — Unauthorized track-level access
- **SUPOL** — Police-related incidents not directly caused by TTC operations
Incident code reference:
[https://stevemunro.ca/wp-content/uploads/2026/06/ttc-subway-delay-data-consolidated-by-code.pdf](https://stevemunro.ca/wp-content/uploads/2026/06/ttc-subway-delay-data-consolidated-by-code.pdf)

### 3. Exploratory Analysis
- **Monthly trends** — `LAG`/`LEAD` window functions to compute month-over-month % change in total delay minutes; Percentage change in Calculations
- **Station & line ranking** — `RANK()` partitioned by line to surface the most delay-prone stations on each line
- **Root-cause drill-down** — incident codes grouped by station for the top offenders, with each code's share of that station's total delay time
- **Pareto analysis** — cumulative-sum window functions to identify which incident types account for the bulk of total delay minutes (the classic 80/20 view)
## Key Findings

- **Within Kipling's incident mix, MUTO** — Miscellaneous Transportation, Other (Employee Non-Chargeable) — is the most frequently recorded code, though it ranks second by total delay minutes. It covers administrative or staffing-related transportation needs, such as crew changeovers, rather than mechanical faults or passenger-caused incidents. Individually, these delays are short: 340 recorded incidents account for 1,263 delay minutes, an average of about 3.7 minutes each. But at that frequency, the time adds up — which points to a specific, low-drama opportunity: streamlining these routine staffing transfers could meaningfully cut into Kipling's overall delay total and reported incidents.

- **Seasonality outweighs ridership.** Delay minutes peak in winter and taper off through spring into summer. September — Ontario's back-to-school month, when ridership rebounds — has the *lowest* total delay minutes of the year, suggesting weather drives system-wide delay (outside of rowdy passengers) more than passenger volume.

- **The major interchange stations run on a third pattern entirely.** St. George, Bloor, and Kennedy are dominated by SUDP (disorderly patron) and SUO (security, other) incidents — not weather, nor mechanical failure.

- **Security and behavioral incidents outrank equipment failure system-wide.** Disorderly-conduct/security codes account for roughly 3 of the top 4 delay categories by total minutes, and injury-related incidents make up about 2 of the top 5. The first mechanical issues like door faults rank much lower (6th) — people, not machines, are the bigger lever here.

## Recommendations

1. **Prioritize winter/weather mitigation at Victoria Park** — track de-icing and weather-hardening measures where they'll have the clearest payoff.
2. **Review end-of-line turnaround and servicing procedures at Kipling** to see whether staffing or scheduling changes could shrink servicing-related delay.
3. **Add station-level security and crowd-management resourcing at St. George, Bloor, and Kennedy**, where disorderly conduct — not mechanical failure — is the main delay driver.


## Skills Demonstrated

- **SQL (MySQL/MariaDB):** CTEs, window functions (`RANK`, `LAG`, `LEAD`, cumulative `SUM() OVER`), `CASE`-based transformations, transactions, string cleaning (`TRIM`, `COALESCE`, `UPPER`, pattern matching), `NULLIF` for safe division
- **Data quality & cleaning:** completeness auditing, evidence-based missing-value imputation, categorical standardization, staging-table workflow to protect raw data
- **Analysis:** trend analysis, ranking/segmentation, root-cause analysis, Pareto (80/20) analysis
- **Communication:** translating query output into stakeholder-relevant findings and recommendations


## About This Project

Part of my data analyst portfolio. I have a background in physics and I'm currently looking for junior–intermediate Data Analyst roles in Toronto.
