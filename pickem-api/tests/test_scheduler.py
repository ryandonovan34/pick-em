"""
Unit tests for scheduler._send_pick_reminders — everyone in the group gets a
kickoff reminder, not just members who haven't picked yet, since lines can
move between when someone picks and kickoff and grading always uses
whatever spread is on the Game row at kickoff.
"""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlmodel import Session, select

from app.config import settings
from app.models import Game, Group, GroupMember, Pick, User
from app.services import notifications, scheduler


def _make_user(session: Session, **overrides) -> User:
    fields = {
        "email": f"{uuid.uuid4()}@test.com", "hashed_pw": "x",
        "display_name": "Test", "fcm_token": "token-" + str(uuid.uuid4())[:8],
    }
    fields.update(overrides)
    user = User(**fields)
    session.add(user)
    session.flush()
    return user


def _make_group(session: Session, admin_id: uuid.UUID) -> Group:
    group = Group(
        name="Test", admin_id=admin_id, join_code=str(uuid.uuid4())[:6].upper(),
        sport="americanfootball_nfl", mode="season", season_year=2099,
    )
    session.add(group)
    session.flush()
    return group


def _make_game(session: Session, kickoff_at: datetime | None = None) -> Game:
    game = Game(
        odds_api_id=str(uuid.uuid4()), sport="americanfootball_nfl",
        home_team="Home", away_team="Away", spread=-3.5, favorite_team="Home",
        kickoff_at=kickoff_at or (datetime.now(timezone.utc) + timedelta(minutes=15)),
    )
    session.add(game)
    session.flush()
    return game


def test_already_picked_member_gets_line_check_not_skipped(session: Session, monkeypatch):
    picked_user = _make_user(session)
    unpicked_user = _make_user(session)
    group = _make_group(session, admin_id=picked_user.id)
    session.add(GroupMember(group_id=group.id, user_id=picked_user.id))
    session.add(GroupMember(group_id=group.id, user_id=unpicked_user.id))
    game = _make_game(session)
    session.add(Pick(user_id=picked_user.id, game_id=game.id, group_id=group.id, picked_team="Home"))
    session.commit()

    sent_pick_reminders = []
    sent_line_checks = []
    monkeypatch.setattr(notifications, "send_pick_digest_reminder", lambda token, *a: sent_pick_reminders.append(token))
    monkeypatch.setattr(notifications, "send_line_check_digest_reminder", lambda token, *a: sent_line_checks.append(token))

    scheduler._send_pick_reminders([game.id], group.id, 15)

    assert sent_pick_reminders == [unpicked_user.fcm_token]
    assert sent_line_checks == [picked_user.fcm_token]


def test_member_without_fcm_token_is_skipped(session: Session, monkeypatch):
    admin = _make_user(session)
    no_token_user = _make_user(session, fcm_token=None)
    group = _make_group(session, admin_id=admin.id)
    session.add(GroupMember(group_id=group.id, user_id=no_token_user.id))
    game = _make_game(session)
    session.commit()

    sent = []
    monkeypatch.setattr(notifications, "send_pick_digest_reminder", lambda token, *a: sent.append(token))
    monkeypatch.setattr(notifications, "send_line_check_digest_reminder", lambda token, *a: sent.append(token))

    scheduler._send_pick_reminders([game.id], group.id, 15)

    assert sent == []


@pytest.fixture(autouse=True)
def _odds_api_key(monkeypatch):
    # schedule_odds_refresh_for_game is a no-op without a key configured.
    monkeypatch.setattr(settings, "ODDS_API_KEY", "test-key")


