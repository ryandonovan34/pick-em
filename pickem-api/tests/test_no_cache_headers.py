"""
Regression test for the pick-history staleness bug: a client (notably iOS's
on-disk URLCache, which survives app relaunches) could cache a legitimately
empty response made before a user's picks were graded, and keep serving it
back stale indefinitely since the API sent no cache-control guidance at all.
Every response must say not to cache it.
"""

from fastapi.testclient import TestClient


def test_every_response_sets_no_store(client: TestClient):
    resp = client.get("/health")
    assert resp.headers.get("cache-control") == "no-store"


def test_error_response_also_sets_no_store(client: TestClient):
    # Unauthenticated request to a protected route — whatever status this
    # comes back as, it must still carry the header.
    resp = client.get("/groups/00000000-0000-0000-0000-000000000000")
    assert resp.status_code != 200
    assert resp.headers.get("cache-control") == "no-store"
