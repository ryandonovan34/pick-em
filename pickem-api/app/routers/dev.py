"""
Development-only endpoints. These are completely unavailable in production (return 404).

POST /dev/mock-games    — seed the odds pool with realistic fake games
POST /dev/mock-results  — trigger the result processing pipeline for a game
POST /dev/seed-week     — create/reuse a week for a group and populate it with mock games
GET  /dev/mock-templates — list available team matchups for each sport

These routes let you drive the entire app without ever calling the real Odds API,
which is the Phase 2 development workflow.
"""

import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlmodel import Session, select

from app.config import settings
from app.database import get_session
from app.models import Game, Group, GroupMember, SlateGame, User, Week
from app.schemas.game import GameRead, WeekRead
from app.services import notifications
from app.services.auto_slate import get_or_create_week
from app.services.nfl_calendar import label_for_week_number, nfl_week_number_and_label, thursday_of, weekly_slot_kickoff
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
    {"home": "New England Patriots",  "away": "New York Jets",           "spread": -2.5},
    {"home": "Denver Broncos",        "away": "Jacksonville Jaguars",    "spread": -3.5},
    {"home": "Tennessee Titans",      "away": "Washington Commanders",   "spread": -6.5},
    {"home": "Carolina Panthers",     "away": "Atlanta Falcons",         "spread": -1.5},
    {"home": "Dallas Cowboys",        "away": "Philadelphia Eagles",     "spread": -2.5},
    {"home": "Kansas City Chiefs",    "away": "Buffalo Bills",           "spread": -1.5},
    {"home": "Baltimore Ravens",      "away": "Pittsburgh Steelers",     "spread": -3.5},
    {"home": "San Francisco 49ers",   "away": "Seattle Seahawks",        "spread": -5.5},
]

_TEMPLATES: dict[str, list[dict]] = {
    "americanfootball_nfl": _NFL_TEMPLATES,
}


def _odds_api_id(sport: str, home: str, away: str, week_number: Optional[int]) -> str:
    """
    Deterministic id for a mock game, used to dedup/reuse on repeat seeding.

    week_number disambiguates the same team pairing recurring across
    different simulated weeks (e.g. a 9-week mock season cycling through a
    limited template pool) — without it, two different weeks reusing the
    same matchup would silently collide onto the same Game row and share a
    single result.
    """
    slug = f"{home.replace(' ', '_')}_{away.replace(' ', '_')}"
    if week_number is not None:
        return f"mock_{sport}_w{week_number}_{slug}"
    return f"mock_{sport}_{slug}"


# ── Request / response bodies ─────────────────────────────────────────────────

class MockGamesRequest(BaseModel):
    sport: str
    week_label: str
    game_count: int = 4
    # Disambiguates odds_api_id when the same matchup recurs across weeks.
    week_number: Optional[int] = None
    # Anchor for kickoff staggering. Defaults to now+48h when omitted.
    base_kickoff_at: Optional[datetime] = None
    # Which slice of the template list to use (wraps via modulo), so callers
    # seeding many weeks in a row can rotate through matchups instead of
    # always getting templates[0:game_count].
    template_offset: int = 0


class MockResultRequest(BaseModel):
    game_id: uuid.UUID
    home_score: int
    away_score: int


class SeedWeekRequest(BaseModel):
    group_id: uuid.UUID
    sport: str
    game_count: int = 4
    # Explicit NFL week number (0=preseason, 1-18 regular, 19-22 playoffs).
    # If omitted, derived from the games' kickoff dates via the group's
    # season_year — the same canonical mapping auto-populate and manual
    # create-week use, so all three week-creation paths agree.
    week_number: Optional[int] = None
    # If omitted, auto-derived from week_number (e.g. "Week 9", "Preseason").
    week_label: Optional[str] = None
    base_kickoff_at: Optional[datetime] = None
    template_offset: int = 0


class SeedWeekResponse(BaseModel):
    week: WeekRead
    games: list[GameRead]


# ── Shared helpers ────────────────────────────────────────────────────────────

def _select_templates(templates: list[dict], game_count: int, template_offset: int) -> list[dict]:
    count = min(game_count, len(templates))
    return [templates[(template_offset + i) % len(templates)] for i in range(count)]


