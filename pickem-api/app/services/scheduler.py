"""
APScheduler job management.

Jobs that need FCM tokens look them up from the database at fire time,
not at schedule time — tokens change when users reinstall the app.

APScheduler stores jobs in memory. For production, consider switching to
the SQLAlchemy job store so jobs survive server restarts.
"""

import logging
import uuid
from datetime import datetime, timedelta, timezone

from apscheduler.schedulers.background import BackgroundScheduler

from app.services import notifications

logger = logging.getLogger(__name__)

_SUPPORTED_SPORTS = ["americanfootball_nfl"]

scheduler = BackgroundScheduler(timezone="UTC")


def start() -> None:
    if not scheduler.running:
        scheduler.start()
        logger.info("Scheduler started.")
        _schedule_odds_refresh()
        _schedule_results_fetch()


def shutdown() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Scheduler shut down.")


# ── Public job factories ──────────────────────────────────────────────────────

def schedule_pick_reminders(
    game_id: uuid.UUID,
    group_id: uuid.UUID,
    kickoff_at: datetime,
    team_names: str,
) -> None:
    """
    Schedule pick-reminder notifications at T-120, T-60, T-30, and T-15 minutes.
    FCM tokens and already-picked status are resolved at fire time.
    """
    for minutes in [120, 60, 30, 15]:
        scheduler.add_job(
            _send_pick_reminders,
            "date",
            run_date=kickoff_at - timedelta(minutes=minutes),
            id=f"pick_reminder_{game_id}_{minutes}m",
            replace_existing=True,
            kwargs={"game_id": game_id, "group_id": group_id, "team_names": team_names, "minutes": minutes},
        )


def cancel_pick_reminders(game_id: uuid.UUID) -> None:
    """Cancel all scheduled pick reminders for a game (e.g. when removed from a slate)."""
    for minutes in [120, 60, 30, 15]:
        job_id = f"pick_reminder_{game_id}_{minutes}m"
        if scheduler.get_job(job_id):
            scheduler.remove_job(job_id)


def schedule_slate_admin_reminder(
    week_id: uuid.UUID,
    group_id: uuid.UUID,
    first_kickoff_at: datetime,
) -> None:
    """Remind the admin to finalise the slate 3 hours before first kickoff."""
    scheduler.add_job(
        _send_slate_admin_reminder,
        "date",
        run_date=first_kickoff_at - timedelta(hours=3),
        id=f"slate_reminder_{week_id}",
        replace_existing=True,
        kwargs={"group_id": group_id},
    )


def cancel_slate_admin_reminder(week_id: uuid.UUID) -> None:
    job_id = f"slate_reminder_{week_id}"
    if scheduler.get_job(job_id):
        scheduler.remove_job(job_id)


def schedule_odds_refresh_for_slate(
    week_id: uuid.UUID,
    sport: str,
    first_kickoff_at: datetime,
) -> None:
    """
    Schedule a one-time odds refresh 3 hours before the first kickoff of a slate.
    Replaces any existing job for this week so fire time stays current as games change.
    No-op if ODDS_API_KEY is not configured.
    """
    from app.config import settings
    if not settings.ODDS_API_KEY:
        return
    fire_at = max(first_kickoff_at - timedelta(hours=3), datetime.now(timezone.utc))
    scheduler.add_job(
        _refresh_sport_job,
        "date",
        run_date=fire_at,
        id=f"odds_refresh_slate_{week_id}",
        replace_existing=True,
        kwargs={"sport": sport},
    )
    logger.info("Odds refresh for slate %s scheduled at %s", week_id, fire_at)


def cancel_odds_refresh_for_slate(week_id: uuid.UUID) -> None:
    job_id = f"odds_refresh_slate_{week_id}"
    if scheduler.get_job(job_id):
        scheduler.remove_job(job_id)


# ── Internal setup ────────────────────────────────────────────────────────────

def _schedule_odds_refresh() -> None:
    from app.config import settings
    if not settings.ODDS_API_KEY:
        logger.info("ODDS_API_KEY not set — odds refresh job not scheduled.")
        return
    scheduler.add_job(_refresh_odds_job, "date", id="odds_refresh_startup", replace_existing=True)
    scheduler.add_job(
        _refresh_odds_job,
        "interval",
        hours=24,
        id="odds_refresh_interval",
        replace_existing=True,
    )
    logger.info("Odds refresh scheduled (startup + every 24h).")


def _schedule_results_fetch() -> None:
    from app.config import settings
    if not settings.ODDS_API_KEY:
        return
    scheduler.add_job(
        _fetch_and_process_results,
        "interval",
        minutes=15,
        id="results_fetch",
        replace_existing=True,
    )
    logger.info("Results fetch scheduled (every 15 min).")


# ── Internal job functions ────────────────────────────────────────────────────

def _refresh_odds_job() -> None:
    """Refill the odds pool. Games are NEVER auto-added to any group's
    slate — the admin picks games explicitly (games.py::add_game_to_slate),
    which is also what triggers the slate-ready/game-added notification."""
    from app.services.odds import ingest_odds

    for sport in _SUPPORTED_SPORTS:
        try:
            ingest_odds(sport)
        except Exception:
            logger.exception("Odds refresh failed for sport=%s", sport)


