# Hotel Performance Analytics
### End-to-End Data Engineering Project
**Stack:** AWS S3 → Snowflake (Medallion Architecture) → Power BI

---

## Dashboard Preview

![Hotel Performance Analytics Dashboard](C:\Users\ANMOL HAJNALE\Desktop\New folder\Review Project)

---

## Project Overview

A hotel chain had data scattered across 6 separate files on AWS S3 with no structured pipeline to consolidate and analyze it. Management had no way to answer basic business questions like which hotels are performing well or which guests are unhappy.

This project solves that by building a full data pipeline from raw source files into a single analytics mart, powering a Power BI dashboard that classifies all 100 hotels into performance bands based on revenue and guest satisfaction.

---

## Portfolio Stats

| Metric | Value |
|--------|-------|
| Total Hotels | 100 |
| Cities | New York, Houston, Chicago, Dallas, Los Angeles |
| Total Revenue | $47.3M |
| Total Bookings | 5,000 |
| Average Rating | 3.03 / 5 |
| High Value Bookings | 46.9% |

---

## Architecture — Medallion Layers

```
AWS S3 (6 source files)
     ↓
Bronze  →  hotel_dw.raw       (exact copy, no transformation)
     ↓
Silver  →  hotel_dw.staging   (cleaned, deduplicated, typed)
     ↓
Silver  →  hotel_dw.core      (SCD dimensions + incremental facts)
     ↓
Gold    →  hotel_dw.mart      (pre-aggregated, analytics-ready)
     ↓
Power BI Dashboard
```

---

## Data Sources

| File | Format | Volume |
|------|--------|--------|
| Bookings | CSV | 5,050 records |
| Customers | CSV | 500 records |
| Hotels | CSV | 100 hotels |
| Staff | XLSX | 100 records |
| Reviews | JSON | 5,000 records |
| RoomRates | JSON | 5,000 records |

---

## Pipeline — Layer by Layer

### RAW Layer (Bronze)
- Source files loaded into Snowflake raw tables using COPY INTO
- APPEND_ONLY Streams created on each raw table to capture new rows for CDC

### Staging Layer (Silver Part 1)
- Stored procedure `sp_load_staging()` reads from streams and cleans data
- Deduplication using ROW_NUMBER() — keeps most recent record per business key
- Type casting, null handling, regex cleaning applied

### Core Layer (Silver Part 2)
**Dimensions — SCD Implementation:**

| Table | SCD Type | Tracked Columns |
|-------|----------|-----------------|
| dim_hotels | Type 1 | All columns (overwrite) |
| dim_customers | Type 2 | name, email, phone, city |
| dim_staff | Type 2 | role, shift |
| dim_room_rates | Type 2 | price, discounted_price, is_available |

**Facts — Incremental MERGE (CDC):**
- `fact_bookings` and `fact_reviews` loaded using MERGE
- New records inserted, changed records updated, unchanged records skipped

### Mart Layer (Gold)
- `mart_hotel_performance` — one row per hotel, lifetime aggregated performance
- Pre-aggregated subqueries used to prevent fan-out problem
- Full refresh on every pipeline run

---

## Mart — mart_hotel_performance

**Grain:** One row per hotel — lifetime performance

**Source Tables:** dim_hotels, fact_bookings, fact_reviews, dim_staff

**Key Columns:**

| Column | Source | Description |
|--------|--------|-------------|
| total_revenue | fact_bookings | Sum of all booking amounts |
| total_bookings | fact_bookings | Count of all bookings |
| avg_booking_value | fact_bookings | Average amount per booking |
| high_value_pct | fact_bookings | % of premium bookings |
| avg_stay_days | fact_bookings | Average nights per booking |
| avg_rating | fact_reviews | Average guest rating (1-5) |
| positive_pct | fact_reviews | % of positive sentiment reviews |
| total_staff | dim_staff | Current active staff count |

---

## Fan-Out Problem & Fix

**Problem:** Direct join of fact_bookings × fact_reviews × dim_staff multiplied rows.
```
10 bookings × 3 reviews × 5 staff = 150 rows
SUM(revenue) across 150 rows = $86M (wrong — should be $47.3M)
```

