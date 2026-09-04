"""
Integration tests for DELETE /groups/{group_id} (admin deletes group) and
POST /groups/{group_id}/leave (member leaves group).
"""

from fastapi.testclient import TestClient

from tests.conftest import auth_headers, register_user


def _seed_group_with_two_members(client: TestClient) -> tuple[dict, dict, dict]:
    """Returns (admin_headers, member_headers, group)."""
    admin_headers = auth_headers(client, "admin@example.com")
    group_resp = client.post("/groups", headers=admin_headers, json={
        "name": "Membership Group", "sport": "americanfootball_nfl",
        "mode": "season", "season_year": 2025,
        "blind_picks": False, "superdogs_enabled": True, "superdogs_per_user": 3,
    })
    group = group_resp.json()

    member_data = register_user(client, "member@example.com")
    member_headers = {"Authorization": f"Bearer {member_data['access_token']}"}
    client.post("/groups/join", headers=member_headers, json={"join_code": group["join_code"]})

    return admin_headers, member_headers, group


class TestDeleteGroup:
    def test_admin_can_delete_group(self, client: TestClient):
        admin_headers, _member_headers, group = _seed_group_with_two_members(client)

        resp = client.delete(f"/groups/{group['id']}", headers=admin_headers)
        assert resp.status_code == 204

        get_resp = client.get(f"/groups/{group['id']}", headers=admin_headers)
        assert get_resp.status_code == 404

    def test_non_admin_member_cannot_delete_group(self, client: TestClient):
        _admin_headers, member_headers, group = _seed_group_with_two_members(client)

        resp = client.delete(f"/groups/{group['id']}", headers=member_headers)
        assert resp.status_code == 403

    def test_non_member_cannot_delete_group(self, client: TestClient):
        admin_headers, _member_headers, group = _seed_group_with_two_members(client)
        outsider_headers = auth_headers(client, "outsider@example.com")

        resp = client.delete(f"/groups/{group['id']}", headers=outsider_headers)
        assert resp.status_code == 403

    def test_deleting_nonexistent_group_returns_404(self, client: TestClient):
        admin_headers = auth_headers(client, "admin@example.com")
        resp = client.delete("/groups/00000000-0000-0000-0000-000000000000", headers=admin_headers)
        assert resp.status_code == 404


class TestLeaveGroup:
    def test_member_can_leave_group(self, client: TestClient):
        admin_headers, member_headers, group = _seed_group_with_two_members(client)

        resp = client.post(f"/groups/{group['id']}/leave", headers=member_headers)
        assert resp.status_code == 204

        # No longer a member — subsequent group access is forbidden.
        get_resp = client.get(f"/groups/{group['id']}", headers=member_headers)
        assert get_resp.status_code == 403

        # Group and admin's membership are untouched.
        admin_get_resp = client.get(f"/groups/{group['id']}", headers=admin_headers)
        assert admin_get_resp.status_code == 200

    def test_admin_cannot_leave_group(self, client: TestClient):
        admin_headers, _member_headers, group = _seed_group_with_two_members(client)

        resp = client.post(f"/groups/{group['id']}/leave", headers=admin_headers)
        assert resp.status_code == 400

        # Group still exists and admin is still a member.
        get_resp = client.get(f"/groups/{group['id']}", headers=admin_headers)
        assert get_resp.status_code == 200

    def test_non_member_cannot_leave_group(self, client: TestClient):
        _admin_headers, _member_headers, group = _seed_group_with_two_members(client)
        outsider_headers = auth_headers(client, "outsider@example.com")

        resp = client.post(f"/groups/{group['id']}/leave", headers=outsider_headers)
        assert resp.status_code == 403

    def test_leaving_nonexistent_group_returns_404(self, client: TestClient):
        headers = auth_headers(client, "someone@example.com")
        resp = client.post("/groups/00000000-0000-0000-0000-000000000000/leave", headers=headers)
        assert resp.status_code == 404
