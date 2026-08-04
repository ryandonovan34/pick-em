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
        # Regression: _week_to_read() used to always serialize the
        # server-side +7-day fallback into ends_on, even for a standard
        # week — which made Week.displayLabel show a raw date range for
        # EVERY week on iOS instead of "Week 1", "Week 2", etc. Only a
        # genuinely non-standard window should have ends_on set.
        assert week1["ends_on"] is None

    def test_preseason_included_when_group_opts_in(self, client: TestClient):
        headers = auth_headers(client)
        group = _create_group(client, headers, include_preseason=True)

        resp = client.get(f"/groups/{group['id']}/weeks", headers=headers)
        weeks = resp.json()

        preseason = sorted((w for w in weeks if w["week_number"] < 0), key=lambda w: w["week_number"])
        assert [w["week_number"] for w in preseason] == [-4, -3, -2, -1]
        assert [w["label"] for w in preseason] == [
            "Preseason Week 1", "Preseason Week 2", "Preseason Week 3", "Preseason Week 4",
        ]

    def test_no_games_in_any_week_right_after_creation(self, client: TestClient):
        headers = auth_headers(client)
        group = _create_group(client, headers, include_preseason=True)

        resp = client.get(f"/groups/{group['id']}/weeks", headers=headers)
        weeks = resp.json()
        assert all(w["first_kickoff_at"] is None and w["last_kickoff_at"] is None for w in weeks)

    def test_playoffs_excluded_when_group_opts_out(self, client: TestClient):
        headers = auth_headers(client)
        group = _create_group(client, headers, include_playoffs=False)

        resp = client.get(f"/groups/{group['id']}/weeks", headers=headers)
        weeks = resp.json()

        assert sorted(w["week_number"] for w in weeks) == list(range(1, 19))
