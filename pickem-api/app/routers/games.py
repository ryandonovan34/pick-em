"""
Week and game slate management.

Weeks are the time-boxed containers for a pick slate. The admin creates weeks,
curates the game list from the available odds pool, and the members pick from it.

For World Cup groups, games are auto-populated once odds become available
(Phase 3+). For now in Phase 2 the admin uses /dev/mock-games to seed the pool.
"""

import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from app.utils import ensure_utc, utc_now
from sqlmodel import Session, select

from app.auth.dependencies import get_current_user
from app.database import get_session
from app.models import Game, Group, GroupMember, User, Week
from app.routers.groups import _require_admin, _require_member
from app.schemas.game import AddGameToSlate, GameRead, WeekCreate, WeekRead

router = APIRouter()


# ── Weeks ────────────────────────────────────────────────────────────────────

@router.get("/groups/{group_id}/weeks", response_model=list[WeekRead])
def list_weeks(
    group_id: uuid.UUID,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> list[Week]:
    """Return all weeks/slates for a group, ordered by week_number."""
    _require_member(group_id, current_user, session)
    return list(
        session.exec(
            select(Week)
            .where(Week.group_id == group_id)
            .order_by(Week.week_number)  # type: ignore[arg-type]
        ).all()
    )


@router.post("/groups/{group_id}/weeks", response_model=WeekRead, status_code=status.HTTP_201_CREATED)
def create_week(
    group_id: uuid.UUID,
    body: WeekCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Week:
    """Create a new week/slate. Admin only."""
    group = _require_member(group_id, current_user, session)
    _require_admin(group, current_user)

    existing_weeks = session.exec(
        select(Week).where(Week.group_id == group_id)
    ).all()
    next_number = (max((w.week_number for w in existing_weeks), default=0)) + 1

    week = Week(group_id=group_id, week_number=next_number, label=body.label)
    session.add(week)
    session.commit()
    session.refresh(week)
    return week


# ── Games (slate management) ─────────────────────────────────────────────────

@router.get("/groups/{group_id}/weeks/{week_id}/games", response_model=list[GameRead])
def list_games(
    group_id: uuid.UUID,
    week_id: uuid.UUID,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> list[Game]:
    """Return all games in a week's slate, ordered by kickoff time."""
    _require_member(group_id, current_user, session)

    week = session.get(Week, week_id)
    if week is None or week.group_id != group_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Week not found.")

    return list(
        session.exec(
            select(Game)
            .where(Game.week_id == week_id)
            .order_by(Game.kickoff_at)  # type: ignore[arg-type]
        ).all()
    )


@router.post(
    "/groups/{group_id}/weeks/{week_id}/games",
    response_model=GameRead,
    status_code=status.HTTP_201_CREATED,
)
def add_game_to_slate(
    group_id: uuid.UUID,
    week_id: uuid.UUID,
    body: AddGameToSlate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Game:
    """
    Add a game from the odds pool to a slate.
    The game must exist in the pool (week_id=None) and not already be in another slate.
    Admin only; locked once the first game of the slate has kicked off.
    """
    group = _require_member(group_id, current_user, session)
    _require_admin(group, current_user)

    week = session.get(Week, week_id)
    if week is None or week.group_id != group_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Week not found.")

    # Find the game in the odds pool by its Odds API ID.
    game = session.exec(
        select(Game).where(Game.odds_api_id == body.odds_api_id, Game.week_id.is_(None))  # type: ignore[attr-defined]
    ).first()
    if game is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No available game with odds_api_id '{body.odds_api_id}'. "
                   "Check /odds/available for the current pool.",
        )

    # Can't add games after the first kickoff of this slate.
    existing_games = session.exec(select(Game).where(Game.week_id == week_id)).all()
    now = utc_now()
    if existing_games and min(ensure_utc(g.kickoff_at) for g in existing_games) <= now:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot modify a slate after the first game has kicked off.",
        )

    game.week_id = week_id
    session.add(game)
    session.commit()
    session.refresh(game)
    return game


@router.delete(
    "/groups/{group_id}/weeks/{week_id}/games/{game_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def remove_game_from_slate(
    group_id: uuid.UUID,
    week_id: uuid.UUID,
    game_id: uuid.UUID,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> None:
    """
    Remove a game from a slate (returns it to the odds pool).
    Admin only; locked once the first game of the slate has kicked off.
    """
    group = _require_member(group_id, current_user, session)
    _require_admin(group, current_user)

    game = session.get(Game, game_id)
    if game is None or game.week_id != week_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Game not found in this slate.")

    # Lock check.
    existing_games = session.exec(select(Game).where(Game.week_id == week_id)).all()
    now = utc_now()
    if min((ensure_utc(g.kickoff_at) for g in existing_games), default=now + __import__("datetime").timedelta(hours=1)) <= now:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot modify a slate after the first game has kicked off.",
        )

    # Return to pool rather than deleting — the game data is still valid.
    game.week_id = None
    session.add(game)
    session.commit()


# ── Available odds ────────────────────────────────────────────────────────────

@router.get("/odds/available", response_model=list[GameRead])
def get_available_odds(
    sport: str = Query(..., description="Odds API sport key, e.g. 'americanfootball_nfl'"),
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> list[Game]:
    """
    Return games in the odds pool (week_id=None) for a given sport.
    Admins use this to build a slate.

    In Phase 2 (development), the pool is seeded via POST /dev/mock-games.
    In Phase 3+, the pool is populated by the Odds API scheduler.
    """
    return list(
        session.exec(
            select(Game).where(
                Game.sport == sport,
                Game.week_id.is_(None),  # type: ignore[attr-defined]
            ).order_by(Game.kickoff_at)  # type: ignore[arg-type]
        ).all()
    )
