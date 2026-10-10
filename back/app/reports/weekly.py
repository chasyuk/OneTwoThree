"""Weekly meetings report generator."""

from __future__ import annotations

import csv
import io
import re
from datetime import UTC, date, datetime, time, timedelta
from typing import TYPE_CHECKING

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.db import SessionLocal
from app.models import Meeting, User

if TYPE_CHECKING:
    from sqlalchemy.orm import Session

ISO_WEEK_RE = re.compile(r"^(\d{4})-W(\d{2})$")


def parse_iso_week(week_str: str) -> tuple[datetime, datetime, str]:
    """Parse an ISO week string like '2026-W40'.

    Returns (week_start_utc, week_end_utc, prior_week_str).
    week_start is Monday 00:00:00 UTC, week_end is Sunday 23:59:59.999999 UTC.
    """
    match = ISO_WEEK_RE.match(week_str.strip())
    if not match:
        raise ValueError(f"Invalid ISO week format: {week_str!r}. Expected YYYY-Www (e.g. '2026-W40').")

    year = int(match.group(1))
    week_num = int(match.group(2))
    if not (1 <= week_num <= 53):
        raise ValueError(f"ISO week number must be between 1 and 53, got {week_num}.")

    try:
        monday = date.fromisocalendar(year, week_num, 1)
    except ValueError as err:
        raise ValueError(f"Invalid ISO calendar week: {week_str}") from err

    sunday = date.fromisocalendar(year, week_num, 7)
    week_start = datetime.combine(monday, time.min, tzinfo=UTC)
    week_end = datetime.combine(sunday, time.max, tzinfo=UTC)

    prev_monday = monday - timedelta(days=7)
    prev_year, prev_week, _ = prev_monday.isocalendar()
    prev_week_str = f"{prev_year:04d}-W{prev_week:02d}"

    return week_start, week_end, prev_week_str


def _duration_hours(meeting: Meeting) -> float:
    diff = meeting.ends_at - meeting.starts_at
    return max(0.0, diff.total_seconds() / 3600.0)


def build_weekly_report(week: str, db: Session | None = None) -> bytes:
    """Query the meetings of one ISO week (e.g. "2026-W40") and return the CSV bytes.

    Minimum metrics included:
      - Number of meetings in that ISO week and total duration in hours
      - Same numbers for the week before and the change (diff)
      - Five longest meetings: title, start, duration, number of participants
      - Breakdown by organizer (owner)
    """
    week_start, week_end, prior_week_str = parse_iso_week(week)
    prior_start, prior_end, _ = parse_iso_week(prior_week_str)

    if db is None:
        with SessionLocal() as session:
            return _generate_report(
                session, week, week_start, week_end, prior_week_str, prior_start, prior_end
            )
    return _generate_report(db, week, week_start, week_end, prior_week_str, prior_start, prior_end)


def _generate_report(
    db: Session,
    week_str: str,
    week_start: datetime,
    week_end: datetime,
    prior_week_str: str,
    prior_start: datetime,
    prior_end: datetime,
) -> bytes:
    # 1. Query meetings for target week
    curr_query = (
        select(Meeting)
        .options(selectinload(Meeting.participants))
        .where(Meeting.starts_at >= week_start, Meeting.starts_at <= week_end)
        .order_by(Meeting.starts_at, Meeting.id)
    )
    curr_meetings = list(db.scalars(curr_query).all())

    # 2. Query meetings for prior week
    prior_query = (
        select(Meeting)
        .where(Meeting.starts_at >= prior_start, Meeting.starts_at <= prior_end)
    )
    prior_meetings = list(db.scalars(prior_query).all())

    curr_count = len(curr_meetings)
    curr_duration = sum(_duration_hours(m) for m in curr_meetings)
    prior_count = len(prior_meetings)
    prior_duration = sum(_duration_hours(m) for m in prior_meetings)

    count_diff = curr_count - prior_count
    duration_diff = curr_duration - prior_duration

    # 3. Five longest meetings
    longest_meetings = sorted(curr_meetings, key=_duration_hours, reverse=True)[:5]

    # 4. Breakdown by organizer (user)
    owner_ids = {m.owner_id for m in curr_meetings if m.owner_id is not None}
    users_by_id: dict[object, User] = {}
    if owner_ids:
        users = db.scalars(select(User).where(User.id.in_(owner_ids))).all()
        users_by_id = {u.id: u for u in users}

    user_stats: dict[str, dict[str, float | int | str]] = {}
    for m in curr_meetings:
        if m.owner_id and m.owner_id in users_by_id:
            u = users_by_id[m.owner_id]
            key = str(u.id)
            name = u.name or u.email
            email = u.email
        else:
            key = "unassigned"
            name = "Unassigned"
            email = "N/A"

        if key not in user_stats:
            user_stats[key] = {
                "name": name,
                "email": email,
                "count": 0,
                "duration": 0.0,
            }
        user_stats[key]["count"] = int(user_stats[key]["count"]) + 1
        user_stats[key]["duration"] = float(user_stats[key]["duration"]) + _duration_hours(m)

    # 5. Build CSV
    buf = io.StringIO()
    writer = csv.writer(buf, lineterminator="\n")

    # Section 1: Executive Summary
    writer.writerow(["SECTION", "EXECUTIVE SUMMARY"])
    writer.writerow(["Metric", "Value"])
    writer.writerow(["ISO Week", week_str])
    writer.writerow(["Week Start (UTC)", week_start.strftime("%Y-%m-%d %H:%M:%S")])
    writer.writerow(["Week End (UTC)", week_end.strftime("%Y-%m-%d %H:%M:%S")])
    writer.writerow(["Total Meetings", curr_count])
    writer.writerow(["Total Duration (hours)", f"{curr_duration:.2f}"])
    writer.writerow(["Prior Week", prior_week_str])
    writer.writerow(["Prior Week Meetings", prior_count])
    writer.writerow(["Prior Week Duration (hours)", f"{prior_duration:.2f}"])
    writer.writerow(["Meeting Count Change", f"{count_diff:+d}"])
    writer.writerow(["Duration Change (hours)", f"{duration_diff:+.2f}"])
    writer.writerow([])

    # Section 2: Top 5 Longest Meetings
    writer.writerow(["SECTION", "TOP 5 LONGEST MEETINGS"])
    writer.writerow(["Rank", "Title", "Start Time (UTC)", "Duration (hours)", "Participants Count"])
    if longest_meetings:
        for idx, m in enumerate(longest_meetings, start=1):
            writer.writerow([
                idx,
                m.title,
                m.starts_at.strftime("%Y-%m-%d %H:%M:%S") if m.starts_at else "N/A",
                f"{_duration_hours(m):.2f}",
                len(m.participants),
            ])
    else:
        writer.writerow(["No meetings recorded this week", "", "", "", ""])
    writer.writerow([])

    # Section 3: Breakdown by Organizer
    writer.writerow(["SECTION", "BREAKDOWN BY ORGANIZER"])
    writer.writerow(["Organizer Name", "Email", "Meeting Count", "Total Duration (hours)"])
    if user_stats:
        for stats in sorted(user_stats.values(), key=lambda s: s["count"], reverse=True):
            writer.writerow([
                stats["name"],
                stats["email"],
                stats["count"],
                f"{float(stats['duration']):.2f}",
            ])
    else:
        writer.writerow(["No organizer activity", "", "", ""])

    return buf.getvalue().encode("utf-8")
