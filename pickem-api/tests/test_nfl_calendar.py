"""
Unit tests for NFL season-calendar mapping — the single source of truth used
by auto-population, manual week creation, and dev/mock seeding to agree on
"what NFL week is this date."
"""

from datetime import date, datetime, timedelta, timezone

from app.services.nfl_calendar import (
    label_for_week_number,
    monday_of,
    nfl_season_start,
    nfl_week_number_and_label,
    thursday_of,
    weekly_slot_kickoff,
)


class TestNflWeekNumberAndLabel:
    def test_day_before_season_start_is_preseason(self):
        start = nfl_season_start(2025)
        assert nfl_week_number_and_label(start - timedelta(days=1), 2025) == (0, "Preseason")

    def test_season_start_itself_is_week_1(self):
        start = nfl_season_start(2025)
        assert nfl_week_number_and_label(start, 2025) == (1, "Week 1")

    def test_week_2_starts_seven_days_later(self):
        start = nfl_season_start(2025)
        assert nfl_week_number_and_label(start + timedelta(days=7), 2025) == (2, "Week 2")

    def test_week_18_is_last_regular_season_week(self):
        start = nfl_season_start(2025)
        assert nfl_week_number_and_label(start + timedelta(days=17 * 7), 2025) == (18, "Week 18")

    def test_week_19_is_wild_card(self):
        start = nfl_season_start(2025)
        assert nfl_week_number_and_label(start + timedelta(days=18 * 7), 2025) == (19, "Wild Card")

    def test_week_22_is_super_bowl(self):
        start = nfl_season_start(2025)
        assert nfl_week_number_and_label(start + timedelta(days=21 * 7), 2025) == (22, "Super Bowl")

    def test_beyond_week_22_falls_back_to_generic_week_label(self):
        start = nfl_season_start(2025)
        week_num, label = nfl_week_number_and_label(start + timedelta(days=22 * 7), 2025)
        assert week_num == 23
        assert label == "Week 23"

    def test_season_year_missing_from_table_falls_back_to_first_september_thursday(self):
        start = nfl_season_start(2030)
        assert start.month == 9
        assert start.weekday() == 3  # Thursday


class TestMondayOf:
    def test_thursday_snaps_back_to_that_weeks_monday(self):
        # 2025-09-04 is a Thursday.
        assert monday_of(date(2025, 9, 4)) == date(2025, 9, 1)

    def test_monday_is_unchanged(self):
        assert monday_of(date(2025, 9, 1)) == date(2025, 9, 1)


class TestThursdayAnchorVsMondaySnap:
    """
    Documents the exact bug found during review: NFL weeks are Thursday-
    anchored, but calendar weeks are Monday-anchored. Deriving week_number
    from a *Monday-snapped* date instead of the raw kickoff/starts_on date
    can misclassify dates near the season boundary.
    """

    def test_raw_season_opener_date_classifies_as_week_1(self):
        start = nfl_season_start(2025)  # Thursday 2025-09-04
        assert nfl_week_number_and_label(start, 2025) == (1, "Week 1")

    def test_monday_snapped_opener_date_would_wrongly_classify_as_preseason(self):
        """
        This is exactly why games.py::create_week computes week_number from
        the RAW starts_on before calling monday_of() on it for storage —
        never the other way around.
        """
        start = nfl_season_start(2025)
        snapped = monday_of(start)
        assert snapped < start  # snapping moved it backward across the boundary
        week_num, label = nfl_week_number_and_label(snapped, 2025)
        assert (week_num, label) == (0, "Preseason")


class TestThursdayOf:
    def test_thursday_itself_is_unchanged(self):
        # 2025-10-02 is a Thursday.
        assert thursday_of(date(2025, 10, 2)) == date(2025, 10, 2)

    def test_sunday_resolves_to_that_weeks_thursday(self):
        assert thursday_of(date(2025, 10, 5)) == date(2025, 10, 2)

    def test_following_wednesday_still_resolves_to_same_thursday(self):
        # Thu Oct2 - Wed Oct8 is one NFL week (Thu/Sun/Mon games, then off days).
        assert thursday_of(date(2025, 10, 8)) == date(2025, 10, 2)

    def test_next_thursday_resolves_to_itself_not_previous_week(self):
        assert thursday_of(date(2025, 10, 9)) == date(2025, 10, 9)


class TestWeeklySlotKickoff:
    """2025-10-02 is a Thursday in EDT (UTC-4); 2025-11-20 is a Thursday in
    EST (UTC-5, DST ended Nov 2, 2025) — covers both halves of the season."""

    def test_thursday_night_football_edt(self):
        kickoff = weekly_slot_kickoff(date(2025, 10, 2), 0, 4)
        assert kickoff == datetime(2025, 10, 3, 0, 15, tzinfo=timezone.utc)

    def test_thursday_night_football_est(self):
        kickoff = weekly_slot_kickoff(date(2025, 11, 20), 0, 4)
        assert kickoff == datetime(2025, 11, 21, 1, 15, tzinfo=timezone.utc)

    def test_sunday_early_window(self):
        kickoff = weekly_slot_kickoff(date(2025, 10, 2), 1, 4)
        assert kickoff == datetime(2025, 10, 5, 17, 0, tzinfo=timezone.utc)  # 1:00 PM EDT

    def test_sunday_late_window_is_second_to_last_slot(self):
        kickoff = weekly_slot_kickoff(date(2025, 10, 2), 2, 4)
        assert kickoff == datetime(2025, 10, 5, 20, 25, tzinfo=timezone.utc)  # 4:25 PM EDT

    def test_last_slot_alternates_mnf_and_snf_by_week_parity(self):
        mnf = weekly_slot_kickoff(date(2025, 10, 2), 3, 4, week_number=2)
        assert mnf == datetime(2025, 10, 7, 0, 15, tzinfo=timezone.utc)  # Mon 8:15 PM EDT

        snf = weekly_slot_kickoff(date(2025, 10, 2), 3, 4, week_number=3)
        assert snf == datetime(2025, 10, 6, 0, 20, tzinfo=timezone.utc)  # Sun 8:20 PM EDT

    def test_middle_slots_all_land_in_sunday_early_window_for_larger_counts(self):
        for i in range(1, 4):
            kickoff = weekly_slot_kickoff(date(2025, 10, 2), i, 6)
            assert kickoff == datetime(2025, 10, 5, 17, 0, tzinfo=timezone.utc)


class TestLabelForWeekNumber:
    def test_preseason(self):
        assert label_for_week_number(0) == "Preseason"

    def test_regular_season(self):
        assert label_for_week_number(9) == "Week 9"

    def test_playoffs(self):
        assert label_for_week_number(19) == "Wild Card"
        assert label_for_week_number(22) == "Super Bowl"

    def test_fallback(self):
        assert label_for_week_number(30) == "Week 30"
