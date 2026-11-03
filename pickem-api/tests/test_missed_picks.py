"""
Integration tests for PUT /groups/{group_id}/picks/{pick_id}/missed — the group
admin setting another member's missed pick after the game has been graded.
"""

from fastapi.testclient import TestClient

from tests.conftest import auth_headers, register_user


def _seed(client: TestClient) -> dict:
    """A group with an admin and member, and one game the member forfeited."""
    admin = auth_headers(client, "admin@example.com")
    group = client.post("/groups", headers=admin, json={
        "name": "Missed Group", "sport": "americanfootball_nfl",
        "mode": "season", "season_year": 2025,
        "blind_picks": False, "superdogs_enabled": True, "superdogs_per_user": 3,
    }).json()

    member_data = register_user(client, "member@example.com")
    member = {"Authorization": f"Bearer {member_data['access_token']}"}
    client.post("/groups/join", headers=member, json={"join_code": group["join_code"]})
    member_id = client.get("/auth/me", headers=member).json()["id"]

    pool = client.post("/dev/mock-games", json={
        "sport": "americanfootball_nfl", "week_label": "W1", "game_count": 1,
    }).json()[0]
    week = client.post(f"/groups/{group['id']}/weeks", headers=admin, json={
        "label": "W1", "starts_on": pool["kickoff_at"][:10],
    }).json()
    game = client.post(
        f"/groups/{group['id']}/weeks/{week['id']}/games", headers=admin,
        json={"odds_api_id": pool["odds_api_id"]},
    ).json()

    # The favorite covers comfortably, so picking the favorite wins and the underdog loses.
    margin = int(abs(game["spread"])) + 5
    favorite_is_home = game["favorite_team"] == game["home_team"]
    resp = client.post("/dev/mock-results", json={
        "game_id": game["id"],
        "home_score": 17 + margin if favorite_is_home else 17,
        "away_score": 17 if favorite_is_home else 17 + margin,
    })
    assert resp.status_code == 200, resp.text

    return {"admin": admin, "member": member, "member_id": member_id, "group": group, "game": game}


def _forfeit_id(client: TestClient, ctx: dict, user_id: str) -> str:
    history = client.get(
        f"/groups/{ctx['group']['id']}/members/{user_id}/picks/history", headers=ctx["admin"],
    ).json()
    assert len(history) == 1 and history[0]["is_forfeit"] is True
    return history[0]["pick_id"]


def _url(ctx: dict, pick_id: str) -> str:
    return f"/groups/{ctx['group']['id']}/picks/{pick_id}/missed"


def _standing(client: TestClient, ctx: dict, user_id: str) -> dict:
    rows = client.get(f"/groups/{ctx['group']['id']}/standings", headers=ctx["admin"]).json()
    return next(r for r in rows if r["user_id"] == user_id)


def test_winning_team_turns_forfeit_into_win_and_updates_standing(client: TestClient):
    ctx = _seed(client)
    pick_id = _forfeit_id(client, ctx, ctx["member_id"])
    before = _standing(client, ctx, ctx["member_id"])
    assert (before["wins"], before["losses"]) == (0, 1)

    resp = client.put(_url(ctx, pick_id), headers=ctx["admin"], json={"picked_team": ctx["game"]["favorite_team"]})

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["picked_team"] == ctx["game"]["favorite_team"]
    assert body["result"] == "win"
    assert body["is_forfeit"] is False
    assert body["is_superdog"] is False
    after = _standing(client, ctx, ctx["member_id"])
    assert (after["wins"], after["losses"]) == (1, 0)


def test_losing_team_clears_forfeit_but_stays_a_loss(client: TestClient):
    ctx = _seed(client)
    pick_id = _forfeit_id(client, ctx, ctx["member_id"])
    game = ctx["game"]
    underdog = game["away_team"] if game["favorite_team"] == game["home_team"] else game["home_team"]

    resp = client.put(_url(ctx, pick_id), headers=ctx["admin"], json={"picked_team": underdog})

    assert resp.status_code == 200, resp.text
    assert resp.json()["result"] == "loss"
    assert resp.json()["is_forfeit"] is False
    after = _standing(client, ctx, ctx["member_id"])
    assert (after["wins"], after["losses"]) == (0, 1)


def test_non_admin_cannot_set_missed_pick(client: TestClient):
    ctx = _seed(client)
    pick_id = _forfeit_id(client, ctx, ctx["member_id"])

    resp = client.put(_url(ctx, pick_id), headers=ctx["member"], json={"picked_team": ctx["game"]["favorite_team"]})

    assert resp.status_code == 403
    assert _standing(client, ctx, ctx["member_id"])["losses"] == 1


def test_non_member_cannot_set_missed_pick(client: TestClient):
    ctx = _seed(client)
    pick_id = _forfeit_id(client, ctx, ctx["member_id"])
    outsider = auth_headers(client, "outsider@example.com")

    resp = client.put(_url(ctx, pick_id), headers=outsider, json={"picked_team": ctx["game"]["favorite_team"]})

    assert resp.status_code == 403


def test_admin_cannot_set_their_own_missed_pick(client: TestClient):
    ctx = _seed(client)
    admin_id = client.get("/auth/me", headers=ctx["admin"]).json()["id"]
    pick_id = _forfeit_id(client, ctx, admin_id)

    resp = client.put(_url(ctx, pick_id), headers=ctx["admin"], json={"picked_team": ctx["game"]["favorite_team"]})

    assert resp.status_code == 403
    assert _standing(client, ctx, admin_id)["losses"] == 1


def test_pick_can_only_be_set_once(client: TestClient):
    ctx = _seed(client)
    pick_id = _forfeit_id(client, ctx, ctx["member_id"])
    game = ctx["game"]
    first = client.put(_url(ctx, pick_id), headers=ctx["admin"], json={"picked_team": game["favorite_team"]})
    assert first.status_code == 200, first.text

    resp = client.put(_url(ctx, pick_id), headers=ctx["admin"], json={"picked_team": game["home_team"]})

    assert resp.status_code == 409


def test_team_must_be_in_the_game(client: TestClient):
    ctx = _seed(client)
    pick_id = _forfeit_id(client, ctx, ctx["member_id"])

    resp = client.put(_url(ctx, pick_id), headers=ctx["admin"], json={"picked_team": "Not A Team"})

    assert resp.status_code == 422
    assert _standing(client, ctx, ctx["member_id"])["losses"] == 1


def test_pick_from_another_group_is_not_found(client: TestClient):
    ctx = _seed(client)
    pick_id = _forfeit_id(client, ctx, ctx["member_id"])
    other_admin = auth_headers(client, "other-admin@example.com")
    other_group = client.post("/groups", headers=other_admin, json={
        "name": "Other", "sport": "americanfootball_nfl", "mode": "season", "season_year": 2025,
    }).json()

    resp = client.put(
        f"/groups/{other_group['id']}/picks/{pick_id}/missed",
        headers=other_admin, json={"picked_team": ctx["game"]["favorite_team"]},
    )

    assert resp.status_code == 404
