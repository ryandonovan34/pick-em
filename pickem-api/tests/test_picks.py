"""
Integration tests for pick submission, updating, and visibility rules.
"""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session

from app.models import Game, Group, GroupMember, Week
from tests.conftest import auth_headers, register_user


def _seed_group_and_game(
    client: TestClient,
    session: Session,
    spread: float = -7.5,
    kickoff_offset_hours: float = 48,
    blind_picks: bool = False,
    superdogs_enabled: bool = True,
) -> tuple[dict, dict, dict]:
    """
    Helper: register a user, create a group, seed a game in a week.
    Returns (auth_headers, group_data, game_data).
    """
    headers = auth_headers(client)

    group_resp = client.post("/groups", headers=headers, json={
        "name": "Test Group",
        "sport": "americanfootball_nfl",
        "mode": "season",
        "season_year": 2025,
        "blind_picks": blind_picks,
        "superdogs_enabled": superdogs_enabled,
        "superdogs_per_user": 2,
    })
    assert group_resp.status_code == 201
    group = group_resp.json()

    # starts_on must cover the mock game's kickoff (now + kickoff_offset_hours);
    # WeekCreate snaps any date to the Monday of its containing week.
    game_date = (datetime.now(timezone.utc) + timedelta(hours=kickoff_offset_hours)).date().isoformat()
    week_resp = client.post(
        f"/groups/{group['id']}/weeks", headers=headers,
        json={"label": "Week 1", "starts_on": game_date},
    )
    assert week_resp.status_code == 201
    week = week_resp.json()

    # Seed a game directly into the pool via dev endpoint.
    seed_resp = client.post("/dev/mock-games", json={
        "sport": "americanfootball_nfl",
        "week_label": "Week 1",
        "game_count": 1,
    })
    assert seed_resp.status_code == 201
    game_pool = seed_resp.json()[0]

    # Add to slate.
    add_resp = client.post(
        f"/groups/{group['id']}/weeks/{week['id']}/games",
        headers=headers,
        json={"odds_api_id": game_pool["odds_api_id"]},
    )
    assert add_resp.status_code == 201
    game = add_resp.json()

    return headers, group, game


class TestSubmitPick:
    def test_submit_pick_success(self, client: TestClient, session: Session):
        headers, group, game = _seed_group_and_game(client, session)
        resp = client.post("/picks", headers=headers, json={
            "game_id": game["id"],
            "group_id": group["id"],
            "picked_team": game["favorite_team"],
            "is_superdog": False,
        })
        assert resp.status_code == 201
        data = resp.json()
        assert data["picked_team"] == game["favorite_team"]
        assert data["result"] == "pending"

    def test_duplicate_pick_returns_409(self, client: TestClient, session: Session):
        headers, group, game = _seed_group_and_game(client, session)
        pick_body = {"game_id": game["id"], "group_id": group["id"], "picked_team": game["favorite_team"]}
        client.post("/picks", headers=headers, json=pick_body)
        resp = client.post("/picks", headers=headers, json=pick_body)
        assert resp.status_code == 409

    def test_pick_locked_game_returns_400(self, client: TestClient, session: Session):
        headers, group, game = _seed_group_and_game(client, session)
        # Manually set the game kickoff to the past.
        db_game = session.get(Game, uuid.UUID(game["id"]))
        db_game.kickoff_at = datetime.now(timezone.utc) - timedelta(hours=1)
        session.add(db_game)
        session.commit()

        resp = client.post("/picks", headers=headers, json={
            "game_id": game["id"],
            "group_id": group["id"],
            "picked_team": game["favorite_team"],
        })
        assert resp.status_code == 400

    def test_superdog_on_small_spread_returns_422(self, client: TestClient, session: Session):
        # The mock game has spread -7.5 which qualifies; but let's override to a small spread.
        headers, group, game = _seed_group_and_game(client, session)
        db_game = session.get(Game, uuid.UUID(game["id"]))
        db_game.spread = -3.5
        db_game.favorite_team = db_game.home_team
        session.add(db_game)
        session.commit()

        underdog = game["away_team"] if game["favorite_team"] == game["home_team"] else game["home_team"]
        resp = client.post("/picks", headers=headers, json={
            "game_id": game["id"],
            "group_id": group["id"],
            "picked_team": underdog,
            "is_superdog": True,
        })
        assert resp.status_code == 422
        assert "6.5" in resp.json()["detail"]

    def test_superdog_on_favorite_returns_422(self, client: TestClient, session: Session):
        headers, group, game = _seed_group_and_game(client, session)
        resp = client.post("/picks", headers=headers, json={
            "game_id": game["id"],
            "group_id": group["id"],
            "picked_team": game["favorite_team"],  # wrong — must be underdog
            "is_superdog": True,
        })
        assert resp.status_code == 422
        assert "underdog" in resp.json()["detail"].lower()


