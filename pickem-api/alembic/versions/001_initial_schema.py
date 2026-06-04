"""Initial schema

Revision ID: 001
Revises:
Create Date: 2026-06-02
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("email", sa.String(255), nullable=False, unique=True),
        sa.Column("display_name", sa.String(100), nullable=False),
        sa.Column("hashed_pw", sa.Text, nullable=False),
        sa.Column("fcm_token", sa.String(255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_users_email", "users", ["email"])

    op.create_table(
        "refresh_tokens",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("token_hash", sa.Text, nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )

    op.create_table(
        "groups",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("admin_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("join_code", sa.String(10), nullable=False, unique=True),
        sa.Column("sport", sa.String(50), nullable=False),
        sa.Column("mode", sa.String(20), nullable=False),
        sa.Column("season_year", sa.Integer, nullable=False),
        sa.Column("blind_picks", sa.Boolean, nullable=False, server_default="true"),
        sa.Column("superdogs_enabled", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("superdogs_per_user", sa.Integer, nullable=False, server_default="3"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )

    op.create_table(
        "group_members",
        sa.Column("group_id", UUID(as_uuid=True), sa.ForeignKey("groups.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("joined_at", sa.DateTime(timezone=True), nullable=False),
    )

    op.create_table(
        "weeks",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("group_id", UUID(as_uuid=True), sa.ForeignKey("groups.id", ondelete="CASCADE"), nullable=False),
        sa.Column("week_number", sa.Integer, nullable=False),
        sa.Column("label", sa.String(100), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )

    op.create_table(
        "games",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("week_id", UUID(as_uuid=True), sa.ForeignKey("weeks.id", ondelete="CASCADE"), nullable=True),
        sa.Column("odds_api_id", sa.String(100), nullable=True, unique=True),
        sa.Column("sport", sa.String(50), nullable=False),
        sa.Column("home_team", sa.String(100), nullable=False),
        sa.Column("away_team", sa.String(100), nullable=False),
        sa.Column("spread", sa.Numeric(5, 1), nullable=False),
        sa.Column("favorite_team", sa.String(100), nullable=False),
        sa.Column("kickoff_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("home_score", sa.Integer, nullable=True),
        sa.Column("away_score", sa.Integer, nullable=True),
        sa.Column("result_posted", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("odds_fetched_at", sa.DateTime(timezone=True), nullable=False),
    )

    op.create_table(
        "picks",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("game_id", UUID(as_uuid=True), sa.ForeignKey("games.id", ondelete="CASCADE"), nullable=False),
        sa.Column("group_id", UUID(as_uuid=True), sa.ForeignKey("groups.id", ondelete="CASCADE"), nullable=False),
        sa.Column("picked_team", sa.String(100), nullable=False),
        sa.Column("is_superdog", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("result", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("user_id", "game_id", "group_id", name="uq_pick_per_game"),
    )

    op.create_table(
        "standings",
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("group_id", UUID(as_uuid=True), sa.ForeignKey("groups.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("wins", sa.Integer, nullable=False, server_default="0"),
        sa.Column("losses", sa.Integer, nullable=False, server_default="0"),
        sa.Column("superdog_wins", sa.Integer, nullable=False, server_default="0"),
        sa.Column("superdogs_used", sa.Integer, nullable=False, server_default="0"),
        sa.Column("display_name", sa.String(100), nullable=False, server_default=""),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("standings")
    op.drop_table("picks")
    op.drop_table("games")
    op.drop_table("weeks")
    op.drop_table("group_members")
    op.drop_table("groups")
    op.drop_table("refresh_tokens")
    op.drop_index("ix_users_email", "users")
    op.drop_table("users")