**Fix:** Pre-aggregate each fact table to one row per hotel in a subquery before joining to dim_hotels. Guarantees no row multiplication.

---

## Performance Band Classification (DAX)

Hotels classified into 4 bands using revenue ($520K threshold) and rating (3.0 threshold):

| Band | Revenue | Rating | Count |
|------|---------|--------|-------|
| ⭐ Top Performer | ≥ $520K | ≥ 3.0 | 10 (10%) |
| ⚠️ At Risk | ≥ $520K | < 3.0 | 17 (17%) |
| 💎 Hidden Gem | < $520K | ≥ 3.0 | 44 (44%) |
| 🔴 Needs Attention | < $520K | < 3.0 | 28 (29%) |

Threshold of $520K chosen just above portfolio average ($472,884).

---

## Power BI Dashboard

**Connection:** DirectQuery to Snowflake mart_hotel_performance

**Visuals:**
- KPI Cards — Total Revenue, Total Bookings, Avg Rating, High Value %
- Revenue by City (Bar Chart)
- Rating vs Revenue — Performance Quadrant (Scatter Chart)
- Performance Band Distribution (Donut Chart)
- Hotel Performance Rankings (Table)

**Filters:** City slicer, Star Rating slicer

---

## Key Business Insights

1. **Houston leads** at $10.5M — highest revenue city
2. **Los Angeles lowest** at $6.7M — only 703 bookings vs 1,000+ in other cities
3. **44% Hidden Gems** — biggest growth opportunity, good ratings but underpriced
4. **17% At Risk** — earning well but low ratings, urgent service quality intervention needed
5. **46.9% High Value Bookings** — nearly half of customers are premium segment

---

## Technical Challenges Solved

| Challenge | Root Cause | Fix |
|-----------|------------|-----|
| is_high_value all NULL | CASE compared lowercase after UPPER() | Changed to 'YES'/'NO' |
| Revenue showing $86M | Fan-out from direct multi-table join | Pre-aggregated subqueries |
| Shift field not cleaned | Regex missing uppercase range | Fixed to [^A-Za-z ] |
| JSON files failing | Loaded as CSV format | type=json, strip_outer_array=true |
| Sentiment counts zero | Stored as 'Positive' but compared 'positive' | Added LOWER() |
| Streams empty after reload | Stream consumed before staging ran | Re-inserted raw data to repopulate |

---

## Project Files

```
01_snowflake_setup.sql        — database, schemas, roles, warehouse setup
02_raw_tables_snowpipe.sql    — raw table DDLs and COPY INTO commands
03_streams.sql                — APPEND_ONLY stream creation
04_staging_sp.sql             — sp_load_staging() stored procedure
05_core_dimensions_sp.sql     — sp_load_dimensions() with SCD logic
06_core_facts_sp.sql          — sp_load_facts() with MERGE logic
07_mart_tables.sql            — mart_hotel_performance query
Hotel_Performance_Analytics.pptx  — project presentation (12 slides)
Hotel_Performance_Analytics.docx  — full project documentation
```

---

## Setup Instructions

1. Create a Snowflake account (free trial available at snowflake.com)
2. Run `01_snowflake_setup.sql` to create database, schemas, roles
3. Run `02_raw_tables_snowpipe.sql` to create raw tables
4. Run `03_streams.sql` to create streams
5. Load your source data into raw tables
6. Run `04_staging_sp.sql` → call `sp_load_staging()`
7. Run `05_core_dimensions_sp.sql` → call `sp_load_dimensions()`
8. Run `06_core_facts_sp.sql` → call `sp_load_facts()`
9. Run `07_mart_tables.sql` to create mart
10. Connect Power BI to Snowflake via DirectQuery

---

## Tech Stack

- **Storage:** AWS S3
- **Data Warehouse:** Snowflake
- **Pipeline:** Snowflake Stored Procedures (SQL)
- **CDC:** Snowflake APPEND_ONLY Streams + MERGE
- **SCD:** Type 1 (dim_hotels) + Type 2 (dim_customers, dim_staff, dim_room_rates)
- **Visualization:** Microsoft Power BI (DirectQuery)
