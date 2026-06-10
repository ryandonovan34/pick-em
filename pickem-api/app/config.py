from typing import Literal
from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """
    All configuration is read from environment variables (or a .env file).
    pydantic-settings validates types and raises a clear error at startup
    if a required variable is missing or has the wrong type.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",  # silently ignore unrecognised env vars
    )

    APP_ENV: Literal["development", "production"] = "development"

    DATABASE_URL: str = "postgresql+psycopg2://postgres:postgres@localhost:5432/pickem"

    @field_validator("DATABASE_URL", mode="before")
    @classmethod
    def normalize_database_url(cls, v: str) -> str:
        # Fly.io injects DATABASE_URL as postgres:// but SQLAlchemy 2 requires postgresql+psycopg2://
        if v.startswith("postgres://"):
            return v.replace("postgres://", "postgresql+psycopg2://", 1)
        return v

    SECRET_KEY: str = "change-me-before-production"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    ODDS_API_KEY: str = ""
    ODDS_API_BASE_URL: str = "https://api.the-odds-api.com"
    ODDS_CACHE_TTL_MINUTES: int = 120

    FCM_PROJECT_ID: str = ""
    FCM_SERVICE_ACCOUNT_JSON: str = ""

    @property
    def is_development(self) -> bool:
        return self.APP_ENV == "development"


# Single shared instance — import this everywhere instead of instantiating Settings() again.
settings = Settings()
