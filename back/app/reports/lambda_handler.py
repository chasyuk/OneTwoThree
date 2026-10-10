"""Lambda entrypoint for report-builder.

Reuses the backend container image with command:
ImageConfig: { Command: ["app.reports.lambda_handler.handler"] }
"""

from __future__ import annotations

import json
import logging
import os
import sys
from datetime import UTC, datetime, timedelta
from typing import Any

import boto3

from app.reports.weekly import build_weekly_report

logger = logging.getLogger("report-builder")
logger.setLevel(logging.INFO)
if not logger.handlers:
    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(logging.Formatter("[%(levelname)s] %(message)s"))
    logger.addHandler(sh)


def detect_trigger(event: dict[str, Any]) -> str:
    """Identify which event source triggered the function."""
    if "Records" in event and event["Records"]:
        record = event["Records"][0]
        if record.get("eventSource") == "aws:sqs":
            return "sqs"
        if record.get("eventSource") == "aws:s3":
            return "s3"
    if event.get("source") in ("schedule", "aws.scheduler", "aws.events"):
        return "schedule"
    if "schedule" in str(event.get("detail-type", "")).lower() or "schedule" in str(event).lower():
        return "schedule"
    return "direct"


def get_previous_iso_week() -> str:
    """Compute previous ISO week string (e.g. '2026-W40')."""
    today = datetime.now(UTC)
    prev = today - timedelta(days=7)
    iso_year, iso_week, _ = prev.isocalendar()
    return f"{iso_year:04d}-W{iso_week:02d}"


def extract_week(event: dict[str, Any]) -> str:
    """Extract week from event payload or default to previous ISO week."""
    week = None

    # SQS Record
    if "Records" in event and event["Records"]:
        record = event["Records"][0]
        raw_body = record.get("body", "{}")
        try:
            body = json.loads(raw_body)
            if isinstance(body, dict):
                week = body.get("week")
        except (json.JSONDecodeError, TypeError):
            pass

    # Direct invocation
    if not week:
        week = event.get("week")

    if not week:
        week = get_previous_iso_week()

    return str(week)


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    trigger = detect_trigger(event)
    week = extract_week(event)

    # Required log line: must show which event started the function and the week
    logger.info(
        "report-builder triggered: trigger=%s week=%s",
        trigger,
        week,
        extra={"trigger": trigger, "week": week},
    )

    # Generate CSV
    csv_bytes = build_weekly_report(week)

    # Upload to S3
    bucket = os.environ.get("REPORTS_BUCKET")
    if not bucket:
        raise RuntimeError("REPORTS_BUCKET environment variable is not configured")

    key = f"reports/{week}.csv"
    s3 = boto3.client("s3")
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=csv_bytes,
        ContentType="text/csv",
    )

    logger.info("Report successfully uploaded to s3://%s/%s (%d bytes)", bucket, key, len(csv_bytes))

    return {
        "status": "ok",
        "trigger": trigger,
        "week": week,
        "bucket": bucket,
        "key": key,
        "bytes": len(csv_bytes),
    }
