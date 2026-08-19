"""
Week and game slate management.

Weeks are the time-boxed containers for a pick slate, created empty as
standard season containers when a group is made (see
auto_slate.create_standard_season_weeks). Admins add or remove games from a
slate explicitly — nothing is auto-populated.

The slate_games junction table lets the same game appear in multiple groups'
slates simultaneously, so odds updates and result posting flow through once.
"""

import uuid
from datetime import date, timedelta
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response, status
from app.utils import ensure_utc, utc_now
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.auth.dependencies import get_current_user
from app.config import settings
from app.database import get_session
from app.models import Game, Group, GroupMember, SlateGame, User, Week
from app.routers.groups import _require_admin, _require_member
from app.schemas.game import AddGameToSlate, GameRead, WeekCreate, WeekRead
from app.services.nfl_calendar import local_date, monday_of, nfl_week_number_and_label
from app.services.odds import ingest_odds
from app.services.scheduler import (
    cancel_odds_refresh_for_game,
    cancel_slate_admin_reminder,
    schedule_odds_refresh_for_game,
    schedule_pick_reminders_for_week,
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

def _week_end(week: Week, session: Session) -> Optional[date]:
    """The last day of this week's window. Explicit ends_on wins. Otherwise
    falls back to the standard NFL week — Thursday through the FOLLOWING
    Monday (Monday Night Football), which is +7 days from a Monday-anchored
    starts_on, not +6 (a real NFL week never fits Mon-Sun; it structurally
    always runs into the next ISO week for its Monday game) — UNLESS the
    next standard week (by week_number, within the same group) starts more
    than 7 days later, in which case the window extends up to the day
    before that next week starts. Every standard week (regular season,
    playoffs, and — as of auto_slate.create_standard_season_weeks's uniform
    7-day preseason cadence — all 4 preseason weeks too) has its next
    sibling exactly 7 days later, so max() below reduces to the plain +7
    fallback for all of them; this only matters as a safety net for
    manually-created weeks with an irregular gap to whatever's next."""
    if week.ends_on:
        return week.ends_on
    if week.starts_on is None:
        return None
    fallback = week.starts_on + timedelta(days=7)
    next_week = session.exec(
        select(Week)
        .where(Week.group_id == week.group_id, Week.week_number > week.week_number)
        .order_by(Week.week_number)
    ).first()
    if next_week is not None and next_week.starts_on is not None:
        return max(fallback, next_week.starts_on - timedelta(days=1))
    return fallback


def _week_to_read(week: Week, session: Session) -> WeekRead:
    games = _slate_games(week.id, session)
    first_kickoff = min((g.kickoff_at for g in games), default=None)
    last_kickoff = max((g.kickoff_at for g in games), default=None)
    # The RAW column, not _week_end()'s always-computed +7-day fallback:
    # clients (iOS's Week.displayLabel) use "is ends_on set" to decide
    # between showing "Week N" and a raw date range — a standard week must
    # serialize ends_on=null to get the "Week N" label, even though
    # _week_end()'s fallback is exactly what server-side window enforcement
    # (add_game_to_slate, get_available_odds) should keep using internally.
    return WeekRead(
        id=week.id,
        group_id=week.group_id,
        week_number=week.week_number,
        label=week.label,
        starts_on=week.starts_on,
        ends_on=week.ends_on,
        created_at=week.created_at,
        first_kickoff_at=first_kickoff,
        last_kickoff_at=last_kickoff,
    )


@router.get("/groups/{group_id}/weeks", response_model=list[WeekRead])
def list_weeks(
    group_id: uuid.UUID,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> list[WeekRead]:
    """Return all weeks/slates for a group, ordered by week_number."""
    _require_member(group_id, current_user, session)
    weeks = list(
        session.exec(
            select(Week)
            .where(Week.group_id == group_id)
            .order_by(Week.week_number)  # type: ignore[arg-type]
        ).all()
    )
    return [_week_to_read(w, session) for w in weeks]


@router.post("/groups/{group_id}/weeks", response_model=WeekRead, status_code=status.HTTP_201_CREATED)
def create_week(
    group_id: uuid.UUID,
    body: WeekCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> WeekRead:
    """Create a new week/slate anchored to a calendar week (Mon–Sun). Admin only."""
    group = _require_member(group_id, current_user, session)
    _require_admin(group, current_user)

    # week_number is derived from the RAW starts_on (before Monday-snapping) —
    # NFL weeks are Thursday-anchored, so deriving it from an already-snapped
    # date can misclassify dates near the season boundary. starts_on itself
    # is still stored snapped to Monday for calendar-window purposes.
    week_number = body.week_number
    if week_number is None:
        week_number, _label = nfl_week_number_and_label(body.starts_on, group.season_year)
    snapped_starts_on = monday_of(body.starts_on)

    existing_weeks = session.exec(select(Week).where(Week.group_id == group_id)).all()

    # Prevent duplicate weeks for the same calendar week or NFL week number.
    if any(w.starts_on == snapped_starts_on for w in existing_weeks):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"A week starting on {snapped_starts_on} already exists for this group.",
        )
    if any(w.week_number == week_number for w in existing_weeks):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"A week with week_number={week_number} already exists for this group.",
        )

    week = Week(
        group_id=group_id, week_number=week_number, label=body.label,
        starts_on=snapped_starts_on, ends_on=body.ends_on,
    )
    session.add(week)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"A week with week_number={week_number} already exists for this group.",
        )
    session.refresh(week)
    return _week_to_read(week, session)


