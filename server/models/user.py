"""User and Family models."""

import secrets
from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


class Family(SQLModel, table=True):
    __tablename__ = "families"

    id: str = Field(default_factory=lambda: f"fam_{secrets.token_hex(4)}", primary_key=True)
    name: str = Field(default="우리 가족")
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class User(SQLModel, table=True):
    __tablename__ = "users"

    id: str = Field(default_factory=lambda: f"usr_{secrets.token_hex(4)}", primary_key=True)
    family_id: str = Field(foreign_key="families.id", index=True)
    nickname: str
    password_hash: str
    role: str = Field(default="member")  # 'admin' | 'member'
    avatar_url: Optional[str] = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