class TestPickVisibility:
    def test_blind_group_hides_others_picks_before_kickoff(self, client: TestClient, session: Session):
        # User A creates a blind group and picks.
        headers_a = auth_headers(client, "a@example.com")
        group_resp = client.post("/groups", headers=headers_a, json={
            "name": "Blind Group", "sport": "americanfootball_nfl",
            "mode": "season", "season_year": 2025,
            "blind_picks": True, "superdogs_enabled": False, "superdogs_per_user": 3,
        })
        group = group_resp.json()

        game_date = (datetime.now(timezone.utc) + timedelta(hours=48)).date().isoformat()
        week_resp = client.post(
            f"/groups/{group['id']}/weeks", headers=headers_a,
            json={"label": "W1", "starts_on": game_date},
        )
        week = week_resp.json()

        seed = client.post("/dev/mock-games", json={"sport": "americanfootball_nfl", "week_label": "W1", "game_count": 1})
        game_pool = seed.json()[0]
        add = client.post(f"/groups/{group['id']}/weeks/{week['id']}/games", headers=headers_a,
                          json={"odds_api_id": game_pool["odds_api_id"]})
        game = add.json()

        # User A submits a pick.
        client.post("/picks", headers=headers_a, json={
            "game_id": game["id"], "group_id": group["id"],
            "picked_team": game["favorite_team"], "is_superdog": False,
        })

        # User B joins the group and views picks — should NOT see User A's pick.
        data_b = register_user(client, "b@example.com")
        headers_b = {"Authorization": f"Bearer {data_b['access_token']}"}
        client.post("/groups/join", headers=headers_b, json={"join_code": group["join_code"]})

        resp = client.get(f"/groups/{group['id']}/weeks/{week['id']}/picks", headers=headers_b)
        assert resp.status_code == 200
        # User B has no picks and can't see User A's (blind, before kickoff).
        picks = resp.json()
        assert all(p["user_id"] == data_b["user"]["id"] for p in picks)

    def test_non_blind_group_shows_all_picks(self, client: TestClient, session: Session):
        headers_a = auth_headers(client, "a@example.com")
        group_resp = client.post("/groups", headers=headers_a, json={
            "name": "Open Group", "sport": "americanfootball_nfl",
            "mode": "season", "season_year": 2025,
            "blind_picks": False, "superdogs_enabled": False, "superdogs_per_user": 3,
        })
        group = group_resp.json()
        game_date = (datetime.now(timezone.utc) + timedelta(hours=48)).date().isoformat()
        week_resp = client.post(
            f"/groups/{group['id']}/weeks", headers=headers_a,
            json={"label": "W1", "starts_on": game_date},
        )
        week = week_resp.json()

        seed = client.post("/dev/mock-games", json={"sport": "americanfootball_nfl", "week_label": "W1", "game_count": 1})
        game_pool = seed.json()[0]
        add = client.post(f"/groups/{group['id']}/weeks/{week['id']}/games", headers=headers_a,
                          json={"odds_api_id": game_pool["odds_api_id"]})
        game = add.json()

        client.post("/picks", headers=headers_a, json={
            "game_id": game["id"], "group_id": group["id"],
            "picked_team": game["favorite_team"],
        })

        data_b = register_user(client, "b@example.com")
        headers_b = {"Authorization": f"Bearer {data_b['access_token']}"}
        client.post("/groups/join", headers=headers_b, json={"join_code": group["join_code"]})

        resp = client.get(f"/groups/{group['id']}/weeks/{week['id']}/picks", headers=headers_b)
        assert resp.status_code == 200
        assert len(resp.json()) == 1  # User A's pick is visible