@router.post("/groups/{group_id}/populate", response_model=list[WeekRead])
def populate_group_slate(
    group_id: uuid.UUID,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> list[Week]:
    """
    Ensure the group has its standard season week containers — a backfill
    for groups created before this existed; new groups already get these at
    creation time. Never touches slate membership: games are only ever added
    to a week by the admin explicitly picking them (POST .../games below),
    which is also what notifies the rest of the group. Admin only.
    """
    group = _require_member(group_id, current_user, session)
    _require_admin(group, current_user)

    from app.services.auto_slate import create_standard_season_weeks
    weeks = create_standard_season_weeks(group, session)
    session.commit()
    for w in weeks:
        session.refresh(w)
    return [_week_to_read(w, session) for w in weeks]


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

    # Calendar-week enforcement: game must kick off within this week's window.
    # Uses local_date (ET), not the raw UTC date — an 8+ PM ET kickoff (Sunday/
    # Monday night football) is already the next day in UTC.
    if week.starts_on is not None:
        game_date = local_date(ensure_utc(game.kickoff_at))
        week_end = _week_end(week, session)
        if not (week.starts_on <= game_date <= week_end):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    f"Game kicks off on {game_date} (ET), which is outside this week's "
                    f"window ({week.starts_on} – {week_end}). Add it to the correct week."
                ),
            )

    now = utc_now()
    if ensure_utc(game.kickoff_at) <= now:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot add a game that has already kicked off.",
        )

    existing = _slate_games(week_id, session)
    slate_was_empty = len(existing) == 0
    session.add(SlateGame(week_id=week_id, game_id=game.id))
    session.commit()

    all_slate = _slate_games(week_id, session)
    first_kickoff = min(ensure_utc(g.kickoff_at) for g in all_slate)

    schedule_pick_reminders_for_week(week_id, group_id, all_slate)
    schedule_slate_admin_reminder(week_id, group_id, first_kickoff)
    schedule_odds_refresh_for_game(game.id, game.sport, ensure_utc(game.kickoff_at))

    week = session.get(Week, week_id)
    members_with_tokens = session.exec(
        select(User)
        .join(GroupMember, GroupMember.user_id == User.id)  # type: ignore[arg-type]
        .where(
            GroupMember.group_id == group_id,
            User.fcm_token.isnot(None),  # type: ignore[union-attr]
            User.id != current_user.id,
        )
    ).all()
    tokens = [m.fcm_token for m in members_with_tokens if m.fcm_token]
    if tokens and week:
        if slate_was_empty:
            from app.services.notifications import send_slate_ready
            send_slate_ready(tokens, group.name, week.label)
        else:
            from app.services.notifications import send_game_added
            send_game_added(tokens, group.name, week.label, game.away_team, game.home_team)

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

    game_to_remove = session.get(Game, game_id)
    if game_to_remove is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Game not found.")
    if ensure_utc(game_to_remove.kickoff_at) <= utc_now():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot remove a game that has already kicked off.",
        )

    session.delete(slate_game)
    session.commit()
    # Each slate game has its own pre-kickoff odds refresh now (see
    # add_game_to_slate) — removing one doesn't affect any other game's job.
    cancel_odds_refresh_for_game(game_id)

    remaining = _slate_games(week_id, session)
    schedule_pick_reminders_for_week(week_id, group_id, remaining)
    if remaining:
        first_kickoff = min(ensure_utc(g.kickoff_at) for g in remaining)
        schedule_slate_admin_reminder(week_id, group_id, first_kickoff)
    else:
        cancel_slate_admin_reminder(week_id)

    week = session.get(Week, week_id)
    members_with_tokens = session.exec(
        select(User)
        .join(GroupMember, GroupMember.user_id == User.id)  # type: ignore[arg-type]
        .where(
            GroupMember.group_id == group_id,
            User.fcm_token.isnot(None),  # type: ignore[union-attr]
            User.id != current_user.id,
        )
    ).all()
    tokens = [m.fcm_token for m in members_with_tokens if m.fcm_token]
    if tokens and week:
        from app.services.notifications import send_game_removed
        send_game_removed(tokens, group.name, week.label, game_to_remove.away_team, game_to_remove.home_team)


