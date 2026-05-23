# Architecture

## Design rationale

The pipeline follows a medallion architecture with four storage zones, each
serving a distinct purpose with its own access controls, retention policy,
and recovery path.

### Why four zones and not one bucket

A single-bucket design is operationally simpler but couples concerns that
benefit from separation:

| Concern | Why separation helps |
|---|---|
| **Regulatory** | Canadian tax authorities expect immutable retention of source evidence. Raw must be tamper-proof. |
| **Cost** | AWS Textract is the most expensive component. Isolating it in extraction means downstream business-rule changes do not re-trigger OCR. |
| **Auditability** | Bronze preserves what extraction produced. Silver shows what business rules changed. Gold is derived. The progression itself is the audit trail. |
| **Operational** | Each layer has different freshness requirements, ownership, and access patterns. |

### Recovery cost per zone

| Zone | Failure recovery |
|---|---|
| Raw | Bytes are immutable and version-protected. No recovery action needed. |
| Bronze | Re-execute the Glue Python Shell extraction job (~5 minutes plus Textract async time). |
| Silver | Re-execute the cleaning stage of the Visual ETL job from bronze (~2 minutes). |
| Gold | Re-execute the aggregation stage from silver (~2 minutes). |

## AWS services used

| Service | Role |
|---|---|
| **S3** | Storage for all four zones |
| **KMS** | Customer Managed Key for SSE-KMS encryption across all buckets |
| **IAM** | Least-privilege roles per stage (extraction job, crawler) |
| **Glue Python Shell** | Extraction code (Textract orchestration + pandas xlsx parsing) |
| **Glue Studio Visual ETL** | Bronze → Silver → Gold transformations |
| **Glue Data Catalog** | Schema registry for all tables |
| **Glue Crawler** | Automatic catalog updates when new bronze partitions arrive |
| **Athena** | SQL query interface over the gold reconciliation |
| **Textract** | Receipt and table extraction from PDFs |

## Region selection

`ca-central-1` was chosen for Canadian data residency. Both raw evidence and
curated derivatives remain within Canadian borders, simplifying audit review.
Other regions are technically supported but would introduce cross-border
data-transfer considerations.

## Extraction tool selection

Three sources, three tools:

| Source | Tool | Why |
|---|---|---|
| Fuel receipts (multi-page PDF) | Textract `start_expense_analysis` (async) | Pre-trained on receipts; returns named fields with per-field confidence; supports multi-page |
| Scanned distance log (multi-page PDF) | Textract `analyze_document` with TABLES (async) | Reconstructs row/column structure from image-only input; per-cell confidence |
| Trip log (xlsx) | `pandas.read_excel` | Structured input; only normalization needed, not OCR |

All three emit the same downstream schema with lineage columns attached.
Downstream layers are indifferent to the source format.

## Why visual ETL for transformation

The bronze → silver → gold transformation is built in Glue Studio Visual ETL
rather than as PySpark code. Three reasons:

1. **Auditability**: a non-engineering reviewer can inspect the canvas and
   verify the data flow without reading code.
2. **Maintainability**: business rule changes (which columns aggregate, which
   keys join) can be modified in the canvas without code review.
3. **Native catalog integration**: each S3 sink updates the Glue Data Catalog
   atomically with the underlying Parquet write.

For extraction, where logic is complex and brittle (regex patterns, multi-format
date parsing, Textract response shape handling), Python code is the better fit.
