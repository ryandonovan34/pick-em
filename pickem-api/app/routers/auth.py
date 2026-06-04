"""
Authentication endpoints.

Flow:
  1. POST /auth/register  — create account, get tokens
  2. POST /auth/login     — exchange credentials for tokens
  3. POST /auth/refresh   — exchange refresh token for a new access token
  4. POST /auth/logout    — invalidate a refresh token
  5. PUT  /auth/fcm-token — store the device's FCM push token
"""

import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session, select

from app.auth.dependencies import get_current_user
from app.auth.jwt import create_access_token, create_refresh_token
from app.auth.password import hash_password, verify_password
from app.database import get_session
from app.models import User
from app.models.user import RefreshToken
from app.schemas.auth import (
    AuthResponse,
    FCMTokenUpdate,
    JoinGroupRequest,
    LoginRequest,
    RefreshRequest,
    TokenResponse,
    UserCreate,
    UserRead,
)
from app.config import settings

router = APIRouter()


def _create_auth_response(user: User, session: Session) -> AuthResponse:
    """Create access + refresh tokens and persist the refresh token hash."""
    from app.auth.password import hash_password as _hash

    access = create_access_token(user.id)
    raw_refresh = create_refresh_token()

    token_row = RefreshToken(
        user_id=user.id,
        token_hash=_hash(raw_refresh),
        expires_at=datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
    )
    session.add(token_row)
    session.commit()

    return AuthResponse(
        access_token=access,
        refresh_token=raw_refresh,
        user=UserRead.model_validate(user),
    )


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def register(body: UserCreate, session: Session = Depends(get_session)) -> AuthResponse:
    """
    Create a new account.
    Returns access_token + refresh_token so the user is immediately logged in.
    """
    existing = session.exec(select(User).where(User.email == body.email)).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with that email already exists.",
        )

    user = User(
        email=body.email,
        display_name=body.display_name,
        hashed_pw=hash_password(body.password),
    )
    session.add(user)
    session.commit()
    session.refresh(user)

    return _create_auth_response(user, session)


@router.post("/login", response_model=AuthResponse)
def login(body: LoginRequest, session: Session = Depends(get_session)) -> AuthResponse:
    """Exchange email + password for an access token and a refresh token."""
    user = session.exec(select(User).where(User.email == body.email)).first()

    # Always run verify_password (even if user is None) to prevent timing attacks
    # that could reveal whether an email is registered.
    # This is a real bcrypt hash of "dummy" — the verify will fail but takes the same time.
    _DUMMY_HASH = "$2b$12$Ov9pM3sOYvHzxuFjyuALMu.rEWW5LFEkm2VBKg8TCtAUGg3/vb0HK"
    hashed = user.hashed_pw if user else _DUMMY_HASH
    password_ok = verify_password(body.password, hashed)

    if not user or not password_ok:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password.",
        )

    return _create_auth_response(user, session)


@router.post("/refresh", response_model=TokenResponse)
def refresh_token(body: RefreshRequest, session: Session = Depends(get_session)) -> TokenResponse:
    """
    Exchange a valid refresh token for a new short-lived access token.
    The refresh token itself is NOT rotated — it stays valid until it expires or
    the user calls /logout.
    """
    # Look up all non-expired refresh tokens and check each hash.
    # This is O(n) per user but users typically have very few active tokens.
    now = datetime.now(timezone.utc)
    rows = session.exec(
        select(RefreshToken).where(RefreshToken.expires_at > now)
    ).all()

    matched_row = None
    for row in rows:
        if verify_password(body.refresh_token, row.token_hash):
            matched_row = row
            break

    if matched_row is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token is invalid or expired.",
        )

    user = session.get(User, matched_row.user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found.")

    return TokenResponse(access_token=create_access_token(user.id))


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(
    body: RefreshRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> None:
    """
    Invalidate a refresh token. The client should discard both tokens after calling this.
    Silently succeeds even if the token wasn't found (idempotent).
    """
    rows = session.exec(
        select(RefreshToken).where(RefreshToken.user_id == current_user.id)
    ).all()

    for row in rows:
        if verify_password(body.refresh_token, row.token_hash):
            session.delete(row)
            session.commit()
            return


@router.put("/fcm-token", status_code=status.HTTP_204_NO_CONTENT)
def update_fcm_token(
    body: FCMTokenUpdate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> None:
    """Store the device's FCM push token. Called on every app launch."""
    current_user.fcm_token = body.fcm_token
    session.add(current_user)
    session.commit()
