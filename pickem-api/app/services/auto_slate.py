"""
Automatic slate population.

Two things happen here, both keyed on the real NFL week number (see
services/nfl_calendar.py):

1. create_standard_season_weeks() eagerly creates the full season's week
   CONTAINERS for a group — Week 1-18, plus Preseason/playoff weeks per the
   group's include_preseason/include_playoffs — independent of whether the
   odds pool has any games for them yet. Weeks are calendar structure, not a
   byproduct of odds data; a group shouldn't show "no weeks" just because
   nothing's been ingested for a given week yet. Called on group creation
   and from the admin "populate" action.
2. auto_populate_group() / auto_populate_all_groups() link odds-pool games
   into the right week (creating it if step 1 somehow hasn't run yet).
   Preseason games are skipped unless group.include_preseason is set;
   playoff games are skipped unless group.include_playoffs is set.

Both paths funnel through _get_or_create_week_row(), which reuses the
existing Week for a given (group, week_number) instead of creating a
duplicate, and is race-safe against the APScheduler background thread and
concurrent admin requests hitting this at the same time (see migration 007's
unique constraint).
"""

import logging
from datetime import date, timedelta
from typing import Optional

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.models import Game, Group, SlateGame, Week
from app.services.nfl_calendar import (
    label_for_week_number,
    local_date,
    monday_of,
    nfl_season_start,
    nfl_week_number_and_label,
)
from app.utils import ensure_utc, utc_now

logger = logging.getLogger(__name__)

# How far before the season opener the single "Preseason" bucket's window
# starts — generous on purpose (covers a Hall of Fame Game as well as the
# regular 3-week preseason slate) since under-covering would silently reject
# a real preseason game from being added to the slate.
_PRESEASON_LOOKBACK_DAYS = 42


def _new_games_for_group(group: Group, session: Session) -> list[Game]:
    """Return future games for the group's sport not yet in any of its slates."""
    weeks_in_group = select(Week.id).where(Week.group_id == group.id)
    already_linked = select(SlateGame.game_id).where(
        SlateGame.week_id.in_(weeks_in_group)  # type: ignore[arg-type]
    )
    return list(
        session.exec(
            select(Game).where(
                Game.sport == group.sport,
                Game.kickoff_at > utc_now(),
                Game.id.notin_(already_linked),  # type: ignore[attr-defined]
            ).order_by(Game.kickoff_at)  # type: ignore[arg-type]
        ).all()
    )


def _week_window(games: list[Game]) -> tuple[date, Optional[date]]:
    """Compute (starts_on, ends_on) covering every game's kickoff date.
    starts_on is always the Monday of the earliest game's calendar week;
    ends_on is only set (widening past the standard NFL week — Thursday
    through the following Monday, i.e. +7 days from a Monday-anchored
    starts_on, matching games.py::_week_end's fallback) when a game falls
    after even that. Uses local_date (ET), not the raw UTC date — an 8+ PM
    ET kickoff (Sunday/Monday night football) is already the next day in
    UTC, which would otherwise miscalculate the span."""
    local_dates = [local_date(ensure_utc(g.kickoff_at)) for g in games]
    starts_on = monday_of(min(local_dates))
    last_day = max(local_dates)
    ends_on = last_day if last_day > starts_on + timedelta(days=7) else None
    return starts_on, ends_on


def _link_new_games(week: Week, games: list[Game], session: Session) -> None:
    """Add SlateGame rows for any of `games` not already linked to `week`."""
    already_linked = set(
        session.exec(select(SlateGame.game_id).where(SlateGame.week_id == week.id)).all()
    )
    for game in games:
        if game.id not in already_linked:
            session.add(SlateGame(week_id=week.id, game_id=game.id))
    session.flush()


def _recompute_week_window(week: Week, session: Session) -> None:
    """Re-derive starts_on/ends_on from every game currently linked to this
    week (not just the newly-added batch) — a newly-arrived game can kick off
    earlier than the window already computed, so this must widen backward as
    well as forward."""
    linked_game_ids = select(SlateGame.game_id).where(SlateGame.week_id == week.id)
    games = list(session.exec(select(Game).where(Game.id.in_(linked_game_ids))).all())  # type: ignore[attr-defined]
    if not games:
        return
    week.starts_on, week.ends_on = _week_window(games)
    session.add(week)


