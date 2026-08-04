"""
Integration tests for auto_slate.py — in particular that include_preseason/
include_playoffs actually gate what gets auto-populated, and that re-running
populate on an already-populated week merges instead of duplicating it.
"""

import uuid
from datetime import timedelta

import pytest
from sqlmodel import Session, SQLModel, create_engine, select

from app.models import Game, Group, SlateGame, Week
from app.services.auto_slate import _week_window, auto_populate_group, create_standard_season_weeks
from app.services.nfl_calendar import nfl_season_start, thursday_of, weekly_slot_kickoff
from app.utils import utc_now


@pytest.fixture(name="mem_session")
def mem_session_fixture():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        yield session
    SQLModel.metadata.drop_all(engine)


def _future_season_year() -> int:
    """A season_year whose start is safely in the future no matter when the
    test suite runs — auto_populate only considers games with kickoff > now,
    so fixtures need a season_start that's still ahead of "now"."""
    return utc_now().year + 2


def _make_group(session: Session, **overrides) -> Group:
    group = Group(
        name="Test", admin_id=uuid.uuid4(), join_code=str(uuid.uuid4())[:6].upper(),
        sport="americanfootball_nfl", mode="season",
        season_year=overrides.pop("season_year", _future_season_year()),
        **overrides,
    )
    session.add(group)
    session.flush()
    return group


def _make_game(session: Session, kickoff_offset_days: float, home: str, away: str) -> Game:
    game = Game(
        sport="americanfootball_nfl",
        home_team=home, away_team=away,
        spread=-3.5, favorite_team=home,
        kickoff_at=utc_now() + timedelta(days=kickoff_offset_days),
    )
    session.add(game)
    session.flush()
    return game


def _game_at(kickoff, home: str = "Team A", away: str = "Team B") -> Game:
    return Game(sport="americanfootball_nfl", home_team=home, away_team=away, spread=-3.5, favorite_team=home, kickoff_at=kickoff)


class TestWeekWindowCoversMondayNightFootball:
    """
    A standard NFL week runs Thursday through the FOLLOWING Monday (MNF),
    which is +7 days from a Monday-anchored starts_on — not +6 (Mon-Sun).
    Regression test: _week_window used to threshold at +6, which meant every
    week with a Monday game got a spurious ends_on set (and, on the iOS
    side, rendered a raw date range instead of "Week N" for exactly half of
    all weeks).
    """

    def test_thursday_through_monday_night_football_stays_within_standard_window(self):
        thu = thursday_of(utc_now().date() + timedelta(days=30))
        thursday_game = _game_at(weekly_slot_kickoff(thu, 0, 2))
        monday_game = _game_at(weekly_slot_kickoff(thu, 1, 2, week_number=2))  # even -> MNF

        starts_on, ends_on = _week_window([thursday_game, monday_game])
        assert ends_on is None

    def test_game_beyond_monday_night_football_still_widens_the_window(self):
        thu = thursday_of(utc_now().date() + timedelta(days=30))
        thursday_game = _game_at(weekly_slot_kickoff(thu, 0, 2))
        tuesday_game = _game_at(weekly_slot_kickoff(thu, 0, 2) + timedelta(days=5))  # genuinely beyond MNF

        starts_on, ends_on = _week_window([thursday_game, tuesday_game])
        assert ends_on is not None
        assert ends_on > starts_on + timedelta(days=7)


class TestPreseasonPlayoffFiltering:
    def test_preseason_excluded_by_default(self, mem_session: Session):
        group = _make_group(mem_session)  # include_preseason defaults False
        season_start = nfl_season_start(group.season_year)
        days_until_start = (season_start - utc_now().date()).days
        # Simulate a preseason game: kicks off a few days before the season
        # start, but still in the future relative to "now" (auto_populate
        # only looks at future games) — season_year is chosen far enough
        # ahead that days_until_start comfortably exceeds this offset.
        _make_game(mem_session, kickoff_offset_days=days_until_start - 5, home="Team A", away="Team B")

        weeks = auto_populate_group(group, mem_session)
        assert weeks == []
        assert mem_session.exec(select(Week)).all() == []

    def test_preseason_included_when_enabled(self, mem_session: Session):
        group = _make_group(mem_session, include_preseason=True)
        season_start = nfl_season_start(group.season_year)
        days_until_start = (season_start - utc_now().date()).days
        _make_game(mem_session, kickoff_offset_days=days_until_start - 5, home="Team A", away="Team B")

        weeks = auto_populate_group(group, mem_session)
        assert len(weeks) == 1
        assert weeks[0].label == "Preseason"
        assert weeks[0].week_number == 0

    def test_playoffs_excluded_when_disabled(self, mem_session: Session):
        group = _make_group(mem_session, include_playoffs=False)
        season_start = nfl_season_start(group.season_year)
        days_until_start = (season_start - utc_now().date()).days
        # Week 19 (Wild Card) spans day-offsets [18*7, 19*7) from season start.
        _make_game(mem_session, kickoff_offset_days=days_until_start + 18 * 7 + 3, home="Team A", away="Team B")

        weeks = auto_populate_group(group, mem_session)
        assert weeks == []

    def test_playoffs_included_by_default(self, mem_session: Session):
        group = _make_group(mem_session)  # include_playoffs defaults True
        season_start = nfl_season_start(group.season_year)
        days_until_start = (season_start - utc_now().date()).days
        _make_game(mem_session, kickoff_offset_days=days_until_start + 18 * 7 + 3, home="Team A", away="Team B")

        weeks = auto_populate_group(group, mem_session)
        assert len(weeks) == 1
        assert weeks[0].label == "Wild Card"
        assert weeks[0].week_number == 19


