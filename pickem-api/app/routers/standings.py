"""
Leaderboard endpoint.

Standings are pre-computed and stored in the standings table (updated when results
are processed), so this is a simple indexed read — no aggregation at query time.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session, select

from app.auth.dependencies import get_current_user
from app.database import get_session
from app.models import Group, GroupMember, Standing, User
from app.schemas.standing import StandingRead

router = APIRouter()


@router.get("/groups/{group_id}/standings", response_model=list[StandingRead])
def get_standings(
    group_id: uuid.UUID,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> list[Standing]:
    """
    Return the leaderboard for a group, sorted by win percentage (desc),
    then total effective wins as a tiebreaker.
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

    standings = session.exec(
        select(Standing).where(Standing.group_id == group_id)
    ).all()

    # Sort: higher win% first; break ties by total effective wins.
    def sort_key(s: Standing) -> tuple:
        effective_wins = s.wins + s.superdog_wins * 3
        total = effective_wins + s.losses
        win_pct = effective_wins / total if total > 0 else 0.0
        return (-win_pct, -effective_wins)

    return sorted(standings, key=sort_key)
