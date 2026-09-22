"""
Operational trigger endpoints for external schedulers.

The results-fetch job used to be an in-process APScheduler interval job, but
that only fires while the Python process is actually running — and the Fly.io
machine suspends between requests (see fly.toml's auto_stop_machines), so the
job silently stopped firing for most of the week instead of erroring loudly.

These endpoints let something outside the app (see
.github/workflows/results-fetch.yml) drive that work on a schedule instead.
Hitting the endpoint also wakes a suspended machine on demand
(auto_start_machines), so no change to fly.toml/hosting cost is needed.

There's no user to authenticate as here, so these are protected by a shared
secret (X-Admin-Key) rather than a user JWT.
"""

import logging

from fastapi import APIRouter, Depends, Header, HTTPException, status

from app.config import settings
from app.services.scheduler import fetch_and_process_results

router = APIRouter()
logger = logging.getLogger(__name__)


def _require_admin_key(x_admin_key: str | None = Header(default=None)) -> None:
    """Fails closed: an unset ADMIN_TRIGGER_KEY rejects every request."""
    if not settings.ADMIN_TRIGGER_KEY or x_admin_key != settings.ADMIN_TRIGGER_KEY:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or missing admin key.")


@router.post("/results/fetch")
def trigger_results_fetch(_: None = Depends(_require_admin_key)) -> dict:
    """Fetch scores for any pending game past kickoff and grade its picks."""
    processed = fetch_and_process_results()
    return {"games_processed": processed}
