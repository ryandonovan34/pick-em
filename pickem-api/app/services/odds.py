"""
Odds API integration and spread rounding.

In Phase 2 (APP_ENV=development) the Odds API is never called — all game data
comes from the /dev/mock-games endpoint. This module handles Phase 3+.
"""

import httpx

from app.config import settings


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
