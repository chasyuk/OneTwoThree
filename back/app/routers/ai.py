import json
import logging
import time
from datetime import date
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.ai.agenda import PROMPT_VERSION, AgendaParseError, cost_usd, parse_agenda
from app.auth import get_current_user
from app.config import settings
from app.models import User

router = APIRouter(prefix="/ai", tags=["ai"])
log = logging.getLogger("ai")


class ParseRequest(BaseModel):
    text: str = Field(max_length=10000)
    today: str | None = None
    tz: str = "UTC"


class ParseResponse(BaseModel):
    agenda: dict[str, Any]
    model: str
    prompt_version: str


@router.post("/parse-agenda", response_model=ParseResponse)
def parse_agenda_route(
    req: ParseRequest,
    user: User = Depends(get_current_user),
):
    try:
        today = date.fromisoformat(req.today) if req.today else date.today()
    except ValueError:
        today = date.today()

    started = time.monotonic()
    try:
        agenda, usage = parse_agenda(req.text, today, req.tz)
    except AgendaParseError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        log.exception("Error during local agenda parse")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Parsing failed: {exc}",
        ) from exc

    latency_ms = int((time.monotonic() - started) * 1000)
    cost = cost_usd(settings.PARSER_MODEL, usage)
    log.info(
        json.dumps(
            {
                "event": "agenda_parsed",
                "user": user.cognito_sub,
                "model": settings.PARSER_MODEL,
                "prompt_version": PROMPT_VERSION,
                **usage,
                "latency_ms": latency_ms,
                "cost_usd": cost,
            }
        )
    )

    return ParseResponse(
        agenda=agenda.model_dump(mode="json"),
        model=settings.PARSER_MODEL,
        prompt_version=PROMPT_VERSION,
    )
