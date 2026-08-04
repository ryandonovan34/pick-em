"""
Group management endpoints.

Groups are the core organisational unit. Each group has one admin, one challenge
configuration (sport, mode, blind picks, superdogs), and an isolated leaderboard.
"""

import secrets
import string
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session, select

from app.auth.dependencies import get_current_user
from app.database import get_session
from app.models import Group, GroupMember, User
from app.schemas.auth import GroupCreate, GroupRead, JoinGroupRequest

router = APIRouter()


def _generate_join_code() -> str:
    """Generate a random 6-character alphanumeric join code (uppercase)."""
    alphabet = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(6))


def _require_member(group_id: uuid.UUID, user: User, session: Session) -> Group:
    """Raise 404 if the group doesn't exist; 403 if the user isn't a member."""
    group = session.get(Group, group_id)
    if group is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found.")
    membership = session.exec(
        select(GroupMember).where(
            GroupMember.group_id == group_id,
            GroupMember.user_id == user.id,
        )
    ).first()
    if membership is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a member of this group.")
    return group


def _require_admin(group: Group, user: User) -> None:
    """Raise 403 if the user isn't the group admin."""
    if group.admin_id != user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the group admin can do this.")


@router.post("", response_model=GroupRead, status_code=status.HTTP_201_CREATED)
def create_group(
    body: GroupCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Group:
    """
    Create a new group. The creator becomes the admin and is automatically
    added as a full member (appears on leaderboard, submits picks, receives notifications).
    """
    # Generate a unique join code (retry on collision, which is astronomically rare).
    for _ in range(5):
        code = _generate_join_code()
        if not session.exec(select(Group).where(Group.join_code == code)).first():
            break
    else:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Could not generate a unique join code.")

    group = Group(
        name=body.name,
        admin_id=current_user.id,
        join_code=code,
        sport=body.sport,
        mode=body.mode,
        season_year=body.season_year,
        blind_picks=body.blind_picks,
        superdogs_enabled=body.superdogs_enabled,
        superdogs_per_user=body.superdogs_per_user,
        include_preseason=body.include_preseason,
        include_playoffs=body.include_playoffs,
    )
    session.add(group)
    session.flush()  # flush to get group.id before creating the membership row

    # Admin is automatically a member.
    session.add(GroupMember(group_id=group.id, user_id=current_user.id))
    session.commit()
    session.refresh(group)

    return group


@router.get("", response_model=list[GroupRead])
def list_groups(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> list[Group]:
    """Return all groups the current user belongs to."""
    memberships = session.exec(
        select(GroupMember).where(GroupMember.user_id == current_user.id)
    ).all()
    group_ids = [m.group_id for m in memberships]
    if not group_ids:
        return []
    return list(session.exec(select(Group).where(Group.id.in_(group_ids))).all())  # type: ignore[attr-defined]


@router.get("/{group_id}", response_model=GroupRead)
def get_group(
    group_id: uuid.UUID,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Group:
    """Return a group. Requires membership."""
    return _require_member(group_id, current_user, session)


@router.post("/join", response_model=GroupRead)
def join_group(
    body: JoinGroupRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Group:
    """Join a group using the 6-character join code shared by the admin."""
    group = session.exec(select(Group).where(Group.join_code == body.join_code.upper())).first()
    if group is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid join code.")

    already_member = session.exec(
        select(GroupMember).where(
            GroupMember.group_id == group.id,
            GroupMember.user_id == current_user.id,
        )
    ).first()
    if already_member:
        return group  # idempotent

    session.add(GroupMember(group_id=group.id, user_id=current_user.id))
    session.commit()
    return group


@router.delete("/{group_id}/members/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_member(
    group_id: uuid.UUID,
    user_id: uuid.UUID,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> None:
    """Remove a member from a group. Only the admin can call this."""
    group = _require_member(group_id, current_user, session)
    _require_admin(group, current_user)

    if user_id == current_user.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="The admin cannot remove themselves.")

    membership = session.exec(
        select(GroupMember).where(
            GroupMember.group_id == group_id,
            GroupMember.user_id == user_id,
        )
    ).first()
    if membership:
        session.delete(membership)
        session.commit()
