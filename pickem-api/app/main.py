"""
FastAPI application entry point.

Registers all routers and manages application lifecycle (startup/shutdown).
"""

from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI
from sqlmodel import SQLModel

from app.config import settings
from app.database import engine
from app.routers import auth, dev, games, groups, picks, standings
from app.services import scheduler as sched

# Import models so SQLModel.metadata knows about all tables.
# This must happen before create_all() is called.
import app.models  # noqa: F401


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """
    Code before `yield` runs at startup; code after runs at shutdown.

    In development: create all tables automatically so you can start the server
    without running Alembic first.

    In production: tables must be managed exclusively via Alembic migrations.
    create_all() is intentionally skipped to prevent accidental schema changes.
    """
    if settings.is_development:
        SQLModel.metadata.create_all(engine)

    sched.start()

    yield

    sched.shutdown()


app = FastAPI(
    title="PickEm API",
    description="Pick'em challenge app for the NFL.",
    version="0.1.0",
    # Disable the auto-generated docs in production to reduce attack surface.
    docs_url="/docs" if settings.is_development else None,
    redoc_url="/redoc" if settings.is_development else None,
    lifespan=lifespan,
)

app.include_router(auth.router,               prefix="/auth",   tags=["Auth"])
app.include_router(groups.router,             prefix="/groups", tags=["Groups"])
app.include_router(games.router,                                tags=["Games"])
app.include_router(picks.router,              prefix="/picks",  tags=["Picks"])
app.include_router(picks.group_picks_router,                    tags=["Picks"])
app.include_router(standings.router,                            tags=["Standings"])
app.include_router(dev.router,                prefix="/dev",    tags=["Dev"])


@app.get("/health", tags=["Health"])
def health_check() -> dict:
    """Simple health check used by Fly.io and load balancers."""
    return {"status": "ok", "env": settings.APP_ENV}


# Team ID + bundle ID from the iOS project (project.pbxproj:
# DEVELOPMENT_TEAM / PRODUCT_BUNDLE_IDENTIFIER) — update both here and
# there together if either ever changes.
_APPLE_APP_ID = "WVZ32CQH5A.com.ryandonovan.pickem"


@app.get("/.well-known/apple-app-site-association", tags=["Apple"])
@app.get("/apple-app-site-association", tags=["Apple"])
def apple_app_site_association() -> dict:
    """
    Associates this domain with the iOS app for webcredentials (AutoFill-
    saved logins tied to a verified domain instead of just the app's
    bundle ID, and surfaced properly in Settings > Passwords). Served at
    both the modern (.well-known) and legacy (root) paths since iOS tries
    both. Must stay plain JSON with no redirects — Apple's servers fetch
    it directly, not through the app.
    """
    return {"webcredentials": {"apps": [_APPLE_APP_ID]}}
