import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class PickCreate(BaseModel):
    game_id: uuid.UUID
    group_id: uuid.UUID
    picked_team: str
    is_superdog: bool = False


class PickUpdate(BaseModel):
    picked_team: str
    is_superdog: bool = False


class PickRead(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    game_id: uuid.UUID
    group_id: uuid.UUID
    picked_team: str
    is_superdog: bool
    result: str
    is_forfeit: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class PickHistoryEntry(BaseModel):
    """One graded pick in a member's history, with enough game/week context
    (denormalized from Pick + Game + Week) to render a full row and let the
    client compute a running win/loss tally without further lookups."""
    pick_id: uuid.UUID
    game_id: uuid.UUID
    week_number: int
    week_label: str
    home_team: str
    away_team: str
    picked_team: str
    favorite_team: str
    spread: float
    kickoff_at: datetime
    is_superdog: bool
    is_forfeit: bool
    result: str
    home_score: Optional[int]
    away_score: Optional[int]
