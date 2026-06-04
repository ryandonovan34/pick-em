import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Group(SQLModel, table=True):
    """
    A pick'em group. Every group has one admin, one challenge mode, and its own
    leaderboard isolated from all other groups.
    """

    __tablename__ = "groups"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    name: str = Field(max_length=100)
    admin_id: uuid.UUID = Field(foreign_key="users.id")
    # 6-character alphanumeric code shared with friends to join.
    join_code: str = Field(unique=True, max_length=10)
    # Odds API sport key: 'americanfootball_nfl' | 'soccer_fifa_world_cup'
    sport: str = Field(max_length=50)
    # Challenge structure: 'season' | 'worldCup'
    mode: str = Field(max_length=20)
    # The year this challenge covers (e.g. 2025 for NFL, 2026 for World Cup).
    season_year: int
    # If True, other users' picks are hidden until the game kicks off.
    blind_picks: bool = Field(default=True)
    superdogs_enabled: bool = Field(default=False)
    # Ignored when superdogs_enabled=False.
    superdogs_per_user: int = Field(default=3)
    created_at: datetime = Field(default_factory=_utc_now)


class GroupMember(SQLModel, table=True):
    """
    Join table between users and groups. The admin is always added as a member
    when the group is created, so they appear on the leaderboard and receive
    all member notifications.
    """

    __tablename__ = "group_members"

    group_id: uuid.UUID = Field(foreign_key="groups.id", primary_key=True)
    user_id: uuid.UUID = Field(foreign_key="users.id", primary_key=True)
    joined_at: datetime = Field(default_factory=_utc_now)
