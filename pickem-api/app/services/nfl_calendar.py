"""
Single source of truth for mapping a calendar date onto an NFL season week,
and for realistic NFL weekly game scheduling (Thursday/Sunday/Monday time
slots) used by dev/mock data generation.

Used by auto_slate.py (auto-populating slates from the odds pool), games.py
(manual week creation), and dev.py (mock/dev season seeding) so all three
week-creation paths agree on what week a given date belongs to.
"""

from datetime import date, datetime, timedelta, timezone
from typing import Optional
from zoneinfo import ZoneInfo

_EASTERN = ZoneInfo("America/New_York")

# First kick-off of each NFL regular season (the Thursday opener of Week 1).
# NOTE: NFL openers move around year to year (Labor Day / international games),
# so any season_year missing here falls back to a "first Thursday in September"
# guess in nfl_season_start() below, which may not match the real schedule.
NFL_SEASON_STARTS: dict[int, date] = {
    2024: date(2024, 9, 5),
    2025: date(2025, 9, 4),
    2026: date(2026, 9, 10),  # season opens the week of Sept 9
}

PLAYOFF_LABELS: dict[int, str] = {
    19: "Wild Card",
    20: "Divisional Round",
    21: "Conference Championships",
    22: "Super Bowl",
}


def nfl_season_start(season_year: int) -> date:
    if season_year in NFL_SEASON_STARTS:
        return NFL_SEASON_STARTS[season_year]
    # Fallback: first Thursday in September of that year.
    d = date(season_year, 9, 1)
    while d.weekday() != 3:  # 3 = Thursday
        d += timedelta(days=1)
    return d


def label_for_week_number(week_number: int) -> str:
    if week_number == 0:
        return "Preseason"
    return PLAYOFF_LABELS.get(week_number, f"Week {week_number}")


def nfl_week_number_and_label(d: date, season_year: int) -> tuple[int, str]:
    """
    Map a raw date (e.g. a game's kickoff date, or an admin-submitted
    starts_on) onto an NFL week number and display label.

    Works on any raw date — does NOT require Monday-alignment. Buckets in
    7-day windows from the season's Thursday opener:
      - before season start -> (0, "Preseason")
      - weeks 1-18          -> (n, "Week n")
      - weeks 19-22         -> (n, playoff label)
      - beyond              -> (n, "Week n") fallback
    """
    season_start = nfl_season_start(season_year)
    days = (d - season_start).days
    week_num = 0 if days < 0 else days // 7 + 1
    return week_num, label_for_week_number(week_num)


def monday_of(d: date) -> date:
    return d - timedelta(days=d.weekday())


def thursday_of(d: date) -> date:
    """The Thursday on/before d — i.e. the kickoff day of the NFL week
    containing d. Matches nfl_week_number_and_label's Thu-Wed bucketing, so
    any date in that same NFL week (Thu/Sun/Mon games, or the off days
    around them) resolves to the same anchor."""
    return d - timedelta(days=(d.weekday() - 3) % 7)


def local_date(dt: datetime) -> date:
    """
    The calendar date a game is played on, as experienced in US Eastern
    time — NOT dt.date(), which reads the UTC calendar date. NFL games are
    scheduled in ET, and a Sunday/Monday-night ET kickoff (8+ PM) is already
    the next day in UTC. Using the raw UTC date anywhere week-window spans
    or boundaries get computed (auto_slate.py's _week_window, games.py's
    slate-window enforcement, etc.) will silently miscalculate for any
    evening game — this is the calendar date that must be used instead.
    Requires an aware datetime (see utils.ensure_utc).
    """
    return dt.astimezone(_EASTERN).date()


def _et(d: date, hour: int, minute: int) -> datetime:
    """Convert a local Eastern Time wall-clock moment to UTC. DST-aware —
    the NFL season spans both EDT (through early Nov) and EST (from early
    Nov through the Super Bowl), so this must resolve per-date, not use a
    single fixed UTC offset."""
    return datetime(d.year, d.month, d.day, hour, minute, tzinfo=_EASTERN).astimezone(timezone.utc)


def weekly_slot_kickoff(thursday: date, slot_index: int, slot_count: int, week_number: Optional[int] = None) -> datetime:
    """
    Realistic NFL weekly time slots, anchored to the Thursday of that NFL
    week: Thursday Night Football, Sunday's early (1:00 PM ET) and late
    (4:25 PM ET) windows, and a final prime-time slot that alternates
    between Sunday Night and Monday Night by week number — so a small
    per-week game count still shows both prime-time windows across a season
    instead of always landing on the same one.

    slot_index 0 is always Thursday night. The last slot (slot_count - 1,
    when slot_count >= 2) is the alternating SNF/MNF slot. The second-to-last
    (when slot_count >= 3) is the Sunday late window. Everything else is the
    Sunday early window — the slot most real NFL games actually occupy.
    """
    sunday = thursday + timedelta(days=3)
    monday = thursday + timedelta(days=4)

    if slot_index == 0:
        return _et(thursday, 20, 15)  # Thursday Night Football
    if slot_count >= 2 and slot_index == slot_count - 1:
        if (week_number or 0) % 2 == 0:
            return _et(monday, 20, 15)  # Monday Night Football
        return _et(sunday, 20, 20)  # Sunday Night Football
    if slot_count >= 3 and slot_index == slot_count - 2:
        return _et(sunday, 16, 25)  # Sunday late window
    return _et(sunday, 13, 0)  # Sunday early window