def _get_or_create_week_row(
    group: Group,
    week_number: int,
    label: str,
    starts_on: date,
    ends_on: Optional[date],
    session: Session,
) -> Week:
    """
    Return the Week for (group, week_number), creating it with the given
    window if it doesn't exist yet. Does NOT touch games/slate membership —
    see get_or_create_week() for the games-linking variant.

    Safe to call concurrently: two callers racing to create the same
    (group_id, week_number) will both attempt the insert, but the unique
    constraint (migration 007) means only one wins — the loser catches the
    IntegrityError inside a SAVEPOINT (so it doesn't roll back anything else
    already flushed in this session) and re-selects the winner's row instead.
    """
    week = session.exec(
        select(Week).where(Week.group_id == group.id, Week.week_number == week_number)
    ).first()

    if week is None:
        candidate = Week(
            group_id=group.id, week_number=week_number, label=label,
            starts_on=starts_on, ends_on=ends_on,
        )
        try:
            with session.begin_nested():
                session.add(candidate)
                session.flush()
            week = candidate
        except IntegrityError:
            week = session.exec(
                select(Week).where(Week.group_id == group.id, Week.week_number == week_number)
            ).first()
            if week is None:
                raise

    return week


def get_or_create_week(
    group: Group,
    week_number: int,
    label: str,
    games: list[Game],
    session: Session,
) -> Week:
    """Return the Week for (group, week_number), creating it if needed
    (window derived from `games`), and link `games` into its slate either way."""
    starts_on, ends_on = _week_window(games)
    week = _get_or_create_week_row(group, week_number, label, starts_on, ends_on, session)
    _link_new_games(week, games, session)
    _recompute_week_window(week, session)
    return week


def _standard_season_week_numbers(group: Group) -> list[int]:
    numbers = list(range(1, 19))  # Week 1-18 always present.
    if group.include_preseason:
        numbers.append(0)
    if group.include_playoffs:
        numbers.extend(range(19, 23))
    return sorted(numbers)


def create_standard_season_weeks(group: Group, session: Session) -> list[Week]:
    """
    Eagerly create every standard week container for the group's season —
    independent of whether the odds pool has any games for them yet, so a
    freshly-created group never shows "no weeks." Safe to call repeatedly
    (e.g. every time the admin hits "populate"): existing weeks are left
    untouched, only missing ones get created.
    """
    season_start = nfl_season_start(group.season_year)
    weeks: list[Week] = []
    for week_number in _standard_season_week_numbers(group):
        if week_number == 0:
            # Single lump "Preseason" bucket — spans several real weeks, so
            # unlike a standard week it needs an explicit (wide) ends_on
            # rather than relying on the +7-day standard-week fallback.
            starts_on = monday_of(season_start - timedelta(days=_PRESEASON_LOOKBACK_DAYS))
            ends_on: Optional[date] = season_start - timedelta(days=1)
        else:
            starts_on = monday_of(season_start + timedelta(weeks=week_number - 1))
            ends_on = None  # standard Thu-Mon window; falls back to +7 days (games.py::_week_end)
        weeks.append(_get_or_create_week_row(
            group, week_number, label_for_week_number(week_number), starts_on, ends_on, session,
        ))
    return weeks


def _populate_nfl(group: Group, games: list[Game], session: Session) -> list[Week]:
    by_week: dict[int, tuple[str, list[Game]]] = {}
    for game in games:
        week_number, label = nfl_week_number_and_label(game.kickoff_at.date(), group.season_year)
        if week_number == 0 and not group.include_preseason:
            continue
        if week_number >= 19 and not group.include_playoffs:
            continue
        bucket = by_week.setdefault(week_number, (label, []))
        bucket[1].append(game)

    touched: list[Week] = []
    for week_number in sorted(by_week):
        label, week_games = by_week[week_number]
        touched.append(get_or_create_week(group, week_number, label, week_games, session))
    return touched


def auto_populate_group(group: Group, session: Session) -> list[Week]:
    """
    Build the initial weeks for a newly-created group from the odds pool.
    Safe to call on groups that already have weeks — only adds genuinely new games.
    """
    games = _new_games_for_group(group, session)
    if not games:
        logger.info("auto_populate_group: no pool games for sport=%s (group=%s)", group.sport, group.id)
        return []

    weeks = _populate_nfl(group, games, session)

    session.commit()
    for w in weeks:
        session.refresh(w)

    logger.info(
        "auto_populate_group: created %d week(s) for group=%s sport=%s",
        len(weeks), group.id, group.sport,
    )
    return weeks


def auto_populate_all_groups(session: Session) -> None:
    """
    Called after each odds ingest. For every existing group, adds new weeks
    for any games that appeared in the pool since the last run.
    """
    groups = session.exec(select(Group)).all()
    for group in groups:
        try:
            games = _new_games_for_group(group, session)
            if not games:
                continue
            _populate_nfl(group, games, session)
            session.commit()
        except Exception:
            session.rollback()
            logger.exception("auto_populate_all_groups failed for group=%s", group.id)
