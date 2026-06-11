# Import all models here so that:
# 1. SQLModel.metadata knows about every table (needed for create_all and Alembic autogenerate).
# 2. A single "from app.models import User, Group, ..." works throughout the app.

from app.models.user import User, RefreshToken
from app.models.group import Group, GroupMember
from app.models.week import Week
from app.models.game import Game
from app.models.slate_game import SlateGame
from app.models.pick import Pick
from app.models.standing import Standing

__all__ = [
    "User",
    "RefreshToken",
    "Group",
    "GroupMember",
    "Week",
    "Game",
    "SlateGame",
    "Pick",
    "Standing",
]
