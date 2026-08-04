import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel


class WeekCreate(BaseModel):
    label: str
    # Raw date — NOT required to be a Monday. The router derives week_number
    # from this raw value (NFL weeks are Thursday-anchored) and separately
    # snaps the *stored* starts_on to that week's Monday. Deriving week_number
    # from an already-Monday-snapped date would misclassify dates near the
    # season boundary (snapping can cross the Thursday season-start line).
    starts_on: date
    ends_on: Optional[date] = None  # defaults to starts_on + 7 days if omitted
    # Explicit NFL week-number override (0=preseason, 1-18 regular season,
    # 19-22 playoffs). If omitted, derived from starts_on.
    week_number: Optional[int] = None


class WeekRead(BaseModel):
    id: uuid.UUID
    group_id: uuid.UUID
    week_number: int
    label: str
    starts_on: Optional[date] = None
    ends_on: Optional[date] = None   # explicit, falls back to starts_on + 6 days
    created_at: datetime
    first_kickoff_at: Optional[datetime] = None
    last_kickoff_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class GameRead(BaseModel):
    id: uuid.UUID
    odds_api_id: Optional[str]
    sport: str
    home_team: str
    away_team: str
    spread: float
    favorite_team: str
    kickoff_at: datetime
    home_score: Optional[int]
    away_score: Optional[int]
    result_posted: bool

    model_config = {"from_attributes": True}


class AddGameToSlate(BaseModel):
    odds_api_id: str
