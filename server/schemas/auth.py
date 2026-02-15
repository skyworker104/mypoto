"""Auth and pairing request/response schemas."""

from typing import Optional

from pydantic import BaseModel


# --- Pairing ---

class PairInitResponse(BaseModel):
    pin_displayed: bool
    expires_in: int
    message: str


class PairRequest(BaseModel):
    pin: str
    device_name: str
    device_type: str  # 'ios' | 'android'
    device_model: Optional[str] = None
    app_version: Optional[str] = None


class PairResponse(BaseModel):
    device_id: str
    user_id: str
    access_token: str
    refresh_token: str
    server_name: str
    is_new_user: bool


class PairErrorResponse(BaseModel):
    error: str
    remaining_attempts: int
    message: str


# --- Auth ---

class RefreshRequest(BaseModel):
    refresh_token: str
    device_id: str


class RefreshResponse(BaseModel):
    access_token: str


# --- User Setup ---

class UserSetupRequest(BaseModel):
    nickname: str
    password: str


class UserSetupResponse(BaseModel):
    user_id: str
    nickname: str
    role: str


# --- User Profile ---

class UserProfileResponse(BaseModel):
    id: str
    nickname: str
    role: str
    avatar_url: Optional[str]
    family_id: str
    family_name: str


class UserUpdateRequest(BaseModel):
    nickname: Optional[str] = None
    avatar_url: Optional[str] = None
