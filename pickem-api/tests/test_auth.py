"""
Integration tests for authentication endpoints.
"""

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session

from tests.conftest import auth_headers, register_user


class TestRegister:
    def test_register_success(self, client: TestClient):
        resp = client.post("/auth/register", json={
            "email": "alice@example.com",
            "display_name": "Alice",
            "password": "securepass",
        })
        assert resp.status_code == 201
        data = resp.json()
        assert data["user"]["email"] == "alice@example.com"
        assert "access_token" in data
        assert "refresh_token" in data

    def test_register_duplicate_email_returns_409(self, client: TestClient):
        register_user(client)
        resp = client.post("/auth/register", json={
            "email": "test@example.com",
            "display_name": "Duplicate",
            "password": "password123",
        })
        assert resp.status_code == 409

    def test_register_short_password_returns_422(self, client: TestClient):
        resp = client.post("/auth/register", json={
            "email": "short@example.com",
            "display_name": "Short",
            "password": "abc",
        })
        assert resp.status_code == 422

    def test_register_blank_display_name_returns_422(self, client: TestClient):
        resp = client.post("/auth/register", json={
            "email": "blank@example.com",
            "display_name": "   ",
            "password": "password123",
        })
        assert resp.status_code == 422


class TestLogin:
    def test_login_success(self, client: TestClient):
        register_user(client)
        resp = client.post("/auth/login", json={
            "email": "test@example.com",
            "password": "password123",
        })
        assert resp.status_code == 200
        assert "access_token" in resp.json()

    def test_login_wrong_password_returns_401(self, client: TestClient):
        register_user(client)
        resp = client.post("/auth/login", json={
            "email": "test@example.com",
            "password": "wrongpassword",
        })
        assert resp.status_code == 401

    def test_login_unknown_email_returns_401(self, client: TestClient):
        resp = client.post("/auth/login", json={
            "email": "nobody@example.com",
            "password": "password123",
        })
        assert resp.status_code == 401


class TestRefresh:
    def test_refresh_returns_new_access_token(self, client: TestClient):
        data = register_user(client)
        resp = client.post("/auth/refresh", json={"refresh_token": data["refresh_token"]})
        assert resp.status_code == 200
        assert "access_token" in resp.json()

    def test_refresh_with_invalid_token_returns_401(self, client: TestClient):
        resp = client.post("/auth/refresh", json={"refresh_token": "not-a-real-token"})
        assert resp.status_code == 401


class TestProtectedRoute:
    def test_missing_token_returns_403(self, client: TestClient):
        # FastAPI's HTTPBearer returns 403 (not 401) when no Authorization header is sent.
        resp = client.get("/groups")
        assert resp.status_code == 403

    def test_invalid_token_returns_401(self, client: TestClient):
        resp = client.get("/groups", headers={"Authorization": "Bearer invalid.token.here"})
        assert resp.status_code == 401
