import uuid

from sqlmodel import Field, SQLModel


class SlateGame(SQLModel, table=True):
    """
    Junction table linking a week's slate to the games it contains.
    A game can appear in multiple groups' weeks simultaneously.
    """

    __tablename__ = "slate_games"

    week_id: uuid.UUID = Field(foreign_key="weeks.id", primary_key=True, ondelete="CASCADE")
    game_id: uuid.UUID = Field(foreign_key="games.id", primary_key=True, ondelete="CASCADE")