def _refresh_sport_job(sport: str) -> None:
    from app.services.odds import ingest_odds
    try:
        ingest_odds(sport)
    except Exception:
        logger.exception("Odds refresh failed for sport=%s", sport)


def _send_pick_reminders(
    game_id: uuid.UUID,
    group_id: uuid.UUID,
    team_names: str,
    minutes: int,
) -> None:
    """Look up group members who haven't picked yet and send them a reminder."""
    from app.database import engine
    from app.models import GroupMember, Pick, User
    from sqlmodel import Session, select

    with Session(engine) as session:
        members = session.exec(
            select(User)
            .join(GroupMember, GroupMember.user_id == User.id)  # type: ignore[arg-type]
            .where(GroupMember.group_id == group_id, User.fcm_token.isnot(None))  # type: ignore[union-attr]
        ).all()

        for member in members:
            already_picked = session.exec(
                select(Pick).where(
                    Pick.user_id == member.id,
                    Pick.game_id == game_id,
                    Pick.group_id == group_id,
                )
            ).first()
            if already_picked is None and member.fcm_token:
                notifications.send_pick_reminder(member.fcm_token, team_names, minutes)


def _send_slate_admin_reminder(group_id: uuid.UUID) -> None:
    from app.database import engine
    from app.models import Group, User
    from sqlmodel import Session

    with Session(engine) as session:
        group = session.get(Group, group_id)
        if group is None:
            return
        admin = session.get(User, group.admin_id)
        if admin and admin.fcm_token:
            notifications.send_slate_reminder_to_admin(admin.fcm_token, group.name)


def _fetch_and_process_results() -> None:
    """
    Poll the Odds API scores endpoint for completed games, process results,
    and send FCM notifications to affected groups.
    """
    from app.database import engine
    from app.models import Game, Group, GroupMember, User, Week
    from app.services.odds import fetch_scores, odds_api_sport_keys
    from app.services.results import process_game_result
    from app.utils import utc_now
    from sqlmodel import Session, select

    now = utc_now()

    with Session(engine) as session:
        # Only process games that are on at least one slate (have a slate_games row).
        from app.models import SlateGame
        slated_game_ids = select(SlateGame.game_id).distinct()
        pending = session.exec(
            select(Game).where(
                Game.result_posted == False,  # noqa: E712
                Game.id.in_(slated_game_ids),  # type: ignore[attr-defined]
                Game.kickoff_at <= now,
            )
        ).all()

        if not pending:
            return

        # Fetch scores for each real Odds API key mapped to a pending game's
        # (internal) sport — e.g. 'americanfootball_nfl' expands to both the
        # regular-season+playoffs and the separate preseason scores endpoint,
        # since Game.sport is normalized to the internal key regardless of
        # which one a game's odds actually came from (see odds.py::ingest_odds).
        score_map: dict[str, tuple[int, int]] = {}
        api_sport_keys = {key for g in pending for key in odds_api_sport_keys(g.sport)}
        for api_sport_key in api_sport_keys:
            try:
                for s in fetch_scores(api_sport_key):
                    if not s.get("completed") or not s.get("scores"):
                        continue
                    home = next((x for x in s["scores"] if x["name"] == s["home_team"]), None)
                    away = next((x for x in s["scores"] if x["name"] == s["away_team"]), None)
                    if home and away:
                        score_map[s["id"]] = (int(home["score"]), int(away["score"]))
            except Exception:
                logger.exception("Failed to fetch scores for api_sport=%s", api_sport_key)

        for game in pending:
            if not game.odds_api_id or game.odds_api_id not in score_map:
                continue
            home_score, away_score = score_map[game.odds_api_id]
            try:
                process_game_result(game.id, home_score, away_score, session)
            except ValueError:
                continue
            except Exception:
                logger.exception("Failed to process result for game %s", game.id)
                continue

            # Notify every group that has this game on a slate.
            try:
                from app.models import SlateGame
                for sg in session.exec(select(SlateGame).where(SlateGame.game_id == game.id)).all():
                    week = session.get(Week, sg.week_id)
                    if week is None:
                        continue
                    group = session.get(Group, week.group_id)
                    if group is None:
                        continue

                    members_with_tokens = session.exec(
                        select(User)
                        .join(GroupMember, GroupMember.user_id == User.id)  # type: ignore[arg-type]
                        .where(GroupMember.group_id == group.id, User.fcm_token.isnot(None))  # type: ignore[union-attr]
                    ).all()
                    tokens = [m.fcm_token for m in members_with_tokens if m.fcm_token]
                    if not tokens:
                        continue

                    notifications.send_silent_cache_invalidation(
                        tokens, "results_posted", group_id=group.id, week_id=sg.week_id
                    )

                    # Alert only when the full slate for this group's week is done.
                    slate_game_ids = [r.game_id for r in session.exec(
                        select(SlateGame).where(SlateGame.week_id == sg.week_id)
                    ).all()]
                    slate_games = session.exec(
                        select(Game).where(Game.id.in_(slate_game_ids))  # type: ignore[attr-defined]
                    ).all()
                    if all(g.result_posted for g in slate_games):
                        notifications.send_results_notification(tokens, group.name)

            except Exception:
                logger.exception("Failed to send result notifications for game %s", game.id)
