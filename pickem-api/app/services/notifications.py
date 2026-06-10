"""
Push notification sender (FCM HTTP v1 API).

FCM HTTP v1 uses a short-lived OAuth2 access token (1 hour TTL) derived from
a Google service account. The credentials object from google-auth tracks
expiry and refreshes automatically when needed.

If FCM_SERVICE_ACCOUNT_JSON or FCM_PROJECT_ID is not configured (e.g. local
dev), all send functions are silent no-ops — nothing is logged at INFO level
so dev logs stay clean.
"""

import json
import logging
import uuid
from typing import Any

import httpx
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import service_account

from app.config import settings

logger = logging.getLogger(__name__)

_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_credentials: service_account.Credentials | None = None


def _access_token() -> str | None:
    """Return a valid FCM Bearer token, refreshing if expired. Returns None if not configured."""
    global _credentials
    if not settings.FCM_SERVICE_ACCOUNT_JSON or not settings.FCM_PROJECT_ID:
        return None
    if _credentials is None:
        try:
            info = json.loads(settings.FCM_SERVICE_ACCOUNT_JSON)
            _credentials = service_account.Credentials.from_service_account_info(
                info, scopes=[_FCM_SCOPE]
            )
        except Exception:
            logger.exception("Failed to load FCM service account credentials")
            return None
    if not _credentials.valid:
        _credentials.refresh(GoogleAuthRequest())
    return _credentials.token


def _send(token: str, message: dict[str, Any]) -> None:
    """POST a single FCM message. Silent no-op when FCM is not configured."""
    bearer = _access_token()
    if bearer is None:
        return
    url = f"https://fcm.googleapis.com/v1/projects/{settings.FCM_PROJECT_ID}/messages:send"
    with httpx.Client() as client:
        response = client.post(
            url,
            json={"message": {"token": token, **message}},
            headers={"Authorization": f"Bearer {bearer}"},
            timeout=10.0,
        )
    if not response.is_success:
        logger.warning("FCM send failed: status=%d body=%s", response.status_code, response.text[:300])


def send_pick_reminder(fcm_token: str, team_names: str, minutes_until_kickoff: int) -> None:
    _send(fcm_token, {
        "notification": {
            "title": "Pick reminder",
            "body": f"{team_names} kicks off in {minutes_until_kickoff} minutes — get your pick in!",
        },
    })


def send_slate_reminder_to_admin(fcm_token: str, group_name: str) -> None:
    _send(fcm_token, {
        "notification": {
            "title": f"{group_name} — slate reminder",
            "body": "First kickoff is 3 hours away. Finalise your pick slate.",
        },
    })


def send_results_notification(fcm_tokens: list[str], group_name: str) -> None:
    for token in fcm_tokens:
        _send(token, {
            "notification": {
                "title": f"{group_name} — results are in",
                "body": "Check the leaderboard to see how you did.",
            },
        })


def send_silent_cache_invalidation(
    fcm_tokens: list[str],
    event_type: str,
    group_id: uuid.UUID,
    week_id: uuid.UUID | None = None,
) -> None:
    """
    Send a silent background push so iOS discards its SwiftData cache and re-fetches.
    All data dict values must be strings (FCM requirement).
    """
    data: dict[str, str] = {"type": event_type, "group_id": str(group_id)}
    if week_id:
        data["week_id"] = str(week_id)
    for token in fcm_tokens:
        _send(token, {
            "data": data,
            "apns": {
                "headers": {"apns-push-type": "background", "apns-priority": "5"},
                "payload": {"aps": {"content-available": 1}},
            },
            "android": {"priority": "normal"},
        })
