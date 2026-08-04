"""
Odds API integration and spread rounding.

In Phase 2 (APP_ENV=development) the Odds API is never called — all game data
comes from the /dev/mock-games endpoint. This module handles Phase 3+.
"""

import logging
from datetime import datetime

import httpx
from sqlmodel import Session, select

from app.config import settings
from app.database import engine
from app.models import Game
from app.utils import utc_now

logger = logging.getLogger(__name__)

# The Odds API splits NFL into separate endpoints per phase of the season —
# 'americanfootball_nfl' only has odds/scores once the regular season starts;
# preseason games live under their own key. The app's internal/group-facing
# sport key stays unified as 'americanfootball_nfl' (a group's sport filter,
# Group.include_preseason/include_playoffs, etc. all assume ONE NFL group
# spans the whole season) — this maps that internal key to every real Odds
# API key that should be queried on its behalf.
_ODDS_API_SPORT_KEYS: dict[str, list[str]] = {
    "americanfootball_nfl": ["americanfootball_nfl", "americanfootball_nfl_preseason"],
}


def odds_api_sport_keys(sport: str) -> list[str]:
    """Every real Odds API sport key that should be queried for the given
    internal/group-facing sport. Falls back to [sport] unchanged for any
    sport without a specific mapping."""
    return _ODDS_API_SPORT_KEYS.get(sport, [sport])


def round_spread(raw_spread: float) -> float:
    """
    Round a spread value away from zero to the nearest 0.5, guaranteeing
    no push is possible.

    The Odds API sometimes returns whole-number spreads (e.g. -3.0).
    We always push these 0.5 further from zero before storing:
        -3.0  →  -3.5
        -7.0  →  -7.5
         3.0  →   3.5
        -3.5  →  -3.5  (already a half-point spread, unchanged)

    This function is the ONLY place where spread rounding happens.
    The raw value is discarded immediately after this call.
    """
    fractional = abs(raw_spread) % 1
    if abs(fractional - 0.5) < 1e-9:
        # Already ends in .5 — no adjustment needed.
        return raw_spread
    # Move 0.5 further from zero.
    return raw_spread - 0.5 if raw_spread < 0 else raw_spread + 0.5


async def fetch_odds(sport: str) -> list[dict]:
    """
    Fetch current spread odds from The Odds API.
    Returns a list of raw game dicts from the API response.
    Only called in Phase 3+ (APP_ENV=production or explicit trigger).
    """
    url = f"{settings.ODDS_API_BASE_URL}/v4/sports/{sport}/odds"
    params = {
        "apiKey": settings.ODDS_API_KEY,
        "markets": "spreads",
        "oddsFormat": "american",
        "dateFormat": "iso",
    }
    async with httpx.AsyncClient() as client:
        response = await client.get(url, params=params, timeout=30.0)
        response.raise_for_status()
    return response.json()


def ingest_odds(sport: str) -> int:
    """
    Fetch odds from The Odds API for every real API key mapped to `sport`
    (see odds_api_sport_keys — e.g. 'americanfootball_nfl' expands to both
    the regular-season+playoffs endpoint and the separate preseason one) and
    upsert into the games table. New games are added to the pool; existing
    games have their spread + kickoff updated in place. Every resulting Game
    row is stored with Game.sport = `sport` (the internal/group-facing key),
    regardless of which real API key it came from, so a group filtering on
    sport='americanfootball_nfl' sees preseason, regular-season, and playoff
    games all in the same pool — whether they're auto-populated is governed
    separately by Group.include_preseason/include_playoffs.

    Slate membership is tracked separately via the slate_games junction table.
    Returns the total count of games processed across all mapped API keys.
    """
    if not settings.ODDS_API_KEY:
        logger.warning("ODDS_API_KEY not configured — skipping odds ingest for %s", sport)
        return 0

    total = 0
    for api_sport_key in odds_api_sport_keys(sport):
        total += _ingest_one(api_sport_key, stored_sport=sport)
    return total


def _ingest_one(api_sport_key: str, stored_sport: str) -> int:
    """Ingest from a single real Odds API sport key. Failures here (e.g. a
    404 for a key with no current listings, like preseason out of season)
    are logged and swallowed so they don't block ingest for other keys
    mapped to the same internal sport."""
    url = f"{settings.ODDS_API_BASE_URL}/v4/sports/{api_sport_key}/odds"
    params = {
        "apiKey": settings.ODDS_API_KEY,
        "regions": "us",
        "markets": "spreads",
        "oddsFormat": "american",
        "dateFormat": "iso",
    }
    with httpx.Client() as client:
        response = client.get(url, params=params, timeout=30.0)
        try:
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            logger.warning(
                "Odds API returned %s for sport '%s' — skipping ingest. Body: %s",
                exc.response.status_code, api_sport_key, exc.response.text[:200],
            )
            return 0
    raw_games: list[dict] = response.json()

    now = utc_now()
    count = 0
    with Session(engine) as session:
        for g in raw_games:
            spread_val, favorite_team = _parse_spread(g)
            if spread_val is None:
                continue
            spread = round_spread(spread_val)
            kickoff_at = datetime.fromisoformat(g["commence_time"].replace("Z", "+00:00"))

            existing = session.exec(
                select(Game).where(Game.odds_api_id == g["id"])
            ).first()
            if existing:
                existing.spread = spread
                existing.favorite_team = favorite_team
                existing.kickoff_at = kickoff_at
                existing.odds_fetched_at = now
                session.add(existing)
            else:
                session.add(Game(
                    odds_api_id=g["id"],
                    sport=stored_sport,
                    home_team=g["home_team"],
                    away_team=g["away_team"],
                    spread=spread,
                    favorite_team=favorite_team,
                    kickoff_at=kickoff_at,
                    odds_fetched_at=now,
                ))
            count += 1
        session.commit()

    logger.info("Odds ingest: %d games upserted for api_sport=%s (stored as %s)", count, api_sport_key, stored_sport)
    return count


def fetch_scores(sport: str) -> list[dict]:
    """
    Fetch recent completed game scores from The Odds API.
    Returns raw game dicts including 'completed' flag and 'scores' list.
    Returns an empty list if ODDS_API_KEY is not configured.
    """
    if not settings.ODDS_API_KEY:
        return []
    url = f"{settings.ODDS_API_BASE_URL}/v4/sports/{sport}/scores"
    params = {"apiKey": settings.ODDS_API_KEY, "daysFrom": "3"}
    with httpx.Client() as client:
        response = client.get(url, params=params, timeout=30.0)
        response.raise_for_status()
    return response.json()


def _parse_spread(game_dict: dict) -> tuple[float | None, str | None]:
    """Extract (spread_point, favorite_team) from an Odds API game dict."""
    for bookmaker in game_dict.get("bookmakers", []):
        for market in bookmaker.get("markets", []):
            if market.get("key") != "spreads":
                continue
            outcomes = market.get("outcomes", [])
            # The favorite has the negative point value.
            favorite = next((o for o in outcomes if o.get("point", 0) < 0), None)
            if favorite:
                return favorite["point"], favorite["name"]
    return None, None
