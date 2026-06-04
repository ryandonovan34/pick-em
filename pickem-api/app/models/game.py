import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Game(SQLModel, table=True):
    """
    A single matchup. Games with week_id=None are in the "odds pool" — available
    for admins to add to a slate but not yet part of any group's week.
    Once an admin adds a game to a slate, week_id is set.

    The spread is ALWAYS stored rounded to the nearest 0.5 (see services/odds.py).
    The raw value from the Odds API is discarded immediately on ingest.
    """

    __tablename__ = "games"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    # None = sitting in the odds pool; set when added to a group's slate.
    week_id: Optional[uuid.UUID] = Field(default=None, foreign_key="weeks.id")
    # The Odds API's own ID for this game — used to de-duplicate on re-fetch
    # and to look up a game when the admin picks it from the available list.
    odds_api_id: Optional[str] = Field(default=None, unique=True, max_length=100)
    # Odds API sport key: 'americanfootball_nfl' | 'soccer_fifa_world_cup'
    sport: str = Field(max_length=50)
    home_team: str = Field(max_length=100)
    away_team: str = Field(max_length=100)
    # Stored rounded to .5 — negative means home team is favored.
    spread: float
    # The team that the spread favors (always the one with the negative spread).
    favorite_team: str = Field(max_length=100)
    kickoff_at: datetime
    # Null until results are posted.
    home_score: Optional[int] = None
    away_score: Optional[int] = None
    result_posted: bool = Field(default=False)
    # Tracks how fresh the odds data is.
    odds_fetched_at: datetime = Field(default_factory=_utc_now)
