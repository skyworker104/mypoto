"""Family and invite schemas."""

from typing import Optional

from pydantic import BaseModel


class FamilyMemberResponse(BaseModel):
    user_id: str
    nickname: str
    role: str
    avatar_url: Optional[str]
    device_count: int


class FamilyResponse(BaseModel):
    id: str
    name: str
    members: list[FamilyMemberResponse]


class InviteCreateRequest(BaseModel):
    role: str = "member"
    nickname_hint: Optional[str] = None
    expires_in: int = 86400  # seconds


class InviteCreateResponse(BaseModel):
    invite_code: str
    invite_token: str
    invite_url: str
    qr_data: str
    expires_at: str


class InviteJoinRequest(BaseModel):
    invite_code: str
    nickname: str
    password: str
    device_name: str
    device_type: str
    device_model: Optional[str] = None


class InviteJoinResponse(BaseModel):
    user_id: str
    device_id: str
    access_token: str
    refresh_token: str
    family_name: str


class DeviceResponse(BaseModel):
    id: str
    device_name: str
    device_type: str
    device_model: Optional[str]
    status: str
    last_seen: Optional[str]


class DeviceUpdateRequest(BaseModel):
    device_name: str