def _build_mock_games(
    sport: str,
    game_count: int,
    week_number: Optional[int],
    base_kickoff_at: Optional[datetime],
    session: Session,
    template_offset: int = 0,
) -> list[Game]:
    """
    Return `game_count` mock games for `sport`, reusing existing rows by
    odds_api_id where already present and creating the rest. `template_offset`
    selects which slice of the template list to draw from (wrapping via
    modulo). Caller is responsible for session.commit().

    Kickoff times follow real NFL weekly scheduling (Thursday Night
    Football, Sunday's early/late windows, and an alternating Sunday/Monday
    Night slot) anchored to the Thursday of the NFL week containing
    base_kickoff_at (default now+48h) — see nfl_calendar.weekly_slot_kickoff.
    """
    templates = _TEMPLATES.get(sport)
    if templates is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unknown sport '{sport}'. Available: {list(_TEMPLATES)}",
        )

    selected = _select_templates(templates, game_count, template_offset)
    anchor = base_kickoff_at or (datetime.now(timezone.utc) + timedelta(hours=48))
    thursday = thursday_of(anchor.date())

    games: list[Game] = []
    for i, template in enumerate(selected):
        rounded_spread = round_spread(template["spread"])
        # Negative spread → home team is favored.
        favorite = template["home"] if rounded_spread < 0 else template["away"]
        odds_api_id = _odds_api_id(sport, template["home"], template["away"], week_number)

        existing = session.exec(select(Game).where(Game.odds_api_id == odds_api_id)).first()
        if existing:
            games.append(existing)
            continue

        game = Game(
            odds_api_id=odds_api_id,
            sport=sport,
            home_team=template["home"],
            away_team=template["away"],
            spread=rounded_spread,
            favorite_team=favorite,
            kickoff_at=weekly_slot_kickoff(thursday, i, len(selected), week_number),
        )
        session.add(game)
        games.append(game)

    session.flush()
    return games


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

    Kickoff times are staggered starting 48 hours from now (or from
    base_kickoff_at, if given) so you have time to submit picks before they lock.

    The spread is run through the same rounding function used in production
    so mock data tests the full pipeline. Idempotent: games already in the
    pool (by odds_api_id) are skipped, not duplicated, and not re-returned.
    """
    templates = _TEMPLATES.get(body.sport)
    if templates is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unknown sport '{body.sport}'. Available: {list(_TEMPLATES)}",
        )
    candidate_ids = {
        _odds_api_id(body.sport, t["home"], t["away"], body.week_number)
        for t in _select_templates(templates, body.game_count, body.template_offset)
    }
    pre_existing_ids = set(
        session.exec(select(Game.odds_api_id).where(Game.odds_api_id.in_(candidate_ids))).all()  # type: ignore[attr-defined]
    )

    games = _build_mock_games(
        body.sport, body.game_count, body.week_number, body.base_kickoff_at, session, body.template_offset
    )
    session.commit()

    created = [g for g in games if g.odds_api_id not in pre_existing_ids]
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
    One-shot dev helper: create or reuse a week for a group and populate it
    with mock games.

    Reuses the same game templates as POST /dev/mock-games; games that already
    exist in the pool are reused rather than duplicated. Uses the same
    get_or_create_week() primitive as auto-population and manual week
    creation, so repeated calls for the same week_number safely merge into
    one Week row instead of creating duplicates.
    """
    group = session.get(Group, body.group_id)
    if group is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found.")

    games = _build_mock_games(
        body.sport, body.game_count, body.week_number, body.base_kickoff_at, session, body.template_offset
    )

    week_number = body.week_number
    if week_number is None:
        week_number, _label = nfl_week_number_and_label(
            min(g.kickoff_at for g in games).date(), group.season_year
        )
    label = body.week_label or label_for_week_number(week_number)

    week = get_or_create_week(group, week_number, label, games, session)

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
        game = process_game_result(body.game_id, body.home_score, body.away_score, session)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))

    # Send notifications to every group that has this game in a slate.
    try:
        for sg in session.exec(select(SlateGame).where(SlateGame.game_id == game.id)).all():
            week = session.get(Week, sg.week_id)
            if not week:
                continue
            group = session.get(Group, week.group_id)
            if not group:
                continue
            members = session.exec(
                select(User)
                .join(GroupMember, GroupMember.user_id == User.id)  # type: ignore[arg-type]
                .where(GroupMember.group_id == group.id, User.fcm_token.isnot(None))  # type: ignore[union-attr]
            ).all()
            tokens = [m.fcm_token for m in members if m.fcm_token]
            if tokens:
                notifications.send_silent_cache_invalidation(
                    tokens, "results_posted", group_id=group.id, week_id=sg.week_id
                )
                slate_game_ids = [r.game_id for r in session.exec(
                    select(SlateGame).where(SlateGame.week_id == sg.week_id)
                ).all()]
                slate_games = session.exec(select(Game).where(Game.id.in_(slate_game_ids))).all()  # type: ignore[attr-defined]
                if all(g.result_posted for g in slate_games):
                    notifications.send_results_notification(tokens, group.name)
    except Exception:
        pass  # Never let notification failure break the mock-results response

    return game
