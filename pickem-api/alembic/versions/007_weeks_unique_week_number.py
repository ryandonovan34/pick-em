"""Add a unique constraint on (group_id, week_number) in weeks table.

Closes a race: two week-creation paths (the APScheduler auto-populate job
running in a background thread, and an admin hitting POST /groups/{id}/populate
or the manual create-week endpoint) can otherwise both miss a "does this week
already exist" check and insert two Week rows for the same real NFL week.
services/auto_slate.py::get_or_create_week() catches the resulting
IntegrityError and merges into the existing row instead of erroring.

Revision ID: 007
Revises: 006
Create Date: 2026-07-30
"""

from alembic import op

revision = "007"
down_revision = "006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_unique_constraint("uq_week_group_number", "weeks", ["group_id", "week_number"])


def downgrade() -> None:
    op.drop_constraint("uq_week_group_number", "weeks", type_="unique")
