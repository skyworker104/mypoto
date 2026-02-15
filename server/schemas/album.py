"""Album request/response schemas."""

from typing import Optional

from pydantic import BaseModel


class AlbumCreateRequest(BaseModel):
    name: str
    type: str = "manual"  # 'manual' | 'shared'
    is_shared: bool = False


class AlbumUpdateRequest(BaseModel):
    name: Optional[str] = None
    cover_photo: Optional[str] = None
    is_shared: Optional[bool] = None


class AlbumResponse(BaseModel):
    id: str
    name: str
    type: str
    cover_photo: Optional[str]
    is_shared: bool
    photo_count: int
    created_by: str
    created_at: str


class AlbumDetailResponse(AlbumResponse):
    photos: list[str]  # photo IDs
    members: list[str]  # user IDs


class AlbumPhotosRequest(BaseModel):
    photo_ids: list[str]


class AlbumShareRequest(BaseModel):
    user_ids: list[str]
