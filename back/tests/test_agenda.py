from datetime import date
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

from app.ai.agenda import (
    ActionItem,
    AgendaItem,
    AgendaParseError,
    ParsedAgenda,
    cost_usd,
    parse_agenda,
)
from app.ai.agenda_lambda import handler


def test_agenda_pydantic_schema():
    agenda = ParsedAgenda(
        title="Weekly Sync",
        starts_at="2026-10-19T10:00:00",
        duration_minutes=45,
        items=[
            AgendaItem(topic="Roadmap review", owner="Alice", minutes=20),
            AgendaItem(topic="Q&A", owner=None, minutes=None),
        ],
        action_items=[
            ActionItem(task="Send slides", owner="Alice", due=date(2026, 10, 23)),
        ],
        language="en",
    )
    dumped = agenda.model_dump(mode="json")
    assert dumped["title"] == "Weekly Sync"
    assert len(dumped["items"]) == 2
    assert dumped["items"][0]["owner"] == "Alice"
    assert dumped["action_items"][0]["due"] == "2026-10-23"


def test_agenda_cost_calculation():
    usage = {"input_tokens": 1000, "output_tokens": 200}
    # Haiku: 1000 * 0.10 / 1M + 200 * 0.50 / 1M = 0.00010 + 0.00010 = 0.00020
    cost_haiku = cost_usd("us.anthropic.claude-haiku-4-5-20251001-v1:0", usage)
    assert cost_haiku == 0.0002

    # Opus: 1000 * 4.00 / 1M + 200 * 20.00 / 1M = 0.004 + 0.004 = 0.008
    cost_opus = cost_usd("anthropic.claude-opus-5-5", usage)
    assert cost_opus == 0.008


def test_agenda_parse_mock():
    mock_client = MagicMock()
    mock_msg = MagicMock()
    mock_msg.usage.input_tokens = 100
    mock_msg.usage.output_tokens = 50

    tool_block = MagicMock()
    tool_block.type = "tool_use"
    tool_block.id = "tool-1"
    tool_block.input = {
        "title": "Mock Meeting",
        "starts_at": "2026-10-19T10:00:00",
        "duration_minutes": 30,
        "items": [{"topic": "Status update", "owner": "Bob", "minutes": 15}],
        "action_items": [],
        "language": "en",
    }
    mock_msg.content = [tool_block]
    mock_client.messages.create.return_value = mock_msg

    agenda, usage = parse_agenda("Mock meeting text", date(2026, 10, 19), "UTC", client=mock_client)
    assert agenda.title == "Mock Meeting"
    assert agenda.items[0].topic == "Status update"
    assert usage["input_tokens"] == 100


def test_agenda_parse_refusal():
    mock_client = MagicMock()
    mock_msg = MagicMock()
    mock_msg.usage.input_tokens = 50
    mock_msg.usage.output_tokens = 10
    mock_msg.content = []
    mock_msg.stop_reason = "refusal"
    mock_client.messages.create.return_value = mock_msg

    with pytest.raises(AgendaParseError, match="no agenda returned"):
        parse_agenda("Refused prompt", date(2026, 10, 19), "UTC", client=mock_client)


def test_agenda_api_endpoints(client: TestClient):
    # 1. Create a meeting
    meeting_resp = client.post(
        "/api/meetings",
        json={
            "title": "Meeting for Agenda",
            "starts_at": "2026-10-20T10:00:00Z",
            "ends_at": "2026-10-20T11:00:00Z",
            "place": "Room 101",
        },
    )
    assert meeting_resp.status_code == 201
    meeting_id = meeting_resp.json()["id"]

    # 2. Get agenda before creating -> 404
    get_empty = client.get(f"/api/meetings/{meeting_id}/agenda")
    assert get_empty.status_code == 404

    # 3. Save agenda
    save_resp = client.post(
        f"/api/meetings/{meeting_id}/agenda",
        json={
            "items": [{"topic": "Intro", "owner": "Dmytro", "minutes": 10}],
            "action_items": [{"task": "Prepare report", "owner": "Dmytro", "due": "2026-10-25"}],
            "ai_suggestion": {
                "model": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
                "prompt_version": "agenda-v1",
                "agenda": {"title": "Intro Meeting"},
            },
        },
    )
    assert save_resp.status_code == 200
    saved = save_resp.json()
    assert len(saved["items"]) == 1
    assert saved["items"][0]["topic"] == "Intro"
    assert saved["ai_suggestion"]["prompt_version"] == "agenda-v1"

    # 4. Get agenda after creating -> 200
    get_resp = client.get(f"/api/meetings/{meeting_id}/agenda")
    assert get_resp.status_code == 200
    assert get_resp.json()["id"] == saved["id"]


def test_agenda_lambda_handler_options():
    res = handler({"requestContext": {"http": {"method": "OPTIONS"}}}, None)
    assert res["statusCode"] == 204


def test_agenda_lambda_handler_limits():
    # Length limit: >10,000 chars -> 413
    long_text = "a" * 10001
    res = handler(
        {
            "requestContext": {"http": {"method": "POST"}},
            "headers": {"authorization": "Bearer dummy"},
            "body": f'{{"text": "{long_text}"}}',
        },
        None,
    )
    assert res["statusCode"] == 413
