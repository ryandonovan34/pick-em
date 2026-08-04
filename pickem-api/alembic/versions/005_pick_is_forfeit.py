"""Add is_forfeit to picks table.

A forfeit pick is auto-created when a game's result is posted and a group
member never submitted a pick before kickoff — it counts as a loss.

Revision ID: 005
Revises: 004
Create Date: 2026-06-19
"""

from alembic import op
import sqlalchemy as sa

revision = "005"
down_revision = "004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("picks", sa.Column("is_forfeit", sa.Boolean(), nullable=False, server_default=sa.false()))


def downgrade() -> None:
    op.drop_column("picks", "is_forfeit")
