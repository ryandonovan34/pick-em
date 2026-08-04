"""Add include_preseason and include_playoffs to groups table.

Governs auto-population only (see services/auto_slate.py) — admins can still
manually create/add preseason or playoff weeks regardless of these flags.

Revision ID: 006
Revises: 005
Create Date: 2026-07-30
"""

from alembic import op
import sqlalchemy as sa

revision = "006"
down_revision = "005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("groups", sa.Column("include_preseason", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column("groups", sa.Column("include_playoffs", sa.Boolean(), nullable=False, server_default=sa.true()))


def downgrade() -> None:
    op.drop_column("groups", "include_playoffs")
    op.drop_column("groups", "include_preseason")
