"""Add starts_on to weeks table and backfill from existing slate games.

Revision ID: 003
Revises: 002
Create Date: 2026-06-15

"""
from alembic import op
import sqlalchemy as sa

revision = "003"
down_revision = "002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("weeks", sa.Column("starts_on", sa.Date(), nullable=True))

    # Backfill: set starts_on to the Monday of the week containing the first
    # game in each existing slate. Weeks with no games get NULL.
    op.execute("""
        UPDATE weeks w
        SET starts_on = (
            SELECT DATE_TRUNC('week', MIN(g.kickoff_at) AT TIME ZONE 'UTC')::date
            FROM slate_games sg
            JOIN games g ON g.id = sg.game_id
            WHERE sg.week_id = w.id
        )
        WHERE EXISTS (
            SELECT 1 FROM slate_games sg WHERE sg.week_id = w.id
        )
    """)


def downgrade() -> None:
    op.drop_column("weeks", "starts_on")
