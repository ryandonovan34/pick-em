import uuid
from datetime import date, datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Week(SQLModel, table=True):
    """
    A slate of games within a group. Anchored to a calendar week via
    starts_on (the Monday on/before the slate's first game); the system
    enforces that only games kicking off in that window can be added to the
    slate. The default window is Monday through the FOLLOWING Monday
    inclusive (starts_on + 7 days) — a real NFL week runs Thursday through
    Monday Night Football, which never fits a plain Mon-Sun 7-day span.
    """

    __tablename__ = "weeks"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    group_id: uuid.UUID = Field(foreign_key="groups.id")
    week_number: int
    label: str = Field(max_length=100)
    # Monday of the calendar week this slate covers (UTC date).
    # Nullable for legacy rows created before this field was added.
    starts_on: Optional[date] = Field(default=None)
    # Explicit end date for the slate window. Nullable — when unset, the API
    # falls back to starts_on + 7 days (Thursday through Monday Night
    # Football). Set this directly for slates that don't fit even that (e.g.
    # a playoff or holiday window spanning more than 8 days).
    ends_on: Optional[date] = Field(default=None)
    created_at: datetime = Field(default_factory=_utc_now)
