"""Replace game.week_id with slate_games junction table

Revision ID: 002
Revises: 001
Create Date: 2026-06-10
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "002"
down_revision = "001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Migrate existing game.week_id assignments to the new junction table first.
    op.create_table(
        "slate_games",
        sa.Column("week_id", UUID(as_uuid=True), sa.ForeignKey("weeks.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("game_id", UUID(as_uuid=True), sa.ForeignKey("games.id", ondelete="CASCADE"), primary_key=True),
    )

    op.execute("""
        INSERT INTO slate_games (week_id, game_id)
        SELECT week_id, id FROM games WHERE week_id IS NOT NULL
    """)

    op.drop_constraint("games_week_id_fkey", "games", type_="foreignkey")
    op.drop_column("games", "week_id")


def downgrade() -> None:
    op.add_column("games", sa.Column("week_id", UUID(as_uuid=True), nullable=True))
    op.create_foreign_key("games_week_id_fkey", "games", "weeks", ["week_id"], ["id"], ondelete="CASCADE")

    op.execute("""
        UPDATE games g
        SET week_id = sg.week_id
        FROM slate_games sg
        WHERE sg.game_id = g.id
    """)

    op.drop_table("slate_games")
