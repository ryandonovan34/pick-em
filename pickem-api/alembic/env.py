"""
Alembic migration environment.

This file runs every time you invoke the `alembic` CLI.
It connects to the database and provides the SQLModel metadata so Alembic
can diff the current schema against your models to auto-generate migrations.

Run `alembic revision --autogenerate -m "describe your change"` to create a new migration.
Run `alembic upgrade head` to apply all pending migrations.
"""

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool
from sqlmodel import SQLModel

# Import the app config (DATABASE_URL) and all models (to populate SQLModel.metadata).
from app.config import settings
import app.models  # noqa: F401 — registers all table metadata

# Alembic's own logging config from alembic.ini.
config = context.config
if config.config_file_name:
    fileConfig(config.config_file_name)

# The metadata Alembic diffs against.
target_metadata = SQLModel.metadata

# Inject the real DATABASE_URL so alembic.ini doesn't need to duplicate it.
config.set_main_option("sqlalchemy.url", settings.DATABASE_URL)


def run_migrations_offline() -> None:
    """
    Run migrations without a live DB connection — generates SQL scripts only.
    Useful for reviewing what a migration will do before running it.
    """
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations against the live database."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,  # don't hold connection open between migrations
    )
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
