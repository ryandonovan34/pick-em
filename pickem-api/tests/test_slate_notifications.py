"""
Integration tests for slate-change notifications — members (not the acting
admin) get notified whenever the admin adds or removes a game from a slate.
"""

from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.services import notifications
from tests.conftest import auth_headers, register_user


def _setup_group_with_member(client: TestClient) -> tuple[dict, dict, dict]:
    """Admin creates a group; a second user joins and registers an FCM token.
    Returns (admin_headers, member_headers, group)."""
    admin_headers = auth_headers(client, "admin@example.com")
    group_resp = client.post("/groups", headers=admin_headers, json={
        "name": "Notify Group", "sport": "americanfootball_nfl",
        "mode": "season", "season_year": 2025,
        "blind_picks": False, "superdogs_enabled": False, "superdogs_per_user": 3,
    })
    group = group_resp.json()

    member_data = register_user(client, "member@example.com")
    member_headers = {"Authorization": f"Bearer {member_data['access_token']}"}
    client.post("/groups/join", headers=member_headers, json={"join_code": group["join_code"]})
    fcm_resp = client.put("/auth/fcm-token", headers=member_headers, json={"fcm_token": "member-token"})
    assert fcm_resp.status_code == 204

    return admin_headers, member_headers, group


def _create_week_and_seed_game(client: TestClient, admin_headers: dict, group: dict, label: str = "W1") -> tuple[dict, dict]:
    # Seed the games first, then build the week around their ACTUAL kickoff
    # date — independently guessing "now + 48h" for both can land a game
    # just outside the week's window depending on today's weekday.
    seed = client.post("/dev/mock-games", json={"sport": "americanfootball_nfl", "week_label": label, "game_count": 2})
    games_pool = seed.json()
    game_date = datetime.fromisoformat(games_pool[0]["kickoff_at"].replace("Z", "+00:00")).date().isoformat()
    week_resp = client.post(
        f"/groups/{group['id']}/weeks", headers=admin_headers,
        json={"label": label, "starts_on": game_date},
    )
    week = week_resp.json()
    return week, games_pool


def test_adding_first_game_sends_slate_ready_to_member_not_admin(client: TestClient, monkeypatch):
    admin_headers, member_headers, group = _setup_group_with_member(client)
    week, games_pool = _create_week_and_seed_game(client, admin_headers, group)

    calls = []
    monkeypatch.setattr(notifications, "send_slate_ready", lambda tokens, *a: calls.append(("slate_ready", tokens)))
    monkeypatch.setattr(notifications, "send_game_added", lambda tokens, *a: calls.append(("game_added", tokens)))

    resp = client.post(
        f"/groups/{group['id']}/weeks/{week['id']}/games", headers=admin_headers,
        json={"odds_api_id": games_pool[0]["odds_api_id"]},
    )
    assert resp.status_code == 201, resp.text

    assert calls == [("slate_ready", ["member-token"])]


def test_adding_second_game_sends_game_added(client: TestClient, monkeypatch):
    admin_headers, member_headers, group = _setup_group_with_member(client)
    week, games_pool = _create_week_and_seed_game(client, admin_headers, group)

    client.post(
        f"/groups/{group['id']}/weeks/{week['id']}/games", headers=admin_headers,
        json={"odds_api_id": games_pool[0]["odds_api_id"]},
    )

    calls = []
    monkeypatch.setattr(notifications, "send_slate_ready", lambda tokens, *a: calls.append(("slate_ready", tokens)))
    monkeypatch.setattr(notifications, "send_game_added", lambda tokens, *a: calls.append(("game_added", tokens)))

    resp = client.post(
        f"/groups/{group['id']}/weeks/{week['id']}/games", headers=admin_headers,
        json={"odds_api_id": games_pool[1]["odds_api_id"]},
    )
    assert resp.status_code == 201, resp.text

    assert calls == [("game_added", ["member-token"])]


def test_removing_a_game_sends_game_removed_to_member_not_admin(client: TestClient, monkeypatch):
    admin_headers, member_headers, group = _setup_group_with_member(client)
    week, games_pool = _create_week_and_seed_game(client, admin_headers, group)

    add_resp = client.post(
        f"/groups/{group['id']}/weeks/{week['id']}/games", headers=admin_headers,
        json={"odds_api_id": games_pool[0]["odds_api_id"]},
    )
    game = add_resp.json()

    calls = []
    monkeypatch.setattr(notifications, "send_game_removed", lambda tokens, *a: calls.append(("game_removed", tokens)))

    resp = client.delete(
        f"/groups/{group['id']}/weeks/{week['id']}/games/{game['id']}", headers=admin_headers,
    )
    assert resp.status_code == 204, resp.text

    assert calls == [("game_removed", ["member-token"])]
