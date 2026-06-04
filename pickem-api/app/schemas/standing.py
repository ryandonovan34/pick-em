import uuid
from datetime import datetime

from pydantic import BaseModel, computed_field


class StandingRead(BaseModel):
    user_id: uuid.UUID
    group_id: uuid.UUID
    display_name: str
    wins: int
    losses: int
    superdog_wins: int
    superdogs_used: int
    updated_at: datetime

    model_config = {"from_attributes": True}

    @computed_field  # type: ignore[prop-decorator]
    @property
    def win_percentage(self) -> float:
        # Each superdog win counts as 3 regular wins in the record.
        effective_wins = self.wins + self.superdog_wins * 3
        total = effective_wins + self.losses
        return effective_wins / total if total > 0 else 0.0

    @computed_field  # type: ignore[prop-decorator]
    @property
    def record(self) -> str:
        effective_wins = self.wins + self.superdog_wins * 3
        return f"{effective_wins}-{self.losses}"
