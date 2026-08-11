"""
Tests for the Apple App Site Association endpoint (webcredentials —
ties AutoFill-saved logins to this domain instead of just the app's
bundle ID).
"""

from fastapi.testclient import TestClient


def test_well_known_path_returns_webcredentials(client: TestClient):
    resp = client.get("/.well-known/apple-app-site-association")
    assert resp.status_code == 200
    body = resp.json()
    assert body["webcredentials"]["apps"] == ["WVZ32CQH5A.com.ryandonovan.pickem"]


def test_legacy_root_path_returns_the_same_content(client: TestClient):
    well_known = client.get("/.well-known/apple-app-site-association").json()
    root = client.get("/apple-app-site-association").json()
    assert well_known == root


def test_no_auth_required(client: TestClient):
    # Apple's servers fetch this directly, with no credentials.
    resp = client.get("/.well-known/apple-app-site-association")
    assert resp.status_code == 200
