import re
from datetime import UTC, datetime

import pytest
from sqlalchemy import text

from app.models import Meeting, Participant, User
from app.reports.weekly import build_weekly_report, parse_iso_week
from tests.conftest import TestingSession, engine


def test_parse_iso_week_valid():
    start, end, prev_week = parse_iso_week("2026-W40")
    assert start.isoformat() == "2026-09-28T00:00:00+00:00"
    assert end.isoformat() == "2026-10-04T23:59:59.999999+00:00"
    assert prev_week == "2026-W39"


def test_parse_iso_week_invalid():
    with pytest.raises(ValueError, match="Invalid ISO week format"):
        parse_iso_week("invalid-week")

    with pytest.raises(ValueError, match="ISO week number must be between 1 and 53"):
        parse_iso_week("2026-W60")


def test_build_weekly_report_empty():
    with TestingSession() as session:
        csv_bytes = build_weekly_report("2026-W40", db=session)
        csv_text = csv_bytes.decode("utf-8")
        assert "ISO Week,2026-W40" in csv_text
        assert "Total Meetings,0" in csv_text
        assert "Total Duration (hours),0.00" in csv_text


def test_build_weekly_report_with_meetings():
    with TestingSession() as session:
        # Create a user
        user = User(
            cognito_sub="sub-test-reports",
            email="report_user@example.com",
            name="Report Tester",
        )
        session.add(user)
        session.flush()

        # Create participants
        p1 = Participant(name="Alice", email="alice@example.com")
        p2 = Participant(name="Bob", email="bob@example.com")
        session.add_all([p1, p2])
        session.flush()

        # Meeting in 2026-W40 (e.g. 2026-09-29)
        m1 = Meeting(
            title="Big Sprint Planning",
            starts_at=datetime(2026, 9, 29, 10, 0, tzinfo=UTC),
            ends_at=datetime(2026, 9, 29, 12, 30, tzinfo=UTC),  # 2.5 hours
            owner_id=user.id,
            participants=[p1, p2],
        )
        # Meeting in prior week 2026-W39 (e.g. 2026-09-22)
        m_prev = Meeting(
            title="Previous Standup",
            starts_at=datetime(2026, 9, 22, 10, 0, tzinfo=UTC),
            ends_at=datetime(2026, 9, 22, 11, 0, tzinfo=UTC),  # 1.0 hour
            owner_id=user.id,
            participants=[p1],
        )
        session.add_all([m1, m_prev])
        session.commit()

        csv_bytes = build_weekly_report("2026-W40", db=session)
        csv_text = csv_bytes.decode("utf-8")

        assert "Total Meetings,1" in csv_text
        assert "Total Duration (hours),2.50" in csv_text
        assert "Prior Week Meetings,1" in csv_text
        assert "Prior Week Duration (hours),1.00" in csv_text
        assert "Meeting Count Change,+0" in csv_text
        assert "Duration Change (hours),+1.50" in csv_text
        assert "Big Sprint Planning" in csv_text
        assert "Report Tester,report_user@example.com,1,2.50" in csv_text

    # Cleanup
    with engine.begin() as conn:
        conn.execute(text("TRUNCATE meeting_participants, agendas, meetings, participants, users CASCADE"))


def test_lambda_handler_helpers():
    from app.reports.lambda_handler import detect_trigger, extract_week

    # SQS record
    sqs_event = {
        "Records": [
            {
                "eventSource": "aws:sqs",
                "body": '{"week": "2026-W38", "source": "schedule"}',
            }
        ]
    }
    assert detect_trigger(sqs_event) == "sqs"
    assert extract_week(sqs_event) == "2026-W38"

    # Schedule event
    schedule_event = {"source": "schedule", "week": None}
    assert detect_trigger(schedule_event) == "schedule"
    # Null week should default to previous ISO week
    week = extract_week(schedule_event)
    assert re.match(r"^\d{4}-W\d{2}$", week)

    # Direct event
    direct_event = {"week": "2026-W35"}
    assert detect_trigger(direct_event) == "direct"
    assert extract_week(direct_event) == "2026-W35"
