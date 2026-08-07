"""
Pick submission and retrieval.

Key invariants:
  - A pick can only be submitted/changed before that game's kickoff.
  - A user can only have one pick per game per group.
  - Superdog validation is enforced here (group setting + spread threshold + user limit).
  - Blind-pick visibility is enforced here: other users' picks are omitted from
    the response for any game that hasn't kicked off yet (if blind_picks=True).
    This is server-side enforcement — the data never leaves this function.
"""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from app.utils import ensure_utc, utc_now
from sqlmodel import Session, func, select

from app.auth.dependencies import get_current_user
from app.database import get_session
from app.models import Game, Group, GroupMember, Pick, SlateGame, User, Week
from app.routers.groups import _require_member
from app.schemas.pick import PickCreate, PickHistoryEntry, PickRead, PickUpdate

# Prefixed with /picks in main.py
router = APIRouter()

# No prefix — for /groups/{group_id}/weeks/{week_id}/picks
group_picks_router = APIRouter()


def _require_game_not_locked(game: Game) -> None:
    if ensure_utc(game.kickoff_at) <= utc_now():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This game has already kicked off and picks are locked.",
        )


def _validate_superdog(
    pick: PickCreate | PickUpdate,
    game: Game,
    group: Group,
    user_id: uuid.UUID,
    session: Session,
    existing_pick_id: uuid.UUID | None = None,
) -> None:
    """Validate all three superdog eligibility conditions, each with a specific error."""
    if not pick.is_superdog:
        return

    if not group.superdogs_enabled:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Superdogs are not enabled for this group.",
        )

    if abs(game.spread) < 6.5:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Spread must be at least 6.5 to declare a superdog (current spread: {game.spread}).",
        )

    # The superdog must be declared on the underdog (not the favorite).
    underdog = game.away_team if game.favorite_team == game.home_team else game.home_team
    picked_team = pick.picked_team if isinstance(pick, PickCreate) else pick.picked_team
    if picked_team != underdog:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"A superdog must be declared on the underdog ({underdog}), not the favorite.",
        )

    # Count superdogs already used, excluding the pick being edited (if updating).
    query = select(func.count(Pick.id)).where(  # type: ignore[arg-type]
        Pick.user_id == user_id,
        Pick.group_id == group.id,
        Pick.is_superdog.is_(True),  # type: ignore[attr-defined]
    )
    if existing_pick_id:
        query = query.where(Pick.id != existing_pick_id)

    superdogs_used = session.exec(query).one()
    if superdogs_used >= group.superdogs_per_user:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"You have used all {group.superdogs_per_user} of your superdogs for this challenge.",
        )


@router.post("", response_model=PickRead, status_code=status.HTTP_201_CREATED)
def submit_pick(
    body: PickCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Pick:
    """
    Submit a pick for a game.

    - Validates the game exists and hasn't kicked off.
    - Validates superdog eligibility (group enabled, spread >= 6.5, under limit).
    - Returns 409 if a pick already exists (use PUT /picks/{id} to update).
    """
    game = session.get(Game, body.game_id)
    if game is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Game not found.")

    group = session.get(Group, body.group_id)
    if group is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found.")

    # Must be a member of the group.
    membership = session.exec(
        select(GroupMember).where(
            GroupMember.group_id == body.group_id,
            GroupMember.user_id == current_user.id,
        )
    ).first()
    if membership is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a member of this group.")

    _require_game_not_locked(game)

    # Check for duplicate.
    existing = session.exec(
        select(Pick).where(
            Pick.user_id == current_user.id,
            Pick.game_id == body.game_id,
            Pick.group_id == body.group_id,
        )
    ).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="You already have a pick for this game. Use PUT /picks/{id} to update it.",
        )

    _validate_superdog(body, game, group, current_user.id, session)

    pick = Pick(
        user_id=current_user.id,
        game_id=body.game_id,
        group_id=body.group_id,
        picked_team=body.picked_team,
        is_superdog=body.is_superdog,
    )
    session.add(pick)
    session.commit()
    session.refresh(pick)
    return pick


