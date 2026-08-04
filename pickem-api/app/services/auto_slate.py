"""
Season week structure.

create_standard_season_weeks() eagerly creates the full season's week
CONTAINERS for a group — Week 1-18, plus preseason (4 weeks)/playoff weeks
per the group's include_preseason/include_playoffs — independent of whether
the odds pool has any games for them yet. Weeks are calendar structure, not
a byproduct of odds data or of what's in a slate; a group shouldn't show "no
weeks" just because nothing's been added to a slate yet. Called on group
creation and from the admin "populate" action (the latter mainly to backfill
groups created before this existed).

Games are NEVER auto-added to a week's slate — that's an explicit admin
action (games.py::add_game_to_slate), which is also what triggers the
slate-ready/game-added notification to the rest of the group. This module
only ever creates empty week containers.

_get_or_create_week_row() is race-safe against concurrent admin requests
hitting this at the same time (see migration 007's unique constraint on
(group_id, week_number)).
"""

import logging
from datetime import date, timedelta
from typing import Optional

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.models import Game, Group, SlateGame, Week
from app.services.nfl_calendar import label_for_week_number, local_date, monday_of, nfl_season_start
from app.utils import ensure_utc

logger = logging.getLogger(__name__)


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
    see get_or_create_week() for the games-linking variant (used only by
    dev.py's mock-data seeding — production never auto-adds games).

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
    (window derived from `games`), and link `games` into its slate either
    way. Only used by dev.py's mock-data seeding, which stands in for an
    admin explicitly picking games — production code never calls this to
    auto-populate a slate."""
    starts_on, ends_on = _week_window(games)
    week = _get_or_create_week_row(group, week_number, label, starts_on, ends_on, session)
    _link_new_games(week, games, session)
    _recompute_week_window(week, session)
    return week


def _standard_season_week_numbers(group: Group) -> list[int]:
    numbers = list(range(1, 19))  # Week 1-18 always present.
    if group.include_preseason:
        numbers.extend(range(-4, 0))  # 4 preseason weeks: -4 (Week 1) .. -1 (Week 4)
    if group.include_playoffs:
        numbers.extend(range(19, 23))
    return sorted(numbers)


def create_standard_season_weeks(group: Group, session: Session) -> list[Week]:
    """
    Eagerly create every standard week container for the group's season —
    independent of whether the odds pool has any games for them yet, and
    with NO games attached (the admin picks which games go into a week's
    slate; nothing is auto-selected). Safe to call repeatedly (e.g. every
    time the admin hits "populate"): existing weeks are left untouched, only
    missing ones get created.
    """
    season_start = nfl_season_start(group.season_year)
    weeks: list[Week] = []
    for week_number in _standard_season_week_numbers(group):
        if week_number < 0:
            # Preseason Week N (1-4, oldest to newest) — each is its own
            # clean 7-day bucket counting backward from the opener, exactly
            # matching nfl_week_number_and_label's classification, so it
            # relies on the same +7-day fallback as a regular week (no
            # explicit ends_on needed — see games.py::_week_end).
            weeks_before_start = -week_number
            starts_on = season_start - timedelta(days=weeks_before_start * 7)
        else:
            starts_on = monday_of(season_start + timedelta(weeks=week_number - 1))
        weeks.append(_get_or_create_week_row(
            group, week_number, label_for_week_number(week_number), starts_on, None, session,
        ))
    return weeks
