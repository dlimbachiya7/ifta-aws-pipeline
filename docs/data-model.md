# Data Model

## Bronze layer

Typed Parquet output from extraction, one folder per source type. Each row
carries lineage and extraction confidence.

### `bronze_distance_logs`

Trip-level records extracted from both the Excel trip log and the scanned PDF
distance log.

| Column | Type | Description |
|---|---|---|
| trip_id | string | Surrogate key (hash of source SHA-256 + page/row) |
| trip_date | string | ISO date |
| trip_year, trip_month | int | Derived from trip_date |
| ifta_period | string | e.g., `2022Q2` |
| origin_raw, destination_raw | string | Source values, untouched |
| origin_city, destination_city | string | Cleaned values |
| origin_jurisdiction, destination_jurisdiction | string | Province codes |
| start_odometer, end_odometer | int | Vehicle odometer |
| total_km | int | Trip distance |
| src_uri | string | s3:// path to source file |
| src_sha256 | string | Immutable file fingerprint |
| src_page_or_row | string | `page=N` or `row=N` |
| extraction_method | string | `pandas_xlsx` or `textract_tables` |
| extraction_confidence | double | 0.0 to 1.0 |
| ingested_at, processed_at | timestamp | UTC |

### `bronze_distance_jurisdiction_km`

Long-format breakdown of kilometers per jurisdiction per trip. One row per
(trip, jurisdiction) pair where km > 0.

| Column | Type | Description |
|---|---|---|
| trip_id | string | Foreign key to trip |
| jurisdiction_code | string | Two-letter province code |
| km | double | Kilometers in that jurisdiction |
| ifta_period | string | Quarter |
| (lineage columns) | | Same as above |

### `bronze_fuel_invoices`

One row per fuel receipt (one receipt per PDF page).

| Column | Type | Description |
|---|---|---|
| fuel_purchase_id | string | Surrogate key |
| invoice_or_receipt_number | string | From Textract |
| transaction_date | string | ISO date |
| vendor_canonical | string | One of UFA, SHELL, ESSO, COSTCO, PETRO_CANADA, NORTHGATE |
| vendor_name_raw | string | Raw vendor text |
| vendor_province | string | Province inferred from address |
| jurisdiction_code | string | Same as vendor_province |
| litres | double | Quantity purchased |
| total_cost | double | Total amount |
| subtotal | double | Pre-tax subtotal |
| tax_total | double | Total tax |
| gst, hst, pst | double | Tax line components (currently null; can be parsed from line items) |
| (lineage columns) | | Same as above |

### `bronze_dim_jurisdiction`

Reference dimension for Canadian provinces and territories. Loaded from a
static seed file.

| Column | Type |
|---|---|
| jurisdiction_code | string |
| jurisdiction_name | string |
| country | string |
| ifta_member | boolean |
| tax_regime | string |

## Silver layer

Cleaned and conformed versions of the bronze tables. Filter rules applied,
quality flags attached.

### `silver_juris_km`

Bronze juris_km enriched with jurisdiction attributes from `bronze_dim_jurisdiction`,
filtered to `km > 0`. Adds `jurisdiction_name`, `ifta_member`.

### `silver_fuel`

Bronze fuel filtered to `litres > 0`. Schema otherwise matches bronze.

## Gold layer

Reconciled analytics tables.

### `gold_ifta_reconciliation`

The primary auditor query target. Aggregated kilometers and fuel by IFTA period
and jurisdiction, full outer joined.

| Column | Type | Description |
|---|---|---|
| ifta_period | string | e.g., `2022Q2` |
| jurisdiction_code | string | Two-letter province code |
| jurisdiction_name | string | Full name |
| sum(km) | double | Total km in jurisdiction in period |
| sum(litres) | double | Total litres purchased in jurisdiction in period |
| sum(total_cost) | double | Total spend |
| sum(gst), sum(hst), sum(pst) | double | Tax line totals |

## Design notes

### Why long-format jurisdiction km

The scanned distance log presents kilometers in wide format (one column per
province). The bronze layer pivots to long format because:

- Every quarterly query becomes a `GROUP BY`, not an `UNPIVOT`
- Adding a new IFTA jurisdiction requires no schema migration
- Joining to fuel (also keyed by jurisdiction) is straightforward

The cost is 7x the row count, which is negligible at audit volumes.

### Dimensions

`dim_jurisdiction` is static reference data, hand-curated, 13 rows for
Canadian provinces and territories. Not derived from facts.

`dim_vehicle` is intentionally absent. The provided evidence has no VIN or
vehicle identifier. In production this dimension would come from the
telematics platform (Geotab, ELD providers), keyed by VIN.
