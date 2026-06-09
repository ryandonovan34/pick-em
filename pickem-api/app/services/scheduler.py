"""
APScheduler job management.

Phase 3: odds refresh runs every 6 hours (+ once on startup) if ODDS_API_KEY is set.
Phase 4: wire up FCM token lookup for real notification delivery.

APScheduler stores jobs in memory by default. For production consider
switching to the SQLAlchemy job store so jobs survive server restarts.
"""

import logging
import uuid
from datetime import datetime, timedelta, timezone

from apscheduler.schedulers.background import BackgroundScheduler

from app.services import notifications

logger = logging.getLogger(__name__)

_SUPPORTED_SPORTS = ["americanfootball_nfl", "soccer_fifa_world_cup"]

# The single shared scheduler instance.
scheduler = BackgroundScheduler(timezone="UTC")


def start() -> None:
    if not scheduler.running:
        scheduler.start()
        logger.info("Scheduler started.")
        _schedule_odds_refresh()


def shutdown() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Scheduler shut down.")


# ── Job factories ────────────────────────────────────────────────────────────

def schedule_pick_reminders(
    game_id: uuid.UUID,
    group_id: uuid.UUID,
    kickoff_at: datetime,
    member_fcm_tokens: list[str],
    team_names: str,
) -> None:
    """
    Schedule pick-reminder notifications at T-120, T-60, T-30, and T-15 minutes
    before a game kicks off. Each job only fires if the user hasn't picked yet
    (that check happens inside the job itself — Phase 4).
    """
    intervals = [120, 60, 30, 15]
    for minutes in intervals:
        fire_at = kickoff_at - timedelta(minutes=minutes)
        job_id = f"pick_reminder_{game_id}_{minutes}m"
        scheduler.add_job(
            _send_pick_reminders,
            "date",
            run_date=fire_at,
            id=job_id,
            replace_existing=True,
            args=[member_fcm_tokens, team_names, minutes],
        )


def cancel_pick_reminders(game_id: uuid.UUID) -> None:
    """Cancel all scheduled pick reminders for a game (e.g. when it's removed from a slate)."""
    for minutes in [120, 60, 30, 15]:
        job_id = f"pick_reminder_{game_id}_{minutes}m"
        if scheduler.get_job(job_id):
            scheduler.remove_job(job_id)


def schedule_odds_refresh_for_slate(
    week_id: uuid.UUID,
    sport: str,
    first_kickoff_at: datetime,
) -> None:
    """
    Schedule a one-time odds refresh 3 hours before the first kickoff of a slate.
    Called whenever games are added or removed so the fire time stays current.
    If T-3hr has already passed (kickoff is imminent), fires immediately.
    No-op if ODDS_API_KEY is not configured.
    """
    from app.config import settings
    if not settings.ODDS_API_KEY:
        return
    fire_at = first_kickoff_at - timedelta(hours=3)
    # Don't schedule in the past — fire immediately instead.
    now = datetime.now(timezone.utc)
    if fire_at < now:
        fire_at = now
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
    """Cancel the T-3hr odds refresh for a slate (e.g. all games removed)."""
    job_id = f"odds_refresh_slate_{week_id}"
    if scheduler.get_job(job_id):
        scheduler.remove_job(job_id)


def schedule_slate_admin_reminder(
    week_id: uuid.UUID,
    first_kickoff_at: datetime,
    admin_fcm_token: str,
    group_name: str,
) -> None:
    """Remind the admin to finalise the slate 3 hours before first kickoff."""
    fire_at = first_kickoff_at - timedelta(hours=3)
    scheduler.add_job(
        notifications.send_slate_reminder_to_admin,
        "date",
        run_date=fire_at,
        id=f"slate_reminder_{week_id}",
        replace_existing=True,
        args=[admin_fcm_token, group_name],
    )


# ── Internal job functions ───────────────────────────────────────────────────

def _schedule_odds_refresh() -> None:
    from app.config import settings
    if not settings.ODDS_API_KEY:
        logger.info("ODDS_API_KEY not set — odds refresh job not scheduled.")
        return
    # Fire once immediately on startup to populate the pool.
    scheduler.add_job(_refresh_odds_job, "date", id="odds_refresh_startup", replace_existing=True)
    # Then every 24 hours for line movement updates.
    scheduler.add_job(
        _refresh_odds_job,
        "interval",
        hours=24,
        id="odds_refresh_interval",
        replace_existing=True,
    )
    logger.info("Odds refresh job scheduled (startup + every 24h).")


def _refresh_odds_job() -> None:
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


def _send_pick_reminders(fcm_tokens: list[str], team_names: str, minutes: int) -> None:
    for token in fcm_tokens:
        notifications.send_pick_reminder(token, team_names, minutes)
