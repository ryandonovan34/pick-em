import uuid
from datetime import datetime

from pydantic import BaseModel, EmailStr, field_validator


class UserCreate(BaseModel):
    email: EmailStr
    display_name: str
    password: str

    @field_validator("password")
    @classmethod
    def password_min_length(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters.")
        return v

    @field_validator("display_name")
    @classmethod
    def display_name_not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Display name cannot be blank.")
        return v.strip()


class UserRead(BaseModel):
    id: uuid.UUID
    email: str
    display_name: str
    created_at: datetime

    model_config = {"from_attributes": True}


class AuthResponse(BaseModel):
    """Returned on successful register or login."""
    access_token: str
    refresh_token: str
    user: UserRead


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenResponse(BaseModel):
    access_token: str


class FCMTokenUpdate(BaseModel):
    fcm_token: str


class GroupCreate(BaseModel):
    name: str
    sport: str
    mode: str
    season_year: int
    blind_picks: bool = True
    superdogs_enabled: bool = False
    superdogs_per_user: int = 3
    include_preseason: bool = False
    include_playoffs: bool = True


class GroupRead(BaseModel):
    id: uuid.UUID
    name: str
    admin_id: uuid.UUID
    join_code: str
    sport: str
    mode: str
    season_year: int
    blind_picks: bool
    superdogs_enabled: bool
    superdogs_per_user: int
    include_preseason: bool
    include_playoffs: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class JoinGroupRequest(BaseModel):
    join_code: str
