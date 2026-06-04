from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlmodel import Session

from app.auth.jwt import decode_access_token
from app.database import get_session
from app.models import User

# Extracts the Bearer token from the Authorization header.
_bearer = HTTPBearer()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
    session: Session = Depends(get_session),
) -> User:
    """
    FastAPI dependency. Validates the JWT in the Authorization header and
    returns the corresponding User. Any route that requires authentication
    should declare this as a dependency.

    Raises HTTP 401 if the token is missing, expired, or invalid.
    Raises HTTP 404 if the user in the token no longer exists in the DB
    (e.g., account deleted after the token was issued).
    """
    try:
        user_id = decode_access_token(credentials.credentials)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
            headers={"WWW-Authenticate": "Bearer"},
        )

    user = session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")
    return user
