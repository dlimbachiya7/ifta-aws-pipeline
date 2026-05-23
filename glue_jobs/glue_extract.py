"""IFTA evidence extraction as a Glue Python Shell job.

Reads evidence files from S3 raw layer, extracts structured data using:
  - AWS Textract start_expense_analysis (async) for fuel invoice PDFs
  - AWS Textract start_document_analysis (async, TABLES) for scanned distance log PDFs
  - pandas read_excel for xlsx distance logs

Writes typed Parquet to the bronze layer, one folder per source type.
"""
from __future__ import annotations

import hashlib
import os
import re
import sys
import tempfile
import time
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

import boto3
import pandas as pd

from awsglue.utils import getResolvedOptions

args = getResolvedOptions(sys.argv, ['RAW_BUCKET', 'BRONZE_BUCKET', 'BRONZE_PREFIX'])
RAW_BUCKET = args['RAW_BUCKET']
BRONZE_BUCKET = args['BRONZE_BUCKET']
BRONZE_PREFIX = args['BRONZE_PREFIX'].strip('/') + '/'
REGION = os.environ.get('AWS_REGION', 'ca-central-1')

s3 = boto3.client('s3', region_name=REGION)
textract = boto3.client('textract', region_name=REGION)

print(f"[INIT] raw={RAW_BUCKET} bronze={BRONZE_BUCKET}/{BRONZE_PREFIX} region={REGION}")


def sha256_of_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def lineage_block(source_uri, source_sha256, page_or_row_ref, extraction_method, confidence):
    now = datetime.now(timezone.utc).isoformat()
    return {
        'src_uri': source_uri, 'src_sha256': source_sha256, 'src_page_or_row': page_or_row_ref,
        'extraction_method': extraction_method, 'extraction_confidence': float(confidence),
        'ingested_at': now, 'processed_at': now,
    }


def parse_date_safe(s):
    if s is None or (isinstance(s, float) and pd.isna(s)):
        return None, None
    if isinstance(s, (datetime, pd.Timestamp)):
        d = s
    else:
        s = str(s).strip()
        if not s:
            return None, None
        d = None
        for fmt in ('%Y-%m-%d', '%d/%m/%Y', '%d/%m/%y', '%m/%d/%Y', '%Y/%m/%d', '%d-%b-%Y', '%d-%b-%y'):
            try:
                d = datetime.strptime(s, fmt)
                break
            except ValueError:
                continue
        if d is None:
            return None, None
    iso = d.strftime('%Y-%m-%d')
    q = (d.month - 1) // 3 + 1
    return iso, f"{d.year}Q{q}"


def to_float(text):
    if not text:
        return None
    cleaned = re.sub(r'[^\d.\-]', '', str(text))
    try:
        return float(cleaned) if cleaned else None
    except ValueError:
        return None


# Remaining code omitted for brevity in this generated file example.
# Paste the rest of your original script below this section.
