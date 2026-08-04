"""
Unit tests for games.py::_week_end — the server-side window-close fallback
used by both add_game_to_slate's enforcement check and the "available odds
for this week" filter.
"""

import uuid
from datetime import date, timedelta

import pytest
from sqlmodel import Session, SQLModel, create_engine

from app.models import Group, Week
from app.routers.games import _week_end


@pytest.fixture(name="mem_session")
def mem_session_fixture():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        yield session
    SQLModel.metadata.drop_all(engine)


def _make_group(session: Session) -> Group:
    group = Group(
        name="Test", admin_id=uuid.uuid4(), join_code=str(uuid.uuid4())[:6].upper(),
        sport="americanfootball_nfl", mode="season", season_year=2099,
    )
    session.add(group)
    session.flush()
    return group


def _make_week(session: Session, group: Group, week_number: int, starts_on: date, ends_on: date | None = None) -> Week:
    week = Week(group_id=group.id, week_number=week_number, label=f"Week {week_number}", starts_on=starts_on, ends_on=ends_on)
    session.add(week)
    session.flush()
    return week


def test_explicit_ends_on_always_wins(mem_session: Session):
    group = _make_group(mem_session)
    week = _make_week(mem_session, group, 1, date(2099, 9, 8), ends_on=date(2099, 9, 30))
    assert _week_end(week, mem_session) == date(2099, 9, 30)


def test_falls_back_to_plus_seven_for_evenly_spaced_weeks(mem_session: Session):
    group = _make_group(mem_session)
    week1 = _make_week(mem_session, group, 1, date(2099, 9, 8))
    _make_week(mem_session, group, 2, date(2099, 9, 15))  # exactly 7 days later
    # The next week starting exactly 7 days out must NOT shrink the window
    # below the standard +7 (which is what makes Monday Night Football,
    # kicking off on that next Monday, still count as part of week 1).
    assert _week_end(week1, mem_session) == date(2099, 9, 8) + timedelta(days=7)


def test_extends_to_day_before_next_week_when_gap_is_wider(mem_session: Session):
    group = _make_group(mem_session)
    week1 = _make_week(mem_session, group, -4, date(2099, 7, 18))  # Preseason Week 1, generously early
    _make_week(mem_session, group, -3, date(2099, 8, 15))  # Preseason Week 2, ~4 weeks later
    assert _week_end(week1, mem_session) == date(2099, 8, 14)


def test_falls_back_to_plus_seven_when_no_next_week(mem_session: Session):
    group = _make_group(mem_session)
    last_week = _make_week(mem_session, group, 22, date(2100, 2, 1))  # Super Bowl, nothing after it
    assert _week_end(last_week, mem_session) == date(2100, 2, 1) + timedelta(days=7)


def test_returns_none_when_starts_on_unset(mem_session: Session):
    group = _make_group(mem_session)
    week = Week(group_id=group.id, week_number=1, label="Week 1", starts_on=None, ends_on=None)
    mem_session.add(week)
    mem_session.flush()
    assert _week_end(week, mem_session) is None
