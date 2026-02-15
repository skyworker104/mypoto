"""Photo API endpoints."""

from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile, status
from fastapi.responses import FileResponse
from sqlmodel import Session

from sqlmodel import col, select

from server.api.deps import get_current_user
from server.config import settings
from server.database import get_session
from server.models.photo import Photo
from server.models.user import User
from server.schemas.photo import (
    PhotoBatchRequest,
    PhotoBatchResponse,
    PhotoCheckRequest,
    PhotoCheckResponse,
    PhotoListResponse,
    PhotoResponse,
    PhotoUpdateRequest,
    PhotoUploadResponse,
)
from server.services.photo_service import (
    admin_delete_photo,
    batch_action,
    check_duplicates,
    get_photo_timeline,
    soft_delete_photo,
    upload_photo,
)

router = APIRouter(prefix="/photos", tags=["photos"])


def _resolve_uploaders(photos: list[Photo], session: Session) -> dict[str, str]:
    """Resolve user_id -> nickname for a batch of photos."""
    user_ids = list({p.user_id for p in photos})
    if not user_ids:
        return {}
    users = session.exec(select(User).where(col(User.id).in_(user_ids))).all()
    return {u.id: u.nickname or "Unknown" for u in users}


def _photo_to_response(p: Photo, uploaded_by: str | None = None) -> PhotoResponse:
    return PhotoResponse(
        id=p.id,
        user_id=p.user_id,
        uploaded_by=uploaded_by,
        file_hash=p.file_hash,
        file_size=p.file_size,
        mime_type=p.mime_type,
        width=p.width,
        height=p.height,
        taken_at=p.taken_at.isoformat() if p.taken_at else None,
        latitude=p.latitude,
        longitude=p.longitude,
        location_name=p.location_name,
        camera_make=p.camera_make,
        camera_model=p.camera_model,
        ai_scene=p.ai_scene,
        exif_data=p.exif_data,
        description=p.description,
        is_favorite=bool(p.is_favorite),
        is_video=bool(p.is_video),
        duration=p.duration,
        created_at=p.created_at.isoformat() if p.created_at else "",
        thumb_small_url=f"/api/v1/photos/{p.id}/thumb?size=small",
        thumb_medium_url=f"/api/v1/photos/{p.id}/thumb?size=medium",
    )


@router.post("/check", response_model=PhotoCheckResponse)
def check_photo_hashes(
    request: PhotoCheckRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Check which file hashes already exist (for deduplication before upload)."""
    result = check_duplicates(request.hashes, session)
    return PhotoCheckResponse(**result)


@router.post("/upload", response_model=PhotoUploadResponse)
def upload(
    file: UploadFile = File(...),
    hash: str = Form(default=""),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Upload a photo or video file."""
    content_type = file.content_type or "application/octet-stream"

    file_data = file.file.read()
    if not file_data:
        raise HTTPException(status_code=400, detail="Empty file")

    # Max 100MB
    if len(file_data) > 100 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="File too large (max 100MB)")

    try:
        photo = upload_photo(
            file_data=file_data,
            filename=file.filename or "photo",
            content_type=content_type,
            user_id=user.id,
            session=session,
            provided_hash=hash if hash else None,
        )
    except ValueError as e:
        msg = str(e)
        if msg.startswith("duplicate:"):
            existing_id = msg.split(":")[1]
            return PhotoUploadResponse(
                photo_id=existing_id,
                thumb_url=f"/api/v1/photos/{existing_id}/thumb",
                status="duplicate",
            )
        raise HTTPException(status_code=400, detail=msg)

    # Enqueue for AI face detection
    from server.ai.worker import ai_worker
    ai_worker.enqueue(photo.id)

    return PhotoUploadResponse(
        photo_id=photo.id,
        thumb_url=f"/api/v1/photos/{photo.id}/thumb",
        status="uploaded",
    )


