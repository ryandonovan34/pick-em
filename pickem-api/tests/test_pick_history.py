"""
Integration tests for GET /groups/{group_id}/members/{user_id}/picks/history —
a group member's full history of GRADED picks, for verifying their record.
"""

import uuid
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from tests.conftest import auth_headers, register_user


def _seed_group_with_two_members(client: TestClient) -> tuple[dict, dict, dict]:
    """Returns (admin_headers, member_headers, group)."""
    admin_headers = auth_headers(client, "admin@example.com")
    group_resp = client.post("/groups", headers=admin_headers, json={
        "name": "History Group", "sport": "americanfootball_nfl",
        "mode": "season", "season_year": 2025,
        "blind_picks": False, "superdogs_enabled": True, "superdogs_per_user": 3,
    })
    group = group_resp.json()

    member_data = register_user(client, "member@example.com")
    member_headers = {"Authorization": f"Bearer {member_data['access_token']}"}
    client.post("/groups/join", headers=member_headers, json={"join_code": group["join_code"]})

    return admin_headers, member_headers, group


def _add_graded_game(
    client: TestClient, admin_headers: dict, group: dict,
    week_label: str = "W1", spread: float = -7.5, template_offset: int = 0,
    days_out: int | None = None,
) -> dict:
    """
    Seed one game (kicking off soon — /dev/mock-games decides the exact
    time, self-correcting to stay in the future regardless of what day of
    the week "now" happens to be), then create a week around its ACTUAL
    kickoff date so the two are always consistent, and add it to the slate.
    Pass days_out to land distinct calls in distinct NFL weeks (e.g. for an
    ordering test) — otherwise two default-anchored calls made moments
    apart resolve to the same week and the second week creation 409s.
    """
    body: dict = {"sport": "americanfootball_nfl", "week_label": week_label, "game_count": 1, "template_offset": template_offset}
    if days_out is not None:
        body["base_kickoff_at"] = (datetime.now(timezone.utc) + timedelta(days=days_out)).isoformat()

    seed = client.post("/dev/mock-games", json=body)
    game_pool = seed.json()[0]
    kickoff = datetime.fromisoformat(game_pool["kickoff_at"].replace("Z", "+00:00"))

    week_resp = client.post(
        f"/groups/{group['id']}/weeks", headers=admin_headers,
        json={"label": week_label, "starts_on": kickoff.date().isoformat()},
    )
    week = week_resp.json()

    add_resp = client.post(
        f"/groups/{group['id']}/weeks/{week['id']}/games", headers=admin_headers,
        json={"odds_api_id": game_pool["odds_api_id"]},
    )
    assert add_resp.status_code == 201, add_resp.text
    return add_resp.json()


def _post_result(client: TestClient, game_id: str, home_score: int, away_score: int) -> None:
    resp = client.post("/dev/mock-results", json={
        "game_id": game_id, "home_score": home_score, "away_score": away_score,
    })
    assert resp.status_code == 200, resp.text


def test_graded_pick_appears_with_result_and_running_tally_fields(client: TestClient):
    admin_headers, member_headers, group = _seed_group_with_two_members(client)
    game = _add_graded_game(client, admin_headers, group)

    # Member picks the favorite and it covers.
    pick_resp = client.post("/picks", headers=member_headers, json={
        "game_id": game["id"], "group_id": group["id"],
        "picked_team": game["favorite_team"], "is_superdog": False,
    })
    assert pick_resp.status_code == 201, pick_resp.text

    margin = int(abs(game["spread"])) + 5
    if game["favorite_team"] == game["home_team"]:
        _post_result(client, game["id"], home_score=17 + margin, away_score=17)
    else:
        _post_result(client, game["id"], home_score=17, away_score=17 + margin)

    member_id = client.get("/auth/me", headers=member_headers).json()["id"]
    resp = client.get(f"/groups/{group['id']}/members/{member_id}/picks/history", headers=admin_headers)
    assert resp.status_code == 200, resp.text
    history = resp.json()
    assert len(history) == 1
    entry = history[0]
    assert entry["result"] == "win"
    assert entry["picked_team"] == game["favorite_team"]
    assert entry["is_superdog"] is False
    assert entry["week_label"] == "W1"
    assert entry["home_team"] == game["home_team"]
    assert entry["away_team"] == game["away_team"]


