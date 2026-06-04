import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class WeekCreate(BaseModel):
    label: str


class WeekRead(BaseModel):
    id: uuid.UUID
    group_id: uuid.UUID
    week_number: int
    label: str
    created_at: datetime

    model_config = {"from_attributes": True}


class GameRead(BaseModel):
    id: uuid.UUID
    week_id: Optional[uuid.UUID]
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