@router.get("", response_model=PhotoListResponse)
def list_photos(
    cursor: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
    user_id: str | None = Query(default=None),
    date_from: str | None = Query(default=None),
    date_to: str | None = Query(default=None),
    favorites: bool = Query(default=False),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """List photos in reverse chronological order (timeline)."""
    photos, next_cursor, total = get_photo_timeline(
        session=session,
        user_id=user_id,
        cursor=cursor,
        limit=limit,
        date_from=date_from,
        date_to=date_to,
        favorites_only=favorites,
    )
    nickname_map = _resolve_uploaders(photos, session)
    return PhotoListResponse(
        photos=[_photo_to_response(p, nickname_map.get(p.user_id)) for p in photos],
        next_cursor=next_cursor,
        total_count=total,
    )


@router.get("/{photo_id}", response_model=PhotoResponse)
def get_photo(
    photo_id: str,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get photo details."""
    photo = session.get(Photo, photo_id)
    if not photo or photo.status != "active":
        raise HTTPException(status_code=404, detail="Photo not found")
    uploader = session.get(User, photo.user_id)
    return _photo_to_response(photo, uploader.nickname if uploader else None)


@router.get("/{photo_id}/file")
def get_photo_file(
    photo_id: str,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Download the original photo file."""
    photo = session.get(Photo, photo_id)
    if not photo or photo.status != "active":
        raise HTTPException(status_code=404, detail="Photo not found")

    file_path = Path(photo.file_path)
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="File not found on disk")

    return FileResponse(
        path=str(file_path),
        media_type=photo.mime_type,
        filename=file_path.name,
    )


@router.get("/{photo_id}/thumb")
def get_thumbnail(
    photo_id: str,
    size: str = Query(default="small", regex="^(small|medium)$"),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Download a thumbnail (small=200x200, medium=800x800)."""
    photo = session.get(Photo, photo_id)
    if not photo or photo.status != "active":
        raise HTTPException(status_code=404, detail="Photo not found")

    # Build thumb path
    hash_prefix = photo.file_hash[:16]
    thumb_path = settings.thumbnail_dir / size / f"{hash_prefix}.webp"

    if not thumb_path.exists():
        raise HTTPException(status_code=404, detail="Thumbnail not found")

    return FileResponse(path=str(thumb_path), media_type="image/webp")


@router.patch("/{photo_id}", response_model=PhotoResponse)
def update_photo(
    photo_id: str,
    request: PhotoUpdateRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Update photo properties (favorite, location name)."""
    photo = session.get(Photo, photo_id)
    if not photo or photo.status != "active":
        raise HTTPException(status_code=404, detail="Photo not found")

    if request.is_favorite is not None:
        photo.is_favorite = request.is_favorite
    if request.location_name is not None:
        photo.location_name = request.location_name
    if request.description is not None:
        photo.description = request.description

    session.add(photo)
    session.commit()
    session.refresh(photo)
    uploader = session.get(User, photo.user_id)
    return _photo_to_response(photo, uploader.nickname if uploader else None)


@router.delete("/{photo_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_photo(
    photo_id: str,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Soft delete a photo. Admin can delete any; member only own."""
    if user.role == "admin":
        if not admin_delete_photo(photo_id, session):
            raise HTTPException(status_code=404, detail="Photo not found")
    else:
        if not soft_delete_photo(photo_id, user.id, session):
            raise HTTPException(status_code=404, detail="Photo not found")


@router.post("/batch", response_model=PhotoBatchResponse)
def batch_photos(
    request: PhotoBatchRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Perform batch operations on multiple photos."""
    if request.action not in ("delete", "favorite", "unfavorite"):
        raise HTTPException(status_code=400, detail="Invalid action")

    success, failed = batch_action(
        request.action, request.photo_ids, user.id, session,
        is_admin=(user.role == "admin"),
    )
    return PhotoBatchResponse(success_count=success, failed_count=failed)
