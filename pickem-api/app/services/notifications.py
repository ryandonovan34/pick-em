"""
Push notification sender (FCM HTTP v1 API).

Phase 2: all functions log to stdout instead of sending real notifications.
Phase 4: replace the stub implementations with real FCM calls.

FCM HTTP v1 requires a Google service account OAuth2 token (not the legacy server key).
The token expires every hour and must be refreshed via Google's token endpoint.
"""

import logging
import uuid

logger = logging.getLogger(__name__)


def send_pick_reminder(fcm_token: str, team_names: str, minutes_until_kickoff: int) -> None:
    """Alert a user they haven't picked a game that kicks off soon."""
    logger.info(
        "[FCM stub] Pick reminder → token=%s game=%s in %d min",
        fcm_token[:8],
        team_names,
        minutes_until_kickoff,
    )


def send_slate_reminder_to_admin(fcm_token: str, group_name: str) -> None:
    """Remind the admin to finalise their pick slate 3 hours before first kickoff."""
    logger.info("[FCM stub] Slate reminder → admin token=%s group=%s", fcm_token[:8], group_name)


def send_results_notification(fcm_tokens: list[str], group_name: str) -> None:
    """Alert all group members that results have been posted for a slate."""
    logger.info(
        "[FCM stub] Results posted → %d members notified, group=%s",
        len(fcm_tokens),
        group_name,
    )


def send_silent_cache_invalidation(
    fcm_tokens: list[str],
    event_type: str,
    group_id: uuid.UUID,
    week_id: uuid.UUID | None = None,
) -> None:
    """
    Send a silent (non-alerting) FCM data message so iOS devices discard their
    SwiftData cache and re-fetch immediately.

    event_type is one of:
        'slate_finalized' — admin has finalised the week's game slate
        'results_posted'  — results have been processed for a slate
    """
    payload = {"type": event_type, "group_id": str(group_id)}
    if week_id:
        payload["week_id"] = str(week_id)

    logger.info(
        "[FCM stub] Silent push → %d tokens, payload=%s",
        len(fcm_tokens),
        payload,
    )
