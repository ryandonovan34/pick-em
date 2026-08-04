"""Add ends_on to weeks table so slates can span a custom date range
instead of always being computed as starts_on + 6 days.

Revision ID: 004
Revises: 003
Create Date: 2026-06-19
"""

from alembic import op
import sqlalchemy as sa

revision = "004"
down_revision = "003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("weeks", sa.Column("ends_on", sa.Date(), nullable=True))


def downgrade() -> None:
    op.drop_column("weeks", "ends_on")
