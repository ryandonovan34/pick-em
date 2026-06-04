from collections.abc import Generator

from sqlmodel import Session, create_engine

from app.config import settings

# The engine is the connection pool to PostgreSQL.
# echo=True prints every SQL statement to stdout — helpful in dev, noisy in prod.
engine = create_engine(
    settings.DATABASE_URL,
    echo=settings.is_development,
)


def get_session() -> Generator[Session, None, None]:
    """
    FastAPI dependency. Yields a database session for the duration of a request,
    then commits or rolls back and closes it automatically.

    Usage in a route:
        def my_route(session: Session = Depends(get_session)):
            ...
    """
    with Session(engine) as session:
        yield session
