import uuid
from datetime import datetime

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
