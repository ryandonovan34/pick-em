"""
Automatic slate population.

When a group is created, this service builds its initial weeks and links games
from the odds pool. The scheduler calls it again after each odds ingest to
add newly-available games to existing groups.

NFL:  games are grouped by NFL week number and labelled "Week 1" … "Week 18",
      then "Wild Card", "Divisional Round", "Conference Championships",
      "Super Bowl".
World Cup: all upcoming games land in one slate (the format is one continuous
      tournament rather than repeating weekly fixtures).
"""

import logging
from datetime import date, datetime, timedelta, timezone

from sqlmodel import Session, select

from app.models import Game, Group, SlateGame, Week
from app.utils import utc_now

logger = logging.getLogger(__name__)

# First kick-off of each NFL regular season (the Thursday opener of Week 1).
_NFL_SEASON_STARTS: dict[int, date] = {
    2024: date(2024, 9, 5),
    2025: date(2025, 9, 4),
    2026: date(2026, 9, 3),
}

_NFL_PLAYOFF_LABELS: dict[int, str] = {
    19: "Wild Card",
    20: "Divisional Round",
    21: "Conference Championships",
    22: "Super Bowl",
}


def _nfl_season_start(season_year: int) -> date:
    if season_year in _NFL_SEASON_STARTS:
        return _NFL_SEASON_STARTS[season_year]
    # Fallback: first Thursday in September of that year.
    d = date(season_year, 9, 1)
    while d.weekday() != 3:  # 3 = Thursday
        d += timedelta(days=1)
    return d


def _nfl_week_label(kickoff: datetime, season_year: int) -> str:
    season_start = _nfl_season_start(season_year)
    days = (kickoff.date() - season_start).days
    if days < 0:
        return "Pre-Season"
    week_num = days // 7 + 1
    return _NFL_PLAYOFF_LABELS.get(week_num, f"Week {week_num}")


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


def _next_week_number(group_id, session: Session) -> int:
    existing = session.exec(select(Week).where(Week.group_id == group_id)).all()
    return (max((w.week_number for w in existing), default=0)) + 1


def _create_week_with_games(
    group: Group,
    label: str,
    week_number: int,
    games: list[Game],
    session: Session,
) -> Week:
    week = Week(group_id=group.id, week_number=week_number, label=label)
    session.add(week)
    session.flush()
    for game in games:
        session.add(SlateGame(week_id=week.id, game_id=game.id))
    return week


def _populate_nfl(group: Group, games: list[Game], session: Session) -> list[Week]:
    by_label: dict[str, list[Game]] = {}
    for game in games:
        label = _nfl_week_label(game.kickoff_at, group.season_year)
        by_label.setdefault(label, []).append(game)

    sorted_labels = sorted(
        by_label.items(),
        key=lambda kv: min(g.kickoff_at for g in kv[1]),
    )

    created: list[Week] = []
    for label, week_games in sorted_labels:
        week_number = _next_week_number(group.id, session)
        week = _create_week_with_games(group, label, week_number, week_games, session)
        created.append(week)

    return created


def _populate_world_cup(group: Group, games: list[Game], session: Session) -> list[Week]:
    week_number = _next_week_number(group.id, session)
    week = _create_week_with_games(group, "World Cup 2026", week_number, games, session)
    return [week]


def auto_populate_group(group: Group, session: Session) -> list[Week]:
    """
    Build the initial weeks for a newly-created group from the odds pool.
    Safe to call on groups that already have weeks — only adds genuinely new games.
    """
    games = _new_games_for_group(group, session)
    if not games:
        logger.info("auto_populate_group: no pool games for sport=%s (group=%s)", group.sport, group.id)
        return []

    if group.sport == "americanfootball_nfl":
        weeks = _populate_nfl(group, games, session)
    else:
        weeks = _populate_world_cup(group, games, session)

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
            if group.sport == "americanfootball_nfl":
                _populate_nfl(group, games, session)
            else:
                _populate_world_cup(group, games, session)
            session.commit()
        except Exception:
            session.rollback()
            logger.exception("auto_populate_all_groups failed for group=%s", group.id)
