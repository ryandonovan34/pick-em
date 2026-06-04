"""
Result processing pipeline.

This is the heart of the scoring system. It's triggered by:
  - POST /dev/mock-results (Phase 2)
  - A scheduled Odds API results fetch (Phase 3+)

The pipeline is intentionally self-contained so it can be called from
both contexts with the same logic.
"""

import uuid
from datetime import datetime, timezone

from sqlmodel import Session, select

from app.models import Game, GroupMember, Pick, Standing, User


def _did_favorite_cover(game: Game, home_score: int, away_score: int) -> bool:
    """
    Returns True if the favorite covered the spread.

    The spread is stored from the favorite's perspective (negative = favored).
    To cover, the favorite must win by more than abs(spread).

    Example: spread=-7.5, favoriteTeam=home
        home wins by 8  →  8 > 7.5  →  True (favorite covered)
        home wins by 7  →  7 > 7.5  →  False (underdog covered)
    """
    if game.favorite_team == game.home_team:
        favorite_margin = home_score - away_score
    else:
        favorite_margin = away_score - home_score

    return favorite_margin > abs(game.spread)


def _did_underdog_win_outright(game: Game, home_score: int, away_score: int) -> bool:
    """
    Returns True if the underdog actually won the game (ignoring spread).
    Only used when evaluating superdog picks.
    """
    underdog = game.away_team if game.favorite_team == game.home_team else game.home_team
    if underdog == game.home_team:
        return home_score > away_score
    else:
        return away_score > home_score


def _pick_result(pick: Pick, game: Game, home_score: int, away_score: int) -> str:
    """Determine the result string for a single pick."""
    if pick.is_superdog:
        # Superdog: underdog must win OUTRIGHT for the 3-win bonus.
        return "superdog_win" if _did_underdog_win_outright(game, home_score, away_score) else "loss"
    else:
        favorite_covered = _did_favorite_cover(game, home_score, away_score)
        if pick.picked_team == game.favorite_team:
            return "win" if favorite_covered else "loss"
        else:
            return "loss" if favorite_covered else "win"


def _recompute_standing(user_id: uuid.UUID, group_id: uuid.UUID, session: Session) -> None:
    """
    Recompute and upsert the standing row for one user in one group.

    We derive it from the picks table rather than incrementing counters,
    which means it's always correct even if this function is called multiple times.
    """
    all_picks = session.exec(
        select(Pick).where(
            Pick.user_id == user_id,
            Pick.group_id == group_id,
            Pick.result != "pending",
        )
    ).all()

    wins = sum(1 for p in all_picks if p.result == "win")
    losses = sum(1 for p in all_picks if p.result in ("loss",))
    superdog_wins = sum(1 for p in all_picks if p.result == "superdog_win")
    superdogs_used = sum(1 for p in all_picks if p.is_superdog)

    # Superdog losses count as 1 loss (already covered above).
    # Superdog wins are tracked separately (3 pts each) but losses still = 1.
    standing = session.exec(
        select(Standing).where(
            Standing.user_id == user_id,
            Standing.group_id == group_id,
        )
    ).first()

    user = session.get(User, user_id)
    display_name = user.display_name if user else ""

    if standing is None:
        standing = Standing(user_id=user_id, group_id=group_id)

    standing.wins = wins
    standing.losses = losses
    standing.superdog_wins = superdog_wins
    standing.superdogs_used = superdogs_used
    standing.updated_at = datetime.now(timezone.utc)
    standing.display_name = display_name

    session.add(standing)


def process_game_result(
    game_id: uuid.UUID,
    home_score: int,
    away_score: int,
    session: Session,
) -> Game:
    """
    Process the result for a game. Steps:

    1. Record home_score and away_score on the game.
    2. For every pick on this game, determine 'win', 'loss', or 'superdog_win'.
    3. Recompute the standing row for every affected user in every affected group.
    4. Mark the game result_posted=True.

    This runs in the caller's transaction — commit/rollback is the caller's responsibility.
    """
    game = session.get(Game, game_id)
    if game is None:
        raise ValueError(f"Game {game_id} not found.")
    if game.result_posted:
        raise ValueError(f"Results already posted for game {game_id}.")

    game.home_score = home_score
    game.away_score = away_score
    game.result_posted = True
    session.add(game)

    picks = session.exec(select(Pick).where(Pick.game_id == game_id)).all()

    # Track which (user_id, group_id) pairs need their standings updated.
    affected: set[tuple[uuid.UUID, uuid.UUID]] = set()

    for pick in picks:
        pick.result = _pick_result(pick, game, home_score, away_score)
        pick.updated_at = datetime.now(timezone.utc)
        session.add(pick)
        affected.add((pick.user_id, pick.group_id))

    for user_id, group_id in affected:
        _recompute_standing(user_id, group_id, session)

    session.commit()
    session.refresh(game)
    return game
