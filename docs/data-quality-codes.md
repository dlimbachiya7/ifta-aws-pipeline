# Data Quality Codes

Quality concerns are recorded as data, not resolved by overwriting source
values. Each curated record carries a `dq_flags` array of codes that fired
during processing.

## Severity levels

| Severity | Meaning | Example action |
|---|---|---|
| **ERROR** | Data integrity issue requires investigation | Tax math discrepancy, jurisdiction sum mismatch |
| **WARN** | Quality concern that should be reviewed | Auto-corrected city spelling, low OCR confidence |
| **INFO** | Notable property worth tracking | Late-arriving evidence, duplicate filename |

## Codes

### Extraction quality

| Code | Severity | Description |
|---|---|---|
| DQ_EXTRACTION_LOW_CONFIDENCE | WARN | OCR confidence below threshold (default 0.85) |
| DQ_EXTRACTION_FAILED | ERROR | Extraction returned no usable output |
| DQ_OCR_CHARACTER_AMBIGUOUS | WARN | OCR returned a character with low confidence (0/O, 1/I, etc.) |

### Date and time

| Code | Severity | Description |
|---|---|---|
| DQ_MISSING_DATE | WARN | Date field empty |
| DQ_DATE_FORMAT_AMBIGUOUS | WARN | Date could be parsed multiple ways (e.g., 03-06-2016 — March or June?) |
| DQ_DATE_OUT_OF_RANGE | ERROR | Date outside the IFTA period under audit |

### Distance and odometer

| Code | Severity | Description |
|---|---|---|
| DQ_ODO_CHAIN_BREAK | WARN | start_odometer of trip N does not match end_odometer of trip N-1 |
| DQ_ODO_NEGATIVE_DISTANCE | ERROR | end_odometer < start_odometer |
| DQ_JURISDICTION_SUM_MISMATCH | ERROR | sum of per-jurisdiction km does not equal total_km |
| DQ_DISTANCE_IMPLAUSIBLE | WARN | total_km exceeds plausible daily distance |

### Location

| Code | Severity | Description |
|---|---|---|
| DQ_LOCATION_SPELLING_SUSPECT | WARN | City name fails canonical match; fuzzy-corrected (original preserved) |
| DQ_LOCATION_UNKNOWN_JURISDICTION | WARN | Location text could not be mapped to a known jurisdiction |

### Fuel and tax

| Code | Severity | Description |
|---|---|---|
| DQ_TAX_MATH_MISMATCH | ERROR | litres × price_per_litre ≠ total_cost by more than tolerance |
| DQ_TAX_COMPONENT_MISSING | WARN | Tax breakdown line missing (e.g., HST not parsed from receipt) |
| DQ_VENDOR_UNCANONICAL | WARN | Vendor name did not match any known canonical pattern |
| DQ_FUEL_NO_JURISDICTION | WARN | Fuel receipt has no inferable province |

## Implementation principle

When a quality concern is detected:

1. The cleaned value is written to the analytics column
2. The original value is preserved in a `*_raw` column
3. The code is appended to the `dq_flags` array
4. Both `_raw` and `dq_flags` travel with the record through silver and gold

This means an auditor can always answer "what changed and why" with a single
SELECT statement, with no external metadata or change log required.

## Validation signal

The `DQ_JURISDICTION_SUM_MISMATCH` code fires on exactly the rows that were
hand-highlighted yellow by a human reviewer on the original scanned distance
log. The pipeline flags what humans flag.
