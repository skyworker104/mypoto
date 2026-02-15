"""Photo and Face models."""

import secrets
from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


class Photo(SQLModel, table=True):
    __tablename__ = "photos"

    id: str = Field(default_factory=lambda: f"pho_{secrets.token_hex(4)}", primary_key=True)
    user_id: str = Field(foreign_key="users.id", index=True)
    file_hash: str = Field(unique=True, index=True)
    file_path: str
    thumb_path: Optional[str] = None
    file_size: int
    mime_type: str
    width: Optional[int] = None
    height: Optional[int] = None
    taken_at: Optional[datetime] = Field(default=None, index=True)
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    location_name: Optional[str] = Field(default=None, index=True)
    camera_make: Optional[str] = None
    camera_model: Optional[str] = None
    exif_data: Optional[str] = None  # JSON
    ai_tags: Optional[str] = None  # JSON
    ai_scene: Optional[str] = None
    description: Optional[str] = None
    is_favorite: bool = Field(default=False)
    is_video: bool = Field(default=False)
    duration: Optional[float] = None  # seconds for video
    status: str = Field(default="active")  # 'active' | 'deleted'
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class Face(SQLModel, table=True):
    __tablename__ = "faces"

    id: str = Field(default_factory=lambda: f"fac_{secrets.token_hex(4)}", primary_key=True)
    user_id: Optional[str] = Field(default=None, foreign_key="users.id")
    name: Optional[str] = None
    embedding: Optional[bytes] = None  # face embedding vector
    photo_count: int = Field(default=0)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class PhotoFace(SQLModel, table=True):
    __tablename__ = "photo_faces"

    id: Optional[int] = Field(default=None, primary_key=True)
    photo_id: str = Field(foreign_key="photos.id", index=True)
    face_id: str = Field(foreign_key="faces.id", index=True)
    bbox_x: float = 0
    bbox_y: float = 0
    bbox_w: float = 0
    bbox_h: float = 0
    confidence: float = 0


class Highlight(SQLModel, table=True):
    __tablename__ = "highlights"

    id: str = Field(default_factory=lambda: f"hly_{secrets.token_hex(4)}", primary_key=True)
    user_id: str = Field(foreign_key="users.id", index=True)
    title: str
    description: Optional[str] = None
    video_path: Optional[str] = None
    thumbnail_path: Optional[str] = None
    photo_ids: str = "[]"  # JSON array of photo IDs
    duration_seconds: Optional[int] = None
    source_type: str = "date_range"  # date_range | location | faces | album
    source_params: Optional[str] = None  # JSON
    date_from: Optional[str] = None
    date_to: Optional[str] = None
    status: str = Field(default="pending")  # pending | processing | completed | failed
    error_message: Optional[str] = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    completed_at: Optional[datetime] = None
