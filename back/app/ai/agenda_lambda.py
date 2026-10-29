import base64
import json
import logging
import time
from datetime import date

from app.ai.agenda import PROMPT_VERSION, AgendaParseError, cost_usd, parse_agenda
from app.auth import verify_id_token
from app.config import settings

log = logging.getLogger()
log.setLevel(logging.INFO)

CORS_HEADERS = {
    "content-type": "application/json",
    "access-control-allow-origin": "*",
    "access-control-allow-headers": "Authorization,Content-Type",
    "access-control-allow-methods": "POST,OPTIONS",
}


def handler(event, context):
    http_method = (
        event.get("requestContext", {}).get("http", {}).get("method") or event.get("httpMethod") or ""
    ).upper()

    if http_method == "OPTIONS":
        return {
            "statusCode": 204,
            "headers": CORS_HEADERS,
            "body": "",
        }

    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    auth_header = headers.get("authorization", "")
    token = (
        auth_header.removeprefix("Bearer ").strip()
        if auth_header.startswith("Bearer ")
        else auth_header.strip()
    )

    try:
        if not settings.auth_enabled:
            from app.auth import LOCAL_IDENTITY

            user = LOCAL_IDENTITY
        else:
            user = verify_id_token(token)
    except Exception as e:
        log.warning("Authentication failed in agenda_lambda: %s", e)
        return {
            "statusCode": 401,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": f"Unauthorized: {e}"}),
        }

    raw_body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw_body = base64.b64decode(raw_body).decode("utf-8")

    try:
        body = json.loads(raw_body)
    except Exception:
        return {
            "statusCode": 400,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": "Invalid JSON body"}),
        }

    text = body.get("text", "")
    if len(text) > 10000:
        return {
            "statusCode": 413,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": "Text exceeds maximum length of 10,000 characters"}),
        }

    today_str = body.get("today")
    tz = body.get("tz", "UTC")
    try:
        today = date.fromisoformat(today_str) if today_str else date.today()
    except ValueError:
        today = date.today()

    started = time.monotonic()
    try:
        agenda, usage = parse_agenda(text, today, tz)
    except AgendaParseError as e:
        return {
            "statusCode": 422,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": str(e)}),
        }
    except Exception as e:
        log.exception("Error parsing agenda")
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": f"Parsing failed: {e}"}),
        }

    latency_ms = int((time.monotonic() - started) * 1000)
    cost = cost_usd(settings.PARSER_MODEL, usage)
    log_line = {
        "event": "agenda_parsed",
        "user": user.sub,
        "model": settings.PARSER_MODEL,
        "prompt_version": PROMPT_VERSION,
        **usage,
        "latency_ms": latency_ms,
        "cost_usd": cost,
    }
    log.info(json.dumps(log_line))

    return {
        "statusCode": 200,
        "headers": CORS_HEADERS,
        "body": json.dumps(
            {
                "agenda": agenda.model_dump(mode="json"),
                "model": settings.PARSER_MODEL,
                "prompt_version": PROMPT_VERSION,
            }
        ),
    }
