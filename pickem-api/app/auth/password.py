from passlib.context import CryptContext

# bcrypt is the industry standard for password hashing.
# auto_schemes means the latest available bcrypt variant is used;
# deprecated="auto" automatically re-hashes on login if the hash is older.
_pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(plain: str) -> str:
    """Return a bcrypt hash of the password. Store this in the DB, never the plain text."""
    return _pwd_context.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    """Return True if the plain-text password matches the stored hash."""
    return _pwd_context.verify(plain, hashed)
