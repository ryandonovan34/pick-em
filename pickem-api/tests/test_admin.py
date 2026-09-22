"""
Tests for POST /admin/results/fetch — the external-trigger endpoint that
replaced the in-process 30-min APScheduler results-fetch job (see
app/services/scheduler.py::fetch_and_process_results and
.github/workflows/results-fetch.yml).
"""

from fastapi.testclient import TestClient

from app.config import settings
import app.routers.admin as admin_router


def test_missing_key_returns_401(client: TestClient, monkeypatch):
    monkeypatch.setattr(settings, "ADMIN_TRIGGER_KEY", "correct-key")
    resp = client.post("/admin/results/fetch")
    assert resp.status_code == 401


def test_wrong_key_returns_401(client: TestClient, monkeypatch):
    monkeypatch.setattr(settings, "ADMIN_TRIGGER_KEY", "correct-key")
    resp = client.post("/admin/results/fetch", headers={"X-Admin-Key": "wrong-key"})
    assert resp.status_code == 401


def test_unset_admin_key_fails_closed_even_with_matching_empty_header(client: TestClient, monkeypatch):
    monkeypatch.setattr(settings, "ADMIN_TRIGGER_KEY", "")
    resp = client.post("/admin/results/fetch", headers={"X-Admin-Key": ""})
    assert resp.status_code == 401


def test_correct_key_triggers_fetch_and_returns_count(client: TestClient, monkeypatch):
    monkeypatch.setattr(settings, "ADMIN_TRIGGER_KEY", "correct-key")
    monkeypatch.setattr(admin_router, "fetch_and_process_results", lambda: 3)

    resp = client.post("/admin/results/fetch", headers={"X-Admin-Key": "correct-key"})

    assert resp.status_code == 200
    assert resp.json() == {"games_processed": 3}
