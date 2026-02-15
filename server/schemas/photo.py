"""Photo request/response schemas."""

from typing import Optional

from pydantic import BaseModel


class PhotoCheckRequest(BaseModel):
    hashes: list[str]


class PhotoCheckResponse(BaseModel):
    existing: list[str]
    new: list[str]


class PhotoUploadResponse(BaseModel):
    photo_id: str
    thumb_url: str
    status: str


class PhotoResponse(BaseModel):
    id: str
    user_id: str
    uploaded_by: Optional[str] = None
    file_hash: str
    file_size: int
    mime_type: str
    width: Optional[int]
    height: Optional[int]
    taken_at: Optional[str]
    latitude: Optional[float]
    longitude: Optional[float]
    location_name: Optional[str]
    camera_make: Optional[str]
    camera_model: Optional[str]
    ai_scene: Optional[str] = None
    exif_data: Optional[str] = None
    description: Optional[str]
    is_favorite: bool
    is_video: bool
    duration: Optional[float]
    created_at: str
    thumb_small_url: str
    thumb_medium_url: str


class PhotoListResponse(BaseModel):
    photos: list[PhotoResponse]
    next_cursor: Optional[str]
    total_count: int


class PhotoUpdateRequest(BaseModel):
    is_favorite: Optional[bool] = None
    location_name: Optional[str] = None
    description: Optional[str] = None


class PhotoBatchRequest(BaseModel):
    action: str  # 'delete' | 'favorite' | 'unfavorite'
    photo_ids: list[str]


class PhotoBatchResponse(BaseModel):
    success_count: int
    failed_count: int


class SystemStatusResponse(BaseModel):
    server_name: str
    server_id: str
    server_url: str
    version: str
    photo_count: int
    total_size_bytes: int
    storage_total_bytes: int
    storage_used_bytes: int
    storage_free_bytes: int
    storage_usage_percent: float
