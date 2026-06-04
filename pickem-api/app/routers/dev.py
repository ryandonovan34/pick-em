"""
Development-only endpoints. These are completely unavailable in production (return 404).

POST /dev/mock-games    — seed the odds pool with realistic fake games
POST /dev/mock-results  — trigger the result processing pipeline for a game
POST /dev/seed-week     — create a week for a group and populate it with mock games in one shot
GET  /dev/mock-templates — list available team matchups for each sport

These routes let you drive the entire app without ever calling the real Odds API,
which is the Phase 2 development workflow.
"""

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlmodel import Session, select

from app.config import settings
from app.database import get_session
from app.models import Game, Week
from app.schemas.game import GameRead, WeekRead
from app.services.odds import round_spread
from app.services.results import process_game_result

router = APIRouter()


def _dev_only() -> None:
    """Dependency that raises 404 in production, keeping dev routes invisible."""
    if not settings.is_development:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found.")


# ── Mock game templates ───────────────────────────────────────────────────────

_NFL_TEMPLATES: list[dict] = [
    {"home": "Kansas City Chiefs",    "away": "Las Vegas Raiders",      "spread": -7.5},
    {"home": "Buffalo Bills",         "away": "Miami Dolphins",          "spread": -6.5},
    {"home": "San Francisco 49ers",   "away": "Dallas Cowboys",          "spread": -4.5},
    {"home": "Philadelphia Eagles",   "away": "New York Giants",         "spread": -10.5},
    {"home": "Baltimore Ravens",      "away": "Cleveland Browns",        "spread": -9.5},
    {"home": "Cincinnati Bengals",    "away": "Pittsburgh Steelers",     "spread": -3.5},
    {"home": "Detroit Lions",         "away": "Chicago Bears",           "spread": -7.5},
    {"home": "Green Bay Packers",     "away": "Minnesota Vikings",       "spread": -2.5},
    {"home": "Los Angeles Rams",      "away": "Arizona Cardinals",       "spread": -5.5},
    {"home": "Seattle Seahawks",      "away": "Los Angeles Chargers",    "spread": -1.5},
    {"home": "Tampa Bay Buccaneers",  "away": "New Orleans Saints",      "spread": -3.5},
    {"home": "Houston Texans",        "away": "Indianapolis Colts",      "spread": -4.5},
]

_WORLD_CUP_TEMPLATES: list[dict] = [
    {"home": "France",         "away": "Morocco",       "spread": -1.5},
    {"home": "Brazil",         "away": "Croatia",       "spread": -1.5},
    {"home": "United States",  "away": "Mexico",        "spread": -0.5},
    {"home": "Argentina",      "away": "Saudi Arabia",  "spread": -2.5},
    {"home": "Germany",        "away": "Japan",         "spread": -0.5},
    {"home": "Spain",          "away": "Costa Rica",    "spread": -1.5},
    {"home": "Portugal",       "away": "Ghana",         "spread": -1.5},
    {"home": "England",        "away": "Iran",          "spread": -1.5},
    {"home": "Netherlands",    "away": "Senegal",       "spread": -0.5},
    {"home": "Belgium",        "away": "Canada",        "spread": -1.5},
    {"home": "Uruguay",        "away": "South Korea",   "spread": -0.5},
    {"home": "Switzerland",    "away": "Serbia",        "spread": -0.5},
]

_TEMPLATES: dict[str, list[dict]] = {
    "americanfootball_nfl": _NFL_TEMPLATES,
    "soccer_fifa_world_cup": _WORLD_CUP_TEMPLATES,
}

# World Cup kickoffs start further apart (one per day-ish for group stage).
_KICKOFF_GAP: dict[str, timedelta] = {
    "americanfootball_nfl": timedelta(hours=3),
    "soccer_fifa_world_cup": timedelta(hours=24),
}


# ── Request / response bodies ─────────────────────────────────────────────────

class MockGamesRequest(BaseModel):
    sport: str
    week_label: str
    game_count: int = 4


class MockResultRequest(BaseModel):
    game_id: uuid.UUID
    home_score: int
    away_score: int


class SeedWeekRequest(BaseModel):
    group_id: uuid.UUID
    sport: str
    week_label: str
    game_count: int = 4


class SeedWeekResponse(BaseModel):
    week: WeekRead
    games: list[GameRead]


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/mock-templates", dependencies=[Depends(_dev_only)])
def get_mock_templates() -> dict[str, list[dict]]:
    """
    Return the available team matchup templates for each sport.
    Use these as a reference when seeding games via POST /dev/mock-games.
    """
    return _TEMPLATES


