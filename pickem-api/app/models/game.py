import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Game(SQLModel, table=True):
    """
    A single matchup. Games live permanently in the pool; membership in a group's
    week is tracked via the slate_games junction table so the same game can appear
    in multiple groups' slates simultaneously.

    The spread is ALWAYS stored rounded to the nearest 0.5 (see services/odds.py).
    The raw value from the Odds API is discarded immediately on ingest.
    """

    __tablename__ = "games"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    # The Odds API's own ID for this game — used to de-duplicate on re-fetch
    # and to look up a game when the admin picks it from the available list.
    odds_api_id: Optional[str] = Field(default=None, unique=True, max_length=100)
    # Odds API sport key, e.g. 'americanfootball_nfl'
    sport: str = Field(max_length=50)
    home_team: str = Field(max_length=100)
    away_team: str = Field(max_length=100)
    # Stored rounded to .5 — negative means home team is favored.
    spread: float
    # The team that the spread favors (always the one with the negative spread).
    favorite_team: str = Field(max_length=100)
    # Once True, odds ingest stops overwriting spread/favorite_team — set 30
    # minutes before kickoff (see services/scheduler.py) so the number
    # everyone picked against and the number it's graded on are the same one.
    spread_locked: bool = Field(default=False)
    kickoff_at: datetime
    # Null until results are posted.
    home_score: Optional[int] = None
    away_score: Optional[int] = None
    result_posted: bool = Field(default=False)
    # Tracks how fresh the odds data is.
    odds_fetched_at: datetime = Field(default_factory=_utc_now)
