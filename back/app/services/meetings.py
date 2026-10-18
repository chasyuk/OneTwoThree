from collections.abc import Sequence
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.models import Agenda, Meeting, Participant, User
from app.schemas import AgendaCreate, MeetingCreate
from app.services.errors import NotFoundError

# Meetings are personal: every query is scoped to the owner's user ID.


def list_meetings(db: Session, user: User) -> Sequence[Meeting]:
    query = (
        select(Meeting)
        .options(selectinload(Meeting.participants))
        .where(Meeting.owner_id == user.id)
        .order_by(Meeting.starts_at, Meeting.id)
    )
    return db.scalars(query).all()


def get_meeting(db: Session, meeting_id: UUID, user: User) -> Meeting:
    """Other users' meetings are reported as missing, so their IDs reveal nothing."""
    query = (
        select(Meeting)
        .options(selectinload(Meeting.participants))
        .where(Meeting.id == meeting_id, Meeting.owner_id == user.id)
    )
    meeting = db.scalar(query)
    if meeting is None:
        raise NotFoundError(f"Meeting {meeting_id} not found")
    return meeting


def _load_participants(db: Session, participant_ids: list[UUID]) -> list[Participant]:
    participant_ids = list(dict.fromkeys(participant_ids))
    if not participant_ids:
        return []
    participants = list(db.scalars(select(Participant).where(Participant.id.in_(participant_ids))))
    missing = set(participant_ids) - {p.id for p in participants}
    if missing:
        ids = ", ".join(sorted(str(m) for m in missing))
        raise NotFoundError(f"Participants not found: {ids}")
    return participants


def _apply(meeting: Meeting, data: MeetingCreate, participants: list[Participant]) -> None:
    meeting.title = data.title
    meeting.description = data.description
    meeting.call_link = str(data.call_link) if data.call_link else None
    meeting.place = data.place
    meeting.starts_at = data.starts_at
    meeting.ends_at = data.ends_at
    meeting.participants = participants


def create_meeting(db: Session, data: MeetingCreate, user: User) -> Meeting:
    meeting = Meeting(owner_id=user.id)
    _apply(meeting, data, _load_participants(db, data.participant_ids))
    db.add(meeting)
    db.commit()
    return get_meeting(db, meeting.id, user)


def update_meeting(db: Session, meeting_id: UUID, data: MeetingCreate, user: User) -> Meeting:
    meeting = get_meeting(db, meeting_id, user)
    _apply(meeting, data, _load_participants(db, data.participant_ids))
    db.commit()
    return get_meeting(db, meeting.id, user)


def delete_meeting(db: Session, meeting_id: UUID, user: User) -> None:
    db.delete(get_meeting(db, meeting_id, user))
    db.commit()


def get_agenda(db: Session, meeting_id: UUID, user: User) -> Agenda | None:
    meeting = get_meeting(db, meeting_id, user)
    query = select(Agenda).where(Agenda.meeting_id == meeting.id)
    return db.scalar(query)


def save_agenda(db: Session, meeting_id: UUID, data: AgendaCreate, user: User) -> Agenda:
    meeting = get_meeting(db, meeting_id, user)
    query = select(Agenda).where(Agenda.meeting_id == meeting.id)
    agenda = db.scalar(query)
    items_data = [item.model_dump(mode="json") for item in data.items]
    actions_data = [item.model_dump(mode="json") for item in data.action_items]
    if agenda is None:
        agenda = Agenda(
            meeting_id=meeting.id,
            items=items_data,
            action_items=actions_data,
            ai_suggestion=data.ai_suggestion,
        )
        db.add(agenda)
    else:
        agenda.items = items_data
        agenda.action_items = actions_data
        if data.ai_suggestion is not None:
            agenda.ai_suggestion = data.ai_suggestion
    db.commit()
    db.refresh(agenda)
    return agenda
