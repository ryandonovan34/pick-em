"""Add spread_locked to games table.

Once True, odds ingest stops overwriting spread/favorite_team for that game.
Set 30 minutes before kickoff so the line everyone picked against and the
line it's graded on are guaranteed to be the same number, instead of the
spread being free to drift right up to (or even during) kickoff.

Revision ID: 008
Revises: 007
Create Date: 2026-08-19
"""

from alembic import op
import sqlalchemy as sa

revision = "008"
down_revision = "007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("games", sa.Column("spread_locked", sa.Boolean(), nullable=False, server_default=sa.false()))


def downgrade() -> None:
    op.drop_column("games", "spread_locked")
