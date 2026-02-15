"""Invite model."""

import secrets
from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


class Invite(SQLModel, table=True):
    __tablename__ = "invites"

    id: str = Field(default_factory=lambda: f"inv_{secrets.token_hex(4)}", primary_key=True)
    family_id: str = Field(foreign_key="families.id", index=True)
    created_by: str = Field(foreign_key="users.id")
    invite_code: str = Field(index=True)  # 8-digit code
    invite_token: str = Field(unique=True)
    role: str = Field(default="member")
    nickname_hint: Optional[str] = None
    expires_at: datetime
    used_at: Optional[datetime] = None
    used_by: Optional[str] = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