@router.post("/mock-games", response_model=list[GameRead], status_code=status.HTTP_201_CREATED)
def seed_mock_games(
    body: MockGamesRequest,
    session: Session = Depends(get_session),
    _: None = Depends(_dev_only),
) -> list[Game]:
    """
    Seed the odds pool with realistic mock games.

    Creates up to `game_count` games with week_id=None (i.e. in the pool, not yet
    in any group's slate). Admins can then add them to slates via the normal
    POST /groups/{id}/weeks/{week_id}/games endpoint.

    Kickoff times are staggered starting 48 hours from now so you have time to
    submit picks before they lock.

    The spread is run through the same rounding function used in production
    so mock data tests the full pipeline.
    """
    templates = _TEMPLATES.get(body.sport)
    if templates is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unknown sport '{body.sport}'. Available: {list(_TEMPLATES)}",
        )

    count = min(body.game_count, len(templates))
    gap = _KICKOFF_GAP.get(body.sport, timedelta(hours=3))
    base_kickoff = datetime.now(timezone.utc) + timedelta(hours=48)

    created: list[Game] = []
    for i, template in enumerate(templates[:count]):
        rounded_spread = round_spread(template["spread"])
        # Negative spread → home team is favored.
        favorite = template["home"] if rounded_spread < 0 else template["away"]

        odds_api_id = f"mock_{body.sport}_{template['home'].replace(' ', '_')}_{template['away'].replace(' ', '_')}"

        # Skip if already in pool to make this endpoint idempotent.
        existing = session.exec(select(Game).where(Game.odds_api_id == odds_api_id)).first()
        if existing:
            continue

        game = Game(
            odds_api_id=odds_api_id,
            sport=body.sport,
            home_team=template["home"],
            away_team=template["away"],
            spread=rounded_spread,
            favorite_team=favorite,
            kickoff_at=base_kickoff + gap * i,
        )
        session.add(game)
        created.append(game)

    session.commit()
    for game in created:
        session.refresh(game)

    return created


@router.post("/seed-week", response_model=SeedWeekResponse, status_code=status.HTTP_201_CREATED)
def seed_week(
    body: SeedWeekRequest,
    session: Session = Depends(get_session),
    _: None = Depends(_dev_only),
) -> SeedWeekResponse:
    """
    One-shot dev helper: create a week for a group and populate it with mock games.

    Reuses the same game templates as POST /dev/mock-games. Games that already
    exist in the pool are reused rather than duplicated. The week_number is
    auto-incremented based on existing weeks for that group.
    """
    templates = _TEMPLATES.get(body.sport)
    if templates is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unknown sport '{body.sport}'. Available: {list(_TEMPLATES)}",
        )

    count = min(body.game_count, len(templates))
    gap = _KICKOFF_GAP.get(body.sport, timedelta(hours=3))
    base_kickoff = datetime.now(timezone.utc) + timedelta(hours=48)

    # Create or reuse games in the odds pool.
    games: list[Game] = []
    for i, template in enumerate(templates[:count]):
        rounded_spread = round_spread(template["spread"])
        favorite = template["home"] if rounded_spread < 0 else template["away"]
        odds_api_id = f"mock_{body.sport}_{template['home'].replace(' ', '_')}_{template['away'].replace(' ', '_')}"

        existing = session.exec(select(Game).where(Game.odds_api_id == odds_api_id)).first()
        if existing and existing.week_id is None:
            games.append(existing)
        elif existing is None:
            game = Game(
                odds_api_id=odds_api_id,
                sport=body.sport,
                home_team=template["home"],
                away_team=template["away"],
                spread=rounded_spread,
                favorite_team=favorite,
                kickoff_at=base_kickoff + gap * i,
            )
            session.add(game)
            games.append(game)
        # If existing.week_id is already set, skip it (already on another slate).

    session.flush()

    # Auto-number the new week.
    existing_weeks = session.exec(select(Week).where(Week.group_id == body.group_id)).all()
    next_number = (max((w.week_number for w in existing_weeks), default=0)) + 1

    week = Week(group_id=body.group_id, week_number=next_number, label=body.week_label)
    session.add(week)
    session.flush()

    for game in games:
        game.week_id = week.id
        session.add(game)

    session.commit()
    session.refresh(week)
    for game in games:
        session.refresh(game)

    return SeedWeekResponse(
        week=WeekRead.model_validate(week),
        games=[GameRead.model_validate(g) for g in games],
    )


@router.post("/mock-results", response_model=GameRead)
def post_mock_result(
    body: MockResultRequest,
    session: Session = Depends(get_session),
    _: None = Depends(_dev_only),
) -> Game:
    """
    Simulate posting a result for a game.

    This triggers the exact same result processing pipeline as production:
    picks are scored, standings are updated, and the game is marked result_posted=True.

    You can find game IDs from the response to POST /dev/mock-games or
    GET /groups/{id}/weeks/{week_id}/games.
    """
    try:
        return process_game_result(body.game_id, body.home_score, body.away_score, session)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))