@router.put("/{pick_id}", response_model=PickRead)
def update_pick(
    pick_id: uuid.UUID,
    body: PickUpdate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Pick:
    """Update a pick before the game kicks off. Only the pick's owner can call this."""
    pick = session.get(Pick, pick_id)
    if pick is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pick not found.")
    if pick.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You can only edit your own picks.")

    game = session.get(Game, pick.game_id)
    group = session.get(Group, pick.group_id)
    if game is None or group is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Game or group not found.")

    _require_game_not_locked(game)
    _validate_superdog(body, game, group, current_user.id, session, existing_pick_id=pick.id)

    pick.picked_team = body.picked_team
    pick.is_superdog = body.is_superdog
    pick.updated_at = datetime.now(timezone.utc)
    session.add(pick)
    session.commit()
    session.refresh(pick)
    return pick


@group_picks_router.get("/groups/{group_id}/picks", response_model=list[PickRead])
def get_all_picks(
    group_id: uuid.UUID,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> list[Pick]:
    """Return the current user's own picks for all weeks in a group."""
    _require_member(group_id, current_user, session)
    picks = session.exec(
        select(Pick).where(
            Pick.group_id == group_id,
            Pick.user_id == current_user.id,
        )
    ).all()
    return list(picks)


@group_picks_router.get(
    "/groups/{group_id}/members/{user_id}/picks/history",
    response_model=list[PickHistoryEntry],
)
def get_pick_history(
    group_id: uuid.UUID,
    user_id: uuid.UUID,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> list[PickHistoryEntry]:
    """
    A group member's full history of GRADED picks (result != 'pending'),
    ordered chronologically by kickoff — for verifying their win/loss record.
    Any group member can view any other member's history (mirrors standings'
    group-wide visibility, since this is fundamentally the receipts behind
    that same leaderboard). Excludes pending picks: they haven't contributed
    to the record yet, and since a game is only graded after it kicks off,
    every entry here has already passed kickoff — no blind-pick filtering
    needed (that rule only restricts pre-kickoff visibility).
    """
    _require_member(group_id, current_user, session)

    target_membership = session.exec(
        select(GroupMember).where(GroupMember.group_id == group_id, GroupMember.user_id == user_id)
    ).first()
    if target_membership is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User is not a member of this group.")

    rows = session.exec(
        select(Pick, Game, Week)
        .join(Game, Game.id == Pick.game_id)  # type: ignore[arg-type]
        .join(SlateGame, SlateGame.game_id == Game.id)  # type: ignore[arg-type]
        .join(Week, Week.id == SlateGame.week_id)  # type: ignore[arg-type]
        .where(
            Pick.group_id == group_id,
            Pick.user_id == user_id,
            Week.group_id == group_id,
            Pick.result != "pending",
        )
        .order_by(Game.kickoff_at)  # type: ignore[arg-type]
    ).all()

    return [
        PickHistoryEntry(
            pick_id=pick.id,
            game_id=game.id,
            week_number=week.week_number,
            week_label=week.label,
            home_team=game.home_team,
            away_team=game.away_team,
            picked_team=pick.picked_team,
            favorite_team=game.favorite_team,
            spread=game.spread,
            kickoff_at=game.kickoff_at,
            is_superdog=pick.is_superdog,
            is_forfeit=pick.is_forfeit,
            result=pick.result,
            home_score=game.home_score,
            away_score=game.away_score,
        )
        for pick, game, week in rows
    ]


@group_picks_router.get("/groups/{group_id}/weeks/{week_id}/picks", response_model=list[PickRead])
def get_picks(
    group_id: uuid.UUID,
    week_id: uuid.UUID,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> list[Pick]:
    """
    Return picks for a week.

    Visibility rules (enforced server-side):
      - The current user's own picks are ALWAYS returned.
      - If blind_picks=True: other users' picks are omitted for games that
        haven't kicked off yet. After kickoff, all picks are visible.
      - If blind_picks=False: all picks are returned regardless of kickoff.
    """
    group = session.get(Group, group_id)
    if group is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found.")

    membership = session.exec(
        select(GroupMember).where(
            GroupMember.group_id == group_id,
            GroupMember.user_id == current_user.id,
        )
    ).first()
    if membership is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a member of this group.")

    # Get all games in the week so we can check kickoff times efficiently.
    games_in_week = {
        g.id: g
        for g in session.exec(
            select(Game)
            .join(SlateGame, SlateGame.game_id == Game.id)  # type: ignore[arg-type]
            .where(SlateGame.week_id == week_id)
        ).all()
    }

    all_picks = session.exec(
        select(Pick).where(
            Pick.group_id == group_id,
            Pick.game_id.in_(list(games_in_week.keys())),  # type: ignore[attr-defined]
        )
    ).all()

    if not group.blind_picks:
        return list(all_picks)

    # Blind mode: filter out other users' picks for games that haven't started.
    now = utc_now()
    visible: list[Pick] = []
    for pick in all_picks:
        game = games_in_week.get(pick.game_id)
        is_own = pick.user_id == current_user.id
        is_locked = game is not None and ensure_utc(game.kickoff_at) <= now
        if is_own or is_locked:
            visible.append(pick)

    return visible
