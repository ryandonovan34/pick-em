"""
Automatic slate population.

When a group is created, this service builds its initial weeks and links games
from the odds pool. The scheduler calls it again after each odds ingest to
add newly-available games to existing groups.

Games are bucketed by real NFL week number (see services/nfl_calendar.py).
Preseason games are skipped unless group.include_preseason is set; playoff
games are skipped unless group.include_playoffs is set. Re-runs are safe:
get_or_create_week() reuses the existing Week for a given (group, week_number)
instead of creating a duplicate, and is race-safe against the APScheduler
background thread and concurrent admin requests hitting this at the same time
(see migration 007's unique constraint).
"""

import logging
from datetime import date, timedelta
from typing import Optional

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.models import Game, Group, SlateGame, Week
from app.services.nfl_calendar import local_date, monday_of, nfl_week_number_and_label
from app.utils import ensure_utc, utc_now

logger = logging.getLogger(__name__)


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


def get_or_create_week(
    group: Group,
    week_number: int,
    label: str,
    games: list[Game],
    session: Session,
) -> Week:
    """
    Return the Week for (group, week_number), creating it if needed, and link
    `games` into its slate either way.

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
        starts_on, ends_on = _week_window(games)
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

    _link_new_games(week, games, session)
    _recompute_week_window(week, session)
    return week


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