def test_pending_picks_are_excluded(client: TestClient):
    admin_headers, member_headers, group = _seed_group_with_two_members(client)
    game = _add_graded_game(client, admin_headers, group)

    client.post("/picks", headers=member_headers, json={
        "game_id": game["id"], "group_id": group["id"],
        "picked_team": game["favorite_team"], "is_superdog": False,
    })
    # No result posted — pick stays 'pending'.

    member_id = client.get("/auth/me", headers=member_headers).json()["id"]
    resp = client.get(f"/groups/{group['id']}/members/{member_id}/picks/history", headers=admin_headers)
    assert resp.status_code == 200
    assert resp.json() == []


def test_history_ordered_chronologically_by_kickoff(client: TestClient):
    admin_headers, member_headers, group = _seed_group_with_two_members(client)

    game1 = _add_graded_game(client, admin_headers, group, week_label="W1", template_offset=0, days_out=2)
    game2 = _add_graded_game(client, admin_headers, group, week_label="W2", template_offset=1, days_out=14)

    for game in (game1, game2):
        client.post("/picks", headers=member_headers, json={
            "game_id": game["id"], "group_id": group["id"],
            "picked_team": game["favorite_team"], "is_superdog": False,
        })
        margin = int(abs(game["spread"])) + 5
        if game["favorite_team"] == game["home_team"]:
            _post_result(client, game["id"], home_score=17 + margin, away_score=17)
        else:
            _post_result(client, game["id"], home_score=17, away_score=17 + margin)

    member_id = client.get("/auth/me", headers=member_headers).json()["id"]
    resp = client.get(f"/groups/{group['id']}/members/{member_id}/picks/history", headers=admin_headers)
    history = resp.json()
    assert len(history) == 2
    kickoffs = [h["kickoff_at"] for h in history]
    assert kickoffs == sorted(kickoffs)


def test_superdog_win_shows_superdog_win_result(client: TestClient):
    admin_headers, member_headers, group = _seed_group_with_two_members(client)
    game = _add_graded_game(client, admin_headers, group, spread=-7.5)

    underdog = game["away_team"] if game["favorite_team"] == game["home_team"] else game["home_team"]
    pick_resp = client.post("/picks", headers=member_headers, json={
        "game_id": game["id"], "group_id": group["id"],
        "picked_team": underdog, "is_superdog": True,
    })
    assert pick_resp.status_code == 201, pick_resp.text

    # Underdog wins outright.
    if underdog == game["home_team"]:
        _post_result(client, game["id"], home_score=24, away_score=10)
    else:
        _post_result(client, game["id"], home_score=10, away_score=24)

    member_id = client.get("/auth/me", headers=member_headers).json()["id"]
    resp = client.get(f"/groups/{group['id']}/members/{member_id}/picks/history", headers=admin_headers)
    history = resp.json()
    assert len(history) == 1
    assert history[0]["result"] == "superdog_win"
    assert history[0]["is_superdog"] is True


def test_any_member_can_view_another_members_history(client: TestClient):
    """Not admin-gated — mirrors standings' group-wide visibility."""
    admin_headers, member_headers, group = _seed_group_with_two_members(client)
    game = _add_graded_game(client, admin_headers, group)

    client.post("/picks", headers=admin_headers, json={
        "game_id": game["id"], "group_id": group["id"],
        "picked_team": game["favorite_team"], "is_superdog": False,
    })
    margin = int(abs(game["spread"])) + 5
    if game["favorite_team"] == game["home_team"]:
        _post_result(client, game["id"], home_score=17 + margin, away_score=17)
    else:
        _post_result(client, game["id"], home_score=17, away_score=17 + margin)

    admin_id = client.get("/auth/me", headers=admin_headers).json()["id"]
    # A regular (non-admin) member views the admin's history.
    resp = client.get(f"/groups/{group['id']}/members/{admin_id}/picks/history", headers=member_headers)
    assert resp.status_code == 200
    assert len(resp.json()) == 1


def test_404_when_target_user_not_a_group_member(client: TestClient):
    admin_headers, _member_headers, group = _seed_group_with_two_members(client)
    resp = client.get(f"/groups/{group['id']}/members/{uuid.uuid4()}/picks/history", headers=admin_headers)
    assert resp.status_code == 404


def test_403_when_caller_not_a_group_member(client: TestClient):
    admin_headers, _member_headers, group = _seed_group_with_two_members(client)
    outsider_headers = auth_headers(client, "outsider@example.com")
    admin_id = client.get("/auth/me", headers=admin_headers).json()["id"]
    resp = client.get(f"/groups/{group['id']}/members/{admin_id}/picks/history", headers=outsider_headers)
    assert resp.status_code == 403
