"""Comment model."""

import secrets
from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


class Comment(SQLModel, table=True):
    __tablename__ = "comments"

    id: str = Field(default_factory=lambda: f"cmt_{secrets.token_hex(4)}", primary_key=True)
    photo_id: str = Field(foreign_key="photos.id", index=True)
    user_id: str = Field(foreign_key="users.id")
    content: Optional[str] = None
    emoji: Optional[str] = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
