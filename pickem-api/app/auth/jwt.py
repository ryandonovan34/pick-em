import uuid
from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt

from app.config import settings

ALGORITHM = "HS256"


def create_access_token(user_id: uuid.UUID) -> str:
    """
    Create a short-lived JWT that proves a request comes from a specific user.
    The token is signed with SECRET_KEY — anyone who can verify the signature
    knows the token wasn't tampered with.
    """
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub": str(user_id),  # "subject" — the standard JWT claim for the user ID
        "exp": expire,
        "type": "access",
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=ALGORITHM)


def create_refresh_token() -> str:
    """
    Generate a random opaque token (not a JWT) used to get a new access token.
    We store the bcrypt hash of this value in the DB, never the raw token.
    Using a random token (not JWT) for refresh means we can explicitly revoke it
    by deleting the DB row — something you can't do with a stateless JWT.
    """
    return str(uuid.uuid4())


def decode_access_token(token: str) -> uuid.UUID:
    """
    Validate and decode an access token. Raises ValueError on any failure.
    Callers should convert this to an HTTP 401.
    """
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError as e:
        raise ValueError(f"Invalid token: {e}") from e

    if payload.get("type") != "access":
        raise ValueError("Token is not an access token.")

    user_id_str = payload.get("sub")
    if not user_id_str:
        raise ValueError("Token missing subject claim.")

    try:
        return uuid.UUID(user_id_str)
    except ValueError as e:
        raise ValueError(f"Invalid user ID in token: {e}") from e
