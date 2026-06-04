from datetime import datetime, timezone


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def ensure_utc(dt: datetime) -> datetime:
    """
    Return a timezone-aware UTC datetime.

    SQLite stores datetimes as strings and reads them back as naive datetimes.
    PostgreSQL preserves timezone info. This function normalises both so
    comparisons work correctly in tests (SQLite) and in production (Postgres).
    """
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)
