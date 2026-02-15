"""Face recognition API endpoints."""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlmodel import Session, select, func

from server.api.deps import get_current_user
from server.database import get_session
from server.models.photo import Face, PhotoFace
from server.models.user import User
from server.schemas.face import (
    AIStatusResponse,
    FaceListResponse,
    FaceMergeRequest,
    FaceMergeResponse,
    FaceReclusterResponse,
    FaceResponse,
    FaceTagRequest,
)
from server.schemas.photo import PhotoListResponse, PhotoResponse
from server.services.face_service import (
    get_face_photos,
    get_faces,
    merge_faces,
    recluster_faces,
    tag_face,
)

router = APIRouter(prefix="/faces", tags=["faces"])


def _face_to_response(f: dict) -> FaceResponse:
    cover_id = f.get("cover_photo_id")
    return FaceResponse(
        id=f["id"],
        name=f.get("name"),
        photo_count=f["photo_count"],
        cover_photo_id=cover_id,
        cover_thumb_url=f"/api/v1/photos/{cover_id}/thumb" if cover_id else None,
        created_at=f.get("created_at", ""),
    )


@router.get("", response_model=FaceListResponse)
def list_faces(
    named_only: bool = Query(default=False),
    min_photos: int = Query(default=1, ge=1),
    limit: int = Query(default=100, ge=1, le=500),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """List detected face clusters (persons)."""
    faces = get_faces(session, named_only=named_only, min_photos=min_photos, limit=limit)
    return FaceListResponse(
        faces=[_face_to_response(f) for f in faces],
        total=len(faces),
    )


@router.get("/{face_id}/photos")
def get_face_photos_endpoint(
    face_id: str,
    cursor: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get photos containing a specific face."""
    face = session.get(Face, face_id)
    if not face:
        raise HTTPException(status_code=404, detail="Face not found")

    photos, next_cursor = get_face_photos(face_id, session, cursor=cursor, limit=limit)

    from server.api.photos import _photo_to_response
    return {
        "face": _face_to_response({
            "id": face.id,
            "name": face.name,
            "photo_count": face.photo_count,
            "cover_photo_id": None,
            "created_at": face.created_at.isoformat() if face.created_at else "",
        }),
        "photos": [_photo_to_response(p) for p in photos],
        "next_cursor": next_cursor,
    }


@router.patch("/{face_id}", response_model=FaceResponse)
def tag_face_endpoint(
    face_id: str,
    request: FaceTagRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Assign a name to a face cluster (tag a person)."""
    result = tag_face(face_id, request.name, session)
    if not result:
        raise HTTPException(status_code=404, detail="Face not found")
    return FaceResponse(
        id=result["id"],
        name=result["name"],
        photo_count=result["photo_count"],
        cover_photo_id=None,
    )


@router.post("/{face_id}/merge", response_model=FaceMergeResponse)
def merge_faces_endpoint(
    face_id: str,
    request: FaceMergeRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Merge other face clusters into this one (same person)."""
    result = merge_faces(face_id, request.source_face_ids, session)
    if not result:
        raise HTTPException(status_code=404, detail="Target face not found")
    return FaceMergeResponse(**result)


@router.post("/recluster", response_model=FaceReclusterResponse)
def recluster_endpoint(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Re-run face clustering to merge similar faces (admin action)."""
    result = recluster_faces(session)
    return FaceReclusterResponse(**result)


@router.get("/status", response_model=AIStatusResponse)
def ai_status(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get AI processing status."""
    from server.ai.worker import ai_worker

    total_faces = session.exec(
        select(func.count()).select_from(Face)
    ).one()
    named_faces = session.exec(
        select(func.count()).select_from(Face).where(Face.name != None)  # noqa: E711
    ).one()
    total_pf = session.exec(
        select(func.count()).select_from(PhotoFace)
    ).one()

    return AIStatusResponse(
        ai_available=ai_worker.available,
        queue_size=ai_worker.queue_size,
        total_faces=total_faces,
        named_faces=named_faces,
        total_photo_faces=total_pf,
    )
