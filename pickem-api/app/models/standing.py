import uuid
from datetime import datetime, timezone

from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Standing(SQLModel, table=True):
    """
    Pre-computed leaderboard record for one user in one group.

    This is a materialized/write-through cache: we update it transactionally
    every time results are processed, so the leaderboard endpoint is a simple
    single-table read with no aggregation at query time.

    wins + (superdog_wins * 3) gives the effective win count for tie-breaking,
    but win_percentage is computed from wins / (wins + losses) — superdog_wins
    count as 3 wins each, so wins already includes that multiplier.

    Wait — actually: wins = regular wins only. superdog_wins = count of superdog
    wins. Each superdog win counts as 3 in standings but is tracked separately
    so we can display "X superdog wins" in the leaderboard. The effective total
    is (wins + superdog_wins * 3) and should be compared against losses.
    """

    __tablename__ = "standings"

    # Composite primary key — one row per (user, group) pair.
    user_id: uuid.UUID = Field(foreign_key="users.id", primary_key=True, ondelete="CASCADE")
    group_id: uuid.UUID = Field(foreign_key="groups.id", primary_key=True, ondelete="CASCADE")
    wins: int = Field(default=0)
    losses: int = Field(default=0)
    # How many times this user scored a superdog win (3 pts each).
    superdog_wins: int = Field(default=0)
    # How many superdogs this user has declared (to enforce the per-user limit).
    superdogs_used: int = Field(default=0)
    updated_at: datetime = Field(default_factory=_utc_now)
    # Denormalised for leaderboard display — kept in sync by results service.
    display_name: str = Field(default="", max_length=100)
