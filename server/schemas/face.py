"""Face API schemas."""

from pydantic import BaseModel


class FaceResponse(BaseModel):
    id: str
    name: str | None
    photo_count: int
    cover_photo_id: str | None
    cover_thumb_url: str | None = None
    created_at: str = ""


class FaceListResponse(BaseModel):
    faces: list[FaceResponse]
    total: int


class FaceTagRequest(BaseModel):
    name: str


class FaceMergeRequest(BaseModel):
    source_face_ids: list[str]


class FaceMergeResponse(BaseModel):
    id: str
    name: str | None
    photo_count: int
    merged: int


class FaceReclusterResponse(BaseModel):
    clusters: int
    merged: int


class AIStatusResponse(BaseModel):
    ai_available: bool
    queue_size: int
    total_faces: int
    named_faces: int
    total_photo_faces: int
