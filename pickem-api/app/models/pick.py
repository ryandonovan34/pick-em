import uuid
from datetime import datetime, timezone

from sqlmodel import Field, SQLModel, UniqueConstraint


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Pick(SQLModel, table=True):
    """
    One user's pick for one game in one group. The composite unique constraint
    (user_id, game_id, group_id) ensures a user can only have one pick per game
    per group — use PUT /picks/{id} to change it before kickoff.
    """

    __tablename__ = "picks"
    __table_args__ = (
        UniqueConstraint("user_id", "game_id", "group_id", name="uq_pick_per_game"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(foreign_key="users.id")
    game_id: uuid.UUID = Field(foreign_key="games.id")
    group_id: uuid.UUID = Field(foreign_key="groups.id")
    picked_team: str = Field(max_length=100)
    # True only when the user has declared this as a superdog (underdog to win outright).
    is_superdog: bool = Field(default=False)
    # 'pending' until the game result is posted; then 'win', 'loss', or 'superdog_win'.
    result: str = Field(default="pending", max_length=20)
    created_at: datetime = Field(default_factory=_utc_now)
    updated_at: datetime = Field(default_factory=_utc_now)
