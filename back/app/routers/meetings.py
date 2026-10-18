from uuid import UUID

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.schemas import AgendaCreate, AgendaRead, MeetingCreate, MeetingRead
from app.services import meetings as service

router = APIRouter(prefix="/meetings", tags=["meetings"])


@router.get("", response_model=list[MeetingRead])
def list_meetings(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return service.list_meetings(db, user)


@router.get("/{meeting_id}", response_model=MeetingRead)
def get_meeting(meeting_id: UUID, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return service.get_meeting(db, meeting_id, user)


@router.post("", response_model=MeetingRead, status_code=status.HTTP_201_CREATED)
def create_meeting(
    data: MeetingCreate, db: Session = Depends(get_db), user: User = Depends(get_current_user)
):
    return service.create_meeting(db, data, user)


@router.put("/{meeting_id}", response_model=MeetingRead)
def update_meeting(
    meeting_id: UUID,
    data: MeetingCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return service.update_meeting(db, meeting_id, data, user)


@router.delete("/{meeting_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_meeting(meeting_id: UUID, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    service.delete_meeting(db, meeting_id, user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/{meeting_id}/agenda", response_model=AgendaRead)
def get_agenda(meeting_id: UUID, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    agenda = service.get_agenda(db, meeting_id, user)
    if agenda is None:
        return Response(status_code=status.HTTP_404_NOT_FOUND)
    return agenda


@router.post("/{meeting_id}/agenda", response_model=AgendaRead)
def save_agenda(
    meeting_id: UUID,
    data: AgendaCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return service.save_agenda(db, meeting_id, data, user)