class TestCreateStandardSeasonWeeks:
    """
    Weeks are calendar structure, not a byproduct of odds data — a
    freshly-created group should immediately have all 18 regular-season
    weeks (plus playoffs/preseason per its settings) even with zero games
    in the odds pool.
    """

    def test_default_group_gets_regular_season_and_playoffs_but_not_preseason(self, mem_session: Session):
        group = _make_group(mem_session)  # include_preseason=False, include_playoffs=True
        weeks = create_standard_season_weeks(group, mem_session)
        numbers = sorted(w.week_number for w in weeks)
        assert numbers == list(range(1, 19)) + list(range(19, 23))
        assert 0 not in numbers

    def test_preseason_enabled_adds_week_zero(self, mem_session: Session):
        group = _make_group(mem_session, include_preseason=True)
        weeks = create_standard_season_weeks(group, mem_session)
        preseason = next(w for w in weeks if w.week_number == 0)
        assert preseason.label == "Preseason"
        # Explicit wide window (not the standard +7-day fallback) since a
        # single lump bucket spans several real weeks.
        assert preseason.ends_on is not None
        assert preseason.ends_on < nfl_season_start(group.season_year)

    def test_playoffs_disabled_stops_at_week_18(self, mem_session: Session):
        group = _make_group(mem_session, include_playoffs=False)
        weeks = create_standard_season_weeks(group, mem_session)
        assert sorted(w.week_number for w in weeks) == list(range(1, 19))

    def test_week_1_starts_on_the_season_opening_thursdays_monday(self, mem_session: Session):
        group = _make_group(mem_session)
        weeks = create_standard_season_weeks(group, mem_session)
        week1 = next(w for w in weeks if w.week_number == 1)
        season_start = nfl_season_start(group.season_year)
        assert week1.starts_on == season_start - timedelta(days=season_start.weekday())
        assert week1.ends_on is None  # standard week — relies on the +7-day fallback

    def test_calling_twice_does_not_duplicate(self, mem_session: Session):
        group = _make_group(mem_session)
        create_standard_season_weeks(group, mem_session)
        create_standard_season_weeks(group, mem_session)
        all_weeks = mem_session.exec(select(Week).where(Week.group_id == group.id)).all()
        assert len(all_weeks) == 22  # 18 regular season + 4 playoff, no duplicates

    def test_leaves_existing_week_untouched(self, mem_session: Session):
        group = _make_group(mem_session)
        first_pass = create_standard_season_weeks(group, mem_session)
        week1_id = next(w.id for w in first_pass if w.week_number == 1)

        second_pass = create_standard_season_weeks(group, mem_session)
        week1_again = next(w for w in second_pass if w.week_number == 1)
        assert week1_again.id == week1_id


class TestRepeatedPopulateMergesIntoExistingWeek:
    def test_second_batch_for_same_week_joins_existing_row_not_a_duplicate(self, mem_session: Session):
        group = _make_group(mem_session)
        season_start = nfl_season_start(group.season_year)
        days_until_start = (season_start - utc_now().date()).days

        game1 = _make_game(mem_session, kickoff_offset_days=days_until_start + 3, home="Team A", away="Team B")
        weeks = auto_populate_group(group, mem_session)
        assert len(weeks) == 1
        first_week_id = weeks[0].id

        # A second game arrives later (simulating a subsequent odds ingest)
        # that maps to the SAME NFL week.
        game2 = _make_game(mem_session, kickoff_offset_days=days_until_start + 1, home="Team C", away="Team D")
        weeks_again = auto_populate_group(group, mem_session)
        assert len(weeks_again) == 1
        assert weeks_again[0].id == first_week_id  # merged, not duplicated

        all_weeks = mem_session.exec(select(Week).where(Week.group_id == group.id)).all()
        assert len(all_weeks) == 1

        linked_game_ids = {
            sg.game_id for sg in mem_session.exec(
                select(SlateGame).where(SlateGame.week_id == first_week_id)
            ).all()
        }
        assert linked_game_ids == {game1.id, game2.id}
