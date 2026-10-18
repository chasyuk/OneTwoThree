from datetime import date, datetime
from typing import Any
from uuid import UUID

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
    HttpUrl,
    field_validator,
    model_validator,
)


def _blank_to_none(value: object) -> object:
    if isinstance(value, str) and not value.strip():
        return None
    return value


class ParticipantCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    name: str = Field(min_length=1, max_length=120)
    email: EmailStr

    @field_validator("email")
    @classmethod
    def lowercase_email(cls, value: str) -> str:
        return value.lower()


class ParticipantRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    email: str


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: str
    name: str | None


class UserUpdate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    name: str | None = Field(default=None, max_length=120)

    @field_validator("name", mode="before")
    @classmethod
    def blank_to_none(cls, value: object) -> object:
        return _blank_to_none(value)


class MeetingCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=5000)
    call_link: HttpUrl | None = None
    place: str | None = Field(default=None, max_length=255)
    starts_at: AwareDatetime
    ends_at: AwareDatetime
    participant_ids: list[UUID] = []

    @field_validator("description", "call_link", "place", mode="before")
    @classmethod
    def blank_to_none(cls, value: object) -> object:
        return _blank_to_none(value)

    @model_validator(mode="after")
    def require_call_link_or_place(self) -> "MeetingCreate":
        if self.call_link is None and self.place is None:
            raise ValueError("Provide a call link, a place, or both")
        return self

    @model_validator(mode="after")
    def ends_after_start(self) -> "MeetingCreate":
        if self.ends_at <= self.starts_at:
            raise ValueError("The meeting must end after it starts")
        return self


class MeetingRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    title: str
    description: str | None
    call_link: str | None
    place: str | None
    starts_at: datetime
    ends_at: datetime
    owner_id: UUID | None
    participants: list[ParticipantRead]
    created_at: datetime


class AgendaItemSchema(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    topic: str = Field(min_length=1)
    owner: str | None = None
    minutes: int | None = Field(default=None, ge=1, le=480)


class ActionItemSchema(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    task: str = Field(min_length=1)
    owner: str | None = None
    due: date | None = None


class AgendaCreate(BaseModel):
    items: list[AgendaItemSchema] = []
    action_items: list[ActionItemSchema] = []
    ai_suggestion: dict[str, Any] | None = None


class AgendaRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    meeting_id: UUID
    items: list[dict[str, Any]]
    action_items: list[dict[str, Any]]
    ai_suggestion: dict[str, Any] | None
    created_at: datetime
    updated_at: datetime
