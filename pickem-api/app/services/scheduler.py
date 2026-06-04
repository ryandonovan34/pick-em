"""
APScheduler job management.

Phase 2: the scheduler is initialised but no live Odds API jobs run.
         Jobs for pick reminders and slate notifications are registered here
         but only fire if actually scheduled via the routers.
Phase 3: add the odds refresh cron job.
Phase 4: wire up FCM token lookup for real notification delivery.

APScheduler stores jobs in memory by default. For production consider
switching to the SQLAlchemy job store so jobs survive server restarts.
"""

import logging
import uuid
from datetime import datetime, timedelta

from apscheduler.schedulers.background import BackgroundScheduler

from app.services import notifications

logger = logging.getLogger(__name__)

# The single shared scheduler instance.
scheduler = BackgroundScheduler(timezone="UTC")


def start() -> None:
    if not scheduler.running:
        scheduler.start()
        logger.info("Scheduler started.")


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

def _send_pick_reminders(fcm_tokens: list[str], team_names: str, minutes: int) -> None:
    for token in fcm_tokens:
        notifications.send_pick_reminder(token, team_names, minutes)
