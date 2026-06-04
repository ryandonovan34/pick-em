import uuid
from datetime import datetime, timezone

from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Week(SQLModel, table=True):
    """
    A slate of games within a group. For NFL this is a numbered week
    (e.g. "Week 12"); for World Cup this is a round (e.g. "Group Stage - Matchday 1").
    """

    __tablename__ = "weeks"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    group_id: uuid.UUID = Field(foreign_key="groups.id")
    week_number: int
    # Human-readable label shown in the app.
    label: str = Field(max_length=100)
    created_at: datetime = Field(default_factory=_utc_now)
