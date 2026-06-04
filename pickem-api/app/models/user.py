import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class User(SQLModel, table=True):
    """A registered user. Passwords are never stored — only the bcrypt hash."""

    __tablename__ = "users"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    email: str = Field(unique=True, index=True, max_length=255)
    display_name: str = Field(max_length=100)
    hashed_pw: str
    # Updated on every app launch so the backend can always reach this device.
    fcm_token: Optional[str] = Field(default=None, max_length=255)
    created_at: datetime = Field(default_factory=_utc_now)


class RefreshToken(SQLModel, table=True):
    """
    Long-lived tokens that let users stay logged in without re-entering their password.
    We store only the bcrypt hash — never the raw token — so a DB breach doesn't
    hand out valid sessions.
    """

    __tablename__ = "refresh_tokens"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    # ON DELETE CASCADE is set in the Alembic migration so tokens are cleaned up
    # automatically when a user is deleted.
    user_id: uuid.UUID = Field(foreign_key="users.id")
    token_hash: str
    expires_at: datetime
    created_at: datetime = Field(default_factory=_utc_now)
