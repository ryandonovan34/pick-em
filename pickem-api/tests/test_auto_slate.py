"""
Integration tests for auto_slate.py — in particular that
create_standard_season_weeks() respects include_preseason/include_playoffs
and never touches slate membership (games are only ever added by an admin
explicitly picking them), and that get_or_create_week() (used by dev.py's
mock-data seeding) merges into an existing week instead of duplicating it.
"""

import uuid
from datetime import timedelta

import pytest
from sqlmodel import Session, SQLModel, create_engine, select

from app.models import Game, Group, SlateGame, Week
from app.services.auto_slate import _week_window, create_standard_season_weeks, get_or_create_week
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
    test suite runs."""
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


class TestCreateStandardSeasonWeeksNeverAddsGames:
    """
    Weeks are calendar structure, not a byproduct of odds data — a
    freshly-created group should immediately have all its standard weeks
    even with zero games in the odds pool. But the containers must stay
    EMPTY: the admin picks which games go into each week's slate, nothing
    is auto-selected.
    """

    def test_default_group_gets_regular_season_and_playoffs_but_not_preseason(self, mem_session: Session):
        group = _make_group(mem_session)  # include_preseason=False, include_playoffs=True
        weeks = create_standard_season_weeks(group, mem_session)
        numbers = sorted(w.week_number for w in weeks)
        assert numbers == list(range(1, 19)) + list(range(19, 23))
        assert all(n >= 1 for n in numbers)  # no preseason (negative) numbers

    def test_preseason_enabled_adds_four_distinct_weeks(self, mem_session: Session):
        group = _make_group(mem_session, include_preseason=True)
        weeks = create_standard_season_weeks(group, mem_session)
        preseason = sorted((w for w in weeks if w.week_number < 0), key=lambda w: w.week_number)
        assert [w.week_number for w in preseason] == [-4, -3, -2, -1]
        assert [w.label for w in preseason] == [
            "Preseason Week 1", "Preseason Week 2", "Preseason Week 3", "Preseason Week 4",
        ]
        # Each is a standard-width window (no explicit ends_on needed) —
        # chronologically increasing and non-overlapping.
        for w in preseason:
            assert w.ends_on is None
        assert [w.starts_on for w in preseason] == sorted(w.starts_on for w in preseason)

    def test_preseason_week_1_starts_5_weeks_out_for_the_hall_of_fame_game(self, mem_session: Session):
        # The real Hall of Fame Game kicks off ~5 weeks before the season
        # opener — a full week earlier than the rest of the league's first
        # preseason slate (4 weeks out). Verified against actual 2026 Odds
        # API data: HOF Game kicked off exactly 5 weeks (35 days) before
        # the Sept 10 opener.
        group = _make_group(mem_session, include_preseason=True)
        weeks = create_standard_season_weeks(group, mem_session)
        week1 = next(w for w in weeks if w.week_number == -4)
        season_start = nfl_season_start(group.season_year)
        assert week1.starts_on == season_start - timedelta(weeks=5)

    def test_preseason_week_1_does_not_swallow_week_2s_real_games(self, mem_session: Session):
        # Regression: Week 1 used to be widened all the way to the day
        # before Week 2 started (to catch the early HOF outlier), which
        # meant the ENTIRE next real preseason week's games — 4 weeks out,
        # a totally normal, non-outlier batch — also fell inside Week 1's
        # window instead of Week 2's. Confirmed against real Odds API data:
        # a batch of 16 games kicked off exactly 4 weeks before the opener
        # (the earliest of them lands exactly on the Week1/Week2 boundary
        # day, which — same as every other standard week's boundary — is
        # intentionally inclusive on both sides, letting the admin decide;
        # what matters is Week 1's window doesn't reach PAST that boundary).
        group = _make_group(mem_session, include_preseason=True)
        weeks = create_standard_season_weeks(group, mem_session)
        week1 = next(w for w in weeks if w.week_number == -4)
        week2 = next(w for w in weeks if w.week_number == -3)
        season_start = nfl_season_start(group.season_year)
        real_week_2_game_date = season_start - timedelta(weeks=4)
        week1_fallback_end = week1.starts_on + timedelta(days=7)
        assert real_week_2_game_date == week1_fallback_end
        assert real_week_2_game_date == week2.starts_on

    def test_preseason_week_4_ends_a_week_before_the_season_opens(self, mem_session: Session):
        # Real NFL preseason ends about 10-11 days before the opener, not
        # the week immediately before it — there's a genuine gap with no
        # preseason games in it. Week 4 (2 weeks out) + the standard 7-day
        # fallback lands exactly 1 week before the opener, matching that.
        group = _make_group(mem_session, include_preseason=True)
        weeks = create_standard_season_weeks(group, mem_session)
        week4 = next(w for w in weeks if w.week_number == -1)
        season_start = nfl_season_start(group.season_year)
        assert week4.starts_on + timedelta(days=7) == season_start - timedelta(days=7)

    def test_no_games_attached_to_any_created_week(self, mem_session: Session):
        group = _make_group(mem_session, include_preseason=True)
        weeks = create_standard_season_weeks(group, mem_session)
        week_ids = [w.id for w in weeks]
        linked = mem_session.exec(select(SlateGame).where(SlateGame.week_id.in_(week_ids))).all()  # type: ignore[attr-defined]
        assert linked == []

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


class TestGetOrCreateWeekMergesInsteadOfDuplicating:
    """get_or_create_week() is only used by dev.py's mock-data seeding now
    (production never auto-adds games) — still needs to be race/re-run safe."""

    def test_second_batch_for_same_week_joins_existing_row_not_a_duplicate(self, mem_session: Session):
        group = _make_group(mem_session)
        season_start = nfl_season_start(group.season_year)
        thu = thursday_of(season_start + timedelta(days=30))

        game1 = _game_at(weekly_slot_kickoff(thu, 0, 2), home="Team A", away="Team B")
        mem_session.add(game1)
        mem_session.flush()
        week = get_or_create_week(group, 5, "Week 5", [game1], mem_session)
        first_week_id = week.id

        # A second game arrives later (simulating a subsequent dev seed call)
        # that maps to the SAME NFL week.
        game2 = _game_at(weekly_slot_kickoff(thu, 1, 2), home="Team C", away="Team D")
        mem_session.add(game2)
        mem_session.flush()
        week_again = get_or_create_week(group, 5, "Week 5", [game2], mem_session)
        assert week_again.id == first_week_id  # merged, not duplicated

        all_weeks = mem_session.exec(select(Week).where(Week.group_id == group.id)).all()
        assert len(all_weeks) == 1

        linked_game_ids = {
            sg.game_id for sg in mem_session.exec(
                select(SlateGame).where(SlateGame.week_id == first_week_id)
            ).all()
        }
        assert linked_game_ids == {game1.id, game2.id}
