"""
Integration tests for group creation — in particular that a freshly-created
group immediately shows its full season of weeks via the real API, not just
at the service-layer (see tests/test_auto_slate.py for the unit-level
coverage of create_standard_season_weeks itself).
"""

from fastapi.testclient import TestClient

from tests.conftest import auth_headers


def _create_group(client: TestClient, headers: dict, **overrides) -> dict:
    body = {
        "name": "Test Group",
        "sport": "americanfootball_nfl",
        "mode": "season",
        "season_year": 2026,
        "blind_picks": False,
        "superdogs_enabled": False,
        "superdogs_per_user": 3,
    }
    body.update(overrides)
    resp = client.post("/groups", headers=headers, json=body)
    assert resp.status_code == 201, resp.text
    return resp.json()


class TestNewGroupHasWeeksImmediately:
    def test_weeks_exist_right_after_creation_with_zero_games(self, client: TestClient):
        headers = auth_headers(client)
        group = _create_group(client, headers)

        resp = client.get(f"/groups/{group['id']}/weeks", headers=headers)
        assert resp.status_code == 200
        weeks = resp.json()

        numbers = sorted(w["week_number"] for w in weeks)
        assert numbers == list(range(1, 19)) + list(range(19, 23))  # regular season + playoffs, no preseason

        week1 = next(w for w in weeks if w["week_number"] == 1)
        assert week1["label"] == "Week 1"

    def test_preseason_included_when_group_opts_in(self, client: TestClient):
        headers = auth_headers(client)
        group = _create_group(client, headers, include_preseason=True)

        resp = client.get(f"/groups/{group['id']}/weeks", headers=headers)
        weeks = resp.json()

        preseason = next(w for w in weeks if w["week_number"] == 0)
        assert preseason["label"] == "Preseason"

    def test_playoffs_excluded_when_group_opts_out(self, client: TestClient):
        headers = auth_headers(client)
        group = _create_group(client, headers, include_playoffs=False)

        resp = client.get(f"/groups/{group['id']}/weeks", headers=headers)
        weeks = resp.json()

        assert sorted(w["week_number"] for w in weeks) == list(range(1, 19))