# ── Available odds ────────────────────────────────────────────────────────────

@router.get("/odds/available", response_model=list[GameRead])
def get_available_odds(
    response: Response,
    sport: str = Query(..., description="Odds API sport key, e.g. 'americanfootball_nfl'"),
    group_id: Optional[uuid.UUID] = Query(None, description="Exclude games already in this group's slates"),
    week_id: Optional[uuid.UUID] = Query(None, description="Restrict to games within this week's Mon–Sun window"),
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

    Sets X-Cache response header: HIT | MISS:cold | MISS:stale | SKIP
    """
    import logging as _logging
    _log = _logging.getLogger(__name__)

    x_cache = "SKIP"
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
                _log.info("[odds] Cache COLD for %s — ingesting synchronously", sport)
                x_cache = "MISS:cold"
                ingest_odds(sport)
            else:
                _log.info("[odds] Cache STALE (%.1f min) for %s — refreshing in background", age_minutes, sport)
                x_cache = "MISS:stale"
                background_tasks.add_task(ingest_odds, sport)
        else:
            _log.info("[odds] Cache HIT for %s (%.1f min old)", sport, age_minutes)
            x_cache = "HIT"

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

    # If a specific week is requested, restrict to that week's date window.
    # Compares in ET, not UTC — an 8+ PM ET kickoff (Sunday/Monday night
    # football) is already the next day in UTC, which would otherwise
    # silently exclude/include games on the wrong side of the boundary.
    if week_id is not None:
        target_week = session.get(Week, week_id)
        if target_week is not None and target_week.starts_on is not None:
            from sqlalchemy import func, cast
            from sqlalchemy.types import Date as SADate
            week_start = target_week.starts_on
            week_end_exclusive = _week_end(target_week, session) + timedelta(days=1)
            query = query.where(
                cast(func.timezone("America/New_York", Game.kickoff_at), SADate) >= week_start,  # type: ignore[arg-type]
                cast(func.timezone("America/New_York", Game.kickoff_at), SADate) < week_end_exclusive,    # type: ignore[arg-type]
            )

    games = list(session.exec(query.order_by(Game.kickoff_at)).all())  # type: ignore[arg-type]
    response.headers["X-Cache"] = x_cache
    return games
