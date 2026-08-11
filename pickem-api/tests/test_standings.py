"""
Integration tests for GET /groups/{group_id}/standings — in particular that
members show up immediately at 0-0 on join/creation, not only after their
first graded pick (see groups.py::_create_standing_row).
"""

from fastapi.testclient import TestClient

from tests.conftest import auth_headers, register_user


def _create_group(client: TestClient, headers: dict) -> dict:
    resp = client.post("/groups", headers=headers, json={
        "name": "Standings Group", "sport": "americanfootball_nfl",
        "mode": "season", "season_year": 2026,
        "blind_picks": False, "superdogs_enabled": True, "superdogs_per_user": 3,
    })
    assert resp.status_code == 201, resp.text
    return resp.json()


def test_admin_shows_on_standings_immediately_at_zero(client: TestClient):
    headers = auth_headers(client, "admin@example.com")
    group = _create_group(client, headers)

    resp = client.get(f"/groups/{group['id']}/standings", headers=headers)
    assert resp.status_code == 200
    standings = resp.json()
    assert len(standings) == 1
    assert standings[0]["wins"] == 0
    assert standings[0]["losses"] == 0
    assert standings[0]["record"] == "0-0"


def test_member_shows_on_standings_immediately_after_joining(client: TestClient):
    admin_headers = auth_headers(client, "admin@example.com")
    group = _create_group(client, admin_headers)

    member_data = register_user(client, "member@example.com")
    member_headers = {"Authorization": f"Bearer {member_data['access_token']}"}
    join_resp = client.post("/groups/join", headers=member_headers, json={"join_code": group["join_code"]})
    assert join_resp.status_code == 200

    resp = client.get(f"/groups/{group['id']}/standings", headers=admin_headers)
    standings = resp.json()
    assert len(standings) == 2
    member_standing = next(s for s in standings if s["display_name"] == "member")
    assert member_standing["wins"] == 0
    assert member_standing["losses"] == 0


def test_rejoining_does_not_duplicate_standing_row(client: TestClient):
    admin_headers = auth_headers(client, "admin@example.com")
    group = _create_group(client, admin_headers)

    member_data = register_user(client, "member@example.com")
    member_headers = {"Authorization": f"Bearer {member_data['access_token']}"}
    client.post("/groups/join", headers=member_headers, json={"join_code": group["join_code"]})
    rejoin_resp = client.post("/groups/join", headers=member_headers, json={"join_code": group["join_code"]})
    assert rejoin_resp.status_code == 200

    standings = client.get(f"/groups/{group['id']}/standings", headers=admin_headers).json()
    assert len(standings) == 2  # admin + member, not 3