class TestPerGameOddsRefresh:
    """
    Regression: a slate spanning Thursday through Monday used to schedule a
    single pre-kickoff odds refresh anchored to the slate's earliest game
    only, leaving later games' spreads relying solely on the 24h interval
    job (up to a day stale by their own kickoff). Each game now gets its
    own independent refresh job.
    """

    def test_schedules_a_job_keyed_by_game_not_week(self):
        game_id = uuid.uuid4()
        kickoff = datetime.now(timezone.utc) + timedelta(hours=10)
        scheduler.schedule_odds_refresh_for_game(game_id, "americanfootball_nfl", kickoff)

        job = scheduler.scheduler.get_job(f"odds_refresh_game_{game_id}")
        assert job is not None
        assert job.trigger.run_date == kickoff - timedelta(hours=3)

    def test_two_games_in_the_same_slate_get_independent_jobs(self):
        thursday_game_id = uuid.uuid4()
        monday_game_id = uuid.uuid4()
        thursday_kickoff = datetime.now(timezone.utc) + timedelta(hours=10)
        monday_kickoff = thursday_kickoff + timedelta(days=4)

        scheduler.schedule_odds_refresh_for_game(thursday_game_id, "americanfootball_nfl", thursday_kickoff)
        scheduler.schedule_odds_refresh_for_game(monday_game_id, "americanfootball_nfl", monday_kickoff)

        thursday_job = scheduler.scheduler.get_job(f"odds_refresh_game_{thursday_game_id}")
        monday_job = scheduler.scheduler.get_job(f"odds_refresh_game_{monday_game_id}")
        assert thursday_job.trigger.run_date == thursday_kickoff - timedelta(hours=3)
        assert monday_job.trigger.run_date == monday_kickoff - timedelta(hours=3)

    def test_cancelling_one_game_leaves_the_others_scheduled(self):
        game_a = uuid.uuid4()
        game_b = uuid.uuid4()
        kickoff = datetime.now(timezone.utc) + timedelta(hours=10)
        scheduler.schedule_odds_refresh_for_game(game_a, "americanfootball_nfl", kickoff)
        scheduler.schedule_odds_refresh_for_game(game_b, "americanfootball_nfl", kickoff)

        scheduler.cancel_odds_refresh_for_game(game_a)

        assert scheduler.scheduler.get_job(f"odds_refresh_game_{game_a}") is None
        assert scheduler.scheduler.get_job(f"odds_refresh_game_{game_b}") is not None

        scheduler.cancel_odds_refresh_for_game(game_b)  # cleanup


