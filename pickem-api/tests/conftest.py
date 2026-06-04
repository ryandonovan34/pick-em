"""
Shared test fixtures.

All tests use SQLite so they run without a Postgres instance.
The critical step is patching app.database.engine with the SQLite engine
BEFORE the app is imported or TestClient triggers the lifespan — otherwise
the lifespan calls create_all() against localhost:5432 which isn't running.
"""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import event
from sqlmodel import Session, SQLModel, create_engine

# ── Patch the engine before importing the app ─────────────────────────────────
# The app's lifespan calls create_all(engine) where engine comes from app.database.
# We swap that engine with a SQLite one so no Postgres connection is needed.
import app.database as _db_module

_test_engine = create_engine(
    "sqlite:///./test.db",
    connect_args={"check_same_thread": False},
)


@event.listens_for(_test_engine, "connect")
def _enable_fks(dbapi_conn, _record):
    """SQLite doesn't enforce FK constraints by default."""
    dbapi_conn.execute("PRAGMA foreign_keys=ON")


# Module-level patch — applies to the lifespan and to get_session.
_db_module.engine = _test_engine

# Now it's safe to import the app.
from app.database import get_session  # noqa: E402
from app.main import app              # noqa: E402


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture(name="session", scope="function")
def session_fixture():
    """Create a fresh schema in SQLite and yield a session. Drop everything after."""
    SQLModel.metadata.create_all(_test_engine)
    with Session(_test_engine) as session:
        yield session
    SQLModel.metadata.drop_all(_test_engine)


@pytest.fixture(name="client")
def client_fixture(session: Session):
    """
    TestClient with the DB dependency wired to the test session.
    The lifespan now also uses _test_engine (patched above) so it won't
    attempt a Postgres connection.
    """
    app.dependency_overrides[get_session] = lambda: session
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()


# ── Shared helpers ────────────────────────────────────────────────────────────

def register_user(
    client: TestClient,
    email: str = "test@example.com",
    password: str = "password123",
) -> dict:
    """Register a user and return the full auth response dict."""
    resp = client.post("/auth/register", json={
        "email": email,
        "display_name": email.split("@")[0],
        "password": password,
    })
    assert resp.status_code == 201, resp.text
    return resp.json()


def auth_headers(
    client: TestClient,
    email: str = "test@example.com",
    password: str = "password123",
) -> dict:
    """Register and return a Bearer auth header dict."""
    data = register_user(client, email, password)
    return {"Authorization": f"Bearer {data['access_token']}"}
