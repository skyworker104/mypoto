"""Album models."""

import secrets
from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


class Album(SQLModel, table=True):
    __tablename__ = "albums"

    id: str = Field(default_factory=lambda: f"alb_{secrets.token_hex(4)}", primary_key=True)
    user_id: str = Field(foreign_key="users.id", index=True)
    name: str
    type: str = Field(default="manual")  # 'manual' | 'shared' | 'auto'
    cover_photo_id: Optional[str] = Field(default=None, foreign_key="photos.id")
    is_shared: bool = Field(default=False)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class PhotoAlbum(SQLModel, table=True):
    __tablename__ = "photo_albums"

    id: Optional[int] = Field(default=None, primary_key=True)
    photo_id: str = Field(foreign_key="photos.id", index=True)
    album_id: str = Field(foreign_key="albums.id", index=True)
    added_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class AlbumMember(SQLModel, table=True):
    __tablename__ = "album_members"

    id: Optional[int] = Field(default=None, primary_key=True)
    album_id: str = Field(foreign_key="albums.id", index=True)
    user_id: str = Field(foreign_key="users.id", index=True)
    role: str = Field(default="member")  # 'owner' | 'member'