class TestPickReminderClustering:
    """
    Regression: a slate with several games kicking off close together (e.g.
    a Saturday preseason batch) used to schedule one full set of T-120/60/
    30/15 reminders per game — a member could get 20+ near-simultaneous
    notifications for a slate of just 5 games. Games kicking off within
    _CLUSTER_WINDOW of each other now share a single digest reminder per
    offset instead.
    """

    def test_games_within_the_cluster_window_share_one_job_per_offset(self, session: Session):
        admin = _make_user(session)
        group = _make_group(session, admin_id=admin.id)
        session.commit()
        week_id = uuid.uuid4()
        base = datetime.now(timezone.utc) + timedelta(hours=10)
        close_games = [_make_game(session, kickoff_at=base + timedelta(minutes=m)) for m in (0, 20, 45)]
        session.commit()

        scheduler.schedule_pick_reminders_for_week(week_id, group.id, close_games)

        jobs = [j for j in scheduler.scheduler.get_jobs() if j.id.startswith(f"pick_digest_{week_id}_")]
        assert len(jobs) == 4  # one per T-120/60/30/15 offset, not one per game
        assert set(jobs[0].kwargs["game_ids"]) == {g.id for g in close_games}

    def test_games_outside_the_cluster_window_get_separate_jobs(self, session: Session):
        admin = _make_user(session)
        group = _make_group(session, admin_id=admin.id)
        session.commit()
        week_id = uuid.uuid4()
        base = datetime.now(timezone.utc) + timedelta(hours=10)
        thursday_game = _make_game(session, kickoff_at=base)
        monday_game = _make_game(session, kickoff_at=base + timedelta(days=4))
        session.commit()

        scheduler.schedule_pick_reminders_for_week(week_id, group.id, [thursday_game, monday_game])

        jobs = [j for j in scheduler.scheduler.get_jobs() if j.id.startswith(f"pick_digest_{week_id}_")]
        assert len(jobs) == 8  # 4 offsets x 2 independent clusters
        game_id_sets = {frozenset(j.kwargs["game_ids"]) for j in jobs}
        assert game_id_sets == {frozenset([thursday_game.id]), frozenset([monday_game.id])}

    def test_rescheduling_a_week_cancels_its_old_jobs_first(self, session: Session):
        admin = _make_user(session)
        group = _make_group(session, admin_id=admin.id)
        session.commit()
        week_id = uuid.uuid4()
        base = datetime.now(timezone.utc) + timedelta(hours=10)
        game_a = _make_game(session, kickoff_at=base)
        session.commit()

        scheduler.schedule_pick_reminders_for_week(week_id, group.id, [game_a])
        game_b = _make_game(session, kickoff_at=base + timedelta(days=4))
        session.commit()
        scheduler.schedule_pick_reminders_for_week(week_id, group.id, [game_a, game_b])

        jobs = [j for j in scheduler.scheduler.get_jobs() if j.id.startswith(f"pick_digest_{week_id}_")]
        assert len(jobs) == 8  # stale single-game jobs replaced, not left dangling

    def test_removing_all_games_cancels_the_weeks_jobs(self, session: Session):
        admin = _make_user(session)
        group = _make_group(session, admin_id=admin.id)
        session.commit()
        week_id = uuid.uuid4()
        game = _make_game(session)
        session.commit()

        scheduler.schedule_pick_reminders_for_week(week_id, group.id, [game])
        scheduler.schedule_pick_reminders_for_week(week_id, group.id, [])

        jobs = [j for j in scheduler.scheduler.get_jobs() if j.id.startswith(f"pick_digest_{week_id}_")]
        assert jobs == []


class TestRelevantApiSportKey:
    """
    Regression: _fetch_and_process_results used to always query both the
    regular-season+playoffs and separate preseason scores endpoints on
    every poll, regardless of whether any preseason game was actually
    pending — wasting half of every poll's Odds API credit budget for the
    ~5 months/year with no pending preseason games (i.e. almost the whole
    season). _relevant_api_sport_key classifies a single game's kickoff so
    only the endpoint it's actually under gets queried.
    """

    def test_preseason_kickoff_maps_to_preseason_key(self):
        # 2026 season opens 2026-09-10 per NFL_SEASON_STARTS.
        kickoff = datetime(2026, 8, 6, 20, 15, tzinfo=timezone.utc)
        assert scheduler._relevant_api_sport_key(kickoff) == "americanfootball_nfl_preseason"

    def test_regular_season_kickoff_maps_to_regular_key(self):
        kickoff = datetime(2026, 9, 13, 17, 0, tzinfo=timezone.utc)
        assert scheduler._relevant_api_sport_key(kickoff) == "americanfootball_nfl"

    def test_january_playoff_kickoff_maps_to_regular_key(self):
        # Playoffs for the 2026 season happen in Jan 2027 — must still
        # resolve against the 2026 season's start, not a nonexistent 2027 one.
        kickoff = datetime(2027, 1, 18, 20, 0, tzinfo=timezone.utc)
        assert scheduler._relevant_api_sport_key(kickoff) == "americanfootball_nfl"

    def test_late_night_utc_kickoff_near_season_boundary_uses_et_calendar_date(self):
        # 2026-09-10 02:00 UTC is technically "Sept 10" by raw UTC .date(),
        # which would wrongly read as on/after the Sept 10 season opener —
        # but it's still 2026-09-09 22:00 ET (the night before), so this
        # must classify as preseason. Proves local_date (ET) is used, not
        # a naive raw-UTC date comparison.
        kickoff = datetime(2026, 9, 10, 2, 0, tzinfo=timezone.utc)
        assert scheduler._relevant_api_sport_key(kickoff) == "americanfootball_nfl_preseason"
