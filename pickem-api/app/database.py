from collections.abc import Generator

from sqlmodel import Session, create_engine

from app.config import settings

# The engine is the connection pool to PostgreSQL.
# echo=True prints every SQL statement to stdout — helpful in dev, noisy in prod.
# pool_pre_ping: the Fly.io machine can suspend when idle (auto_stop_machines =
# "suspend" in fly.toml) and resume later — any connection already checked out
# of the pool at suspend time survives as a dead reference, and Postgres (or
# the network path) may have closed it during the suspend window regardless.
# Without pre-ping, the next query on that connection fails outright with
# "server closed the connection unexpectedly"; pre-ping cheaply tests each
# connection before handing it out and transparently reconnects if it's dead.
engine = create_engine(
    settings.DATABASE_URL,
    echo=settings.is_development,
    pool_pre_ping=True,
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
