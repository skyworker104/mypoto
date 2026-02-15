"""Device model."""

import secrets
from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


class Device(SQLModel, table=True):
    __tablename__ = "devices"

    id: str = Field(default_factory=lambda: f"dev_{secrets.token_hex(4)}", primary_key=True)
    user_id: str = Field(foreign_key="users.id", index=True)
    device_name: str
    device_type: str  # 'ios' | 'android'
    device_model: Optional[str] = None
    app_version: Optional[str] = None
    token_hash: Optional[str] = None  # refresh token hash
    last_seen: Optional[datetime] = None
    status: str = Field(default="paired")  # 'paired' | 'revoked'
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
