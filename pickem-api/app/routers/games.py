"""
Week and game slate management.

Weeks are the time-boxed containers for a pick slate. When a group is created
the auto-slate service populates weeks automatically from the odds pool.
Admins can still manually add or remove games from a slate.

The slate_games junction table lets the same game appear in multiple groups'
slates simultaneously, so odds updates and result posting flow through once.
"""

import uuid
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status
from app.utils import ensure_utc, utc_now
from sqlmodel import Session, select

from app.auth.dependencies import get_current_user
from app.config import settings
from app.database import get_session
from app.models import Game, Group, GroupMember, SlateGame, User, Week
from app.routers.groups import _require_admin, _require_member
from app.schemas.game import AddGameToSlate, GameRead, WeekCreate, WeekRead
from app.services.odds import ingest_odds
from app.services.scheduler import (
    cancel_odds_refresh_for_slate,
    cancel_pick_reminders,
    cancel_slate_admin_reminder,
    schedule_odds_refresh_for_slate,
    schedule_pick_reminders,
    schedule_slate_admin_reminder,
)

router = APIRouter()


def _slate_games(week_id: uuid.UUID, session: Session) -> list[Game]:
    """Return all games in a week's slate ordered by kickoff time."""
    return list(
        session.exec(
            select(Game)
            .join(SlateGame, SlateGame.game_id == Game.id)  # type: ignore[arg-type]
            .where(SlateGame.week_id == week_id)
            .order_by(Game.kickoff_at)  # type: ignore[arg-type]
        ).all()
    )


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

    existing_weeks = session.exec(select(Week).where(Week.group_id == group_id)).all()
    next_number = (max((w.week_number for w in existing_weeks), default=0)) + 1

    week = Week(group_id=group_id, week_number=next_number, label=body.label)
    session.add(week)
    session.commit()
    session.refresh(week)
    return week


@router.post("/groups/{group_id}/populate", response_model=list[WeekRead])
def populate_group_slate(
    group_id: uuid.UUID,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> list[Week]:
    """Re-run auto-population for a group from the odds pool. Admin only."""
    group = _require_member(group_id, current_user, session)
    _require_admin(group, current_user)
    from app.services.auto_slate import auto_populate_group
    return auto_populate_group(group, session)


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

    return _slate_games(week_id, session)


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
    Add a game from the odds pool to a slate by its Odds API ID.
    Admin only; locked once the first game of the slate has kicked off.
    """
    group = _require_member(group_id, current_user, session)
    _require_admin(group, current_user)

    week = session.get(Week, week_id)
    if week is None or week.group_id != group_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Week not found.")

    game = session.exec(select(Game).where(Game.odds_api_id == body.odds_api_id)).first()
    if game is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No game with odds_api_id '{body.odds_api_id}'. "
                   "Check /odds/available for the current pool.",
        )

    # Idempotency: already in this slate.
    already = session.exec(
        select(SlateGame).where(SlateGame.week_id == week_id, SlateGame.game_id == game.id)
    ).first()
    if already:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Game is already in this slate.",
        )

    # Lock check: can't edit after first kickoff.
    existing = _slate_games(week_id, session)
    now = utc_now()
    if existing and min(ensure_utc(g.kickoff_at) for g in existing) <= now:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot modify a slate after the first game has kicked off.",
        )

    session.add(SlateGame(week_id=week_id, game_id=game.id))
    session.commit()

    all_slate = _slate_games(week_id, session)
    first_kickoff = min(ensure_utc(g.kickoff_at) for g in all_slate)
    team_names = f"{game.away_team} at {game.home_team}"

    schedule_pick_reminders(game.id, group_id, ensure_utc(game.kickoff_at), team_names)
    schedule_slate_admin_reminder(week_id, group_id, first_kickoff)
    schedule_odds_refresh_for_slate(week_id, game.sport, first_kickoff)

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
    """Remove a game from a slate. Admin only; locked once the first game has kicked off."""
    group = _require_member(group_id, current_user, session)
    _require_admin(group, current_user)

    slate_game = session.exec(
        select(SlateGame).where(SlateGame.week_id == week_id, SlateGame.game_id == game_id)
    ).first()
    if slate_game is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Game not found in this slate.")

    existing = _slate_games(week_id, session)
    now = utc_now()
    if min((ensure_utc(g.kickoff_at) for g in existing), default=now) <= now:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot modify a slate after the first game has kicked off.",
        )

    sport = session.get(Game, game_id).sport  # type: ignore[union-attr]
    session.delete(slate_game)
    session.commit()
    cancel_pick_reminders(game_id)

    remaining = _slate_games(week_id, session)
    if remaining:
        first_kickoff = min(ensure_utc(g.kickoff_at) for g in remaining)
        schedule_slate_admin_reminder(week_id, group_id, first_kickoff)
        schedule_odds_refresh_for_slate(week_id, sport, first_kickoff)
    else:
        cancel_slate_admin_reminder(week_id)
        cancel_odds_refresh_for_slate(week_id)


# ── Available odds ────────────────────────────────────────────────────────────

@router.get("/odds/available", response_model=list[GameRead])
def get_available_odds(
    sport: str = Query(..., description="Odds API sport key, e.g. 'americanfootball_nfl'"),
    group_id: Optional[uuid.UUID] = Query(None, description="Exclude games already in this group's slates"),
    background_tasks: BackgroundTasks = BackgroundTasks(),
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> list[Game]:
    """
    Return upcoming games for a sport that can be added to a slate.
    Pass group_id to exclude games already assigned to that group.

    If cached odds are stale, a background re-fetch is triggered while
    current data is returned immediately.
    In development, the pool is seeded via POST /dev/mock-games.
    """
    if settings.ODDS_API_KEY:
        newest = session.exec(
            select(Game)
            .where(Game.sport == sport)
            .order_by(Game.odds_fetched_at.desc())  # type: ignore[union-attr]
        ).first()
        age_minutes = (
            (utc_now() - ensure_utc(newest.odds_fetched_at)).total_seconds() / 60
            if newest is not None else float("inf")
        )
        if age_minutes > settings.ODDS_CACHE_TTL_MINUTES:
            if newest is None:
                # Cold start: ingest synchronously so this request returns real data.
                ingest_odds(sport)
            else:
                background_tasks.add_task(ingest_odds, sport)

    query = select(Game).where(
        Game.sport == sport,
        Game.kickoff_at > utc_now(),
    )

    if group_id is not None:
        weeks_in_group = select(Week.id).where(Week.group_id == group_id)
        already_in_group = select(SlateGame.game_id).where(
            SlateGame.week_id.in_(weeks_in_group)  # type: ignore[arg-type]
        )
        query = query.where(Game.id.notin_(already_in_group))  # type: ignore[attr-defined]

    return list(session.exec(query.order_by(Game.kickoff_at)).all())  # type: ignore[arg-type]
