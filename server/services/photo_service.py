"""Photo upload, storage, and retrieval business logic."""

from pathlib import Path

from sqlmodel import Session, select, col, func

from server.config import settings
from server.models.photo import Photo
from server.utils.exif import extract_exif
from server.utils.image import (
    compute_file_hash,
    generate_thumbnails,
    generate_video_thumbnails,
    get_image_dimensions,
    get_video_metadata,
)
from server.utils.storage import get_photo_storage_path

# Supported MIME types
IMAGE_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/heic": ".heic",
    "image/heif": ".heif",
    "image/gif": ".gif",
}

VIDEO_TYPES = {
    "video/mp4": ".mp4",
    "video/quicktime": ".mov",
    "video/x-msvideo": ".avi",
}

ALL_TYPES = {**IMAGE_TYPES, **VIDEO_TYPES}


def check_duplicates(hashes: list[str], session: Session) -> dict[str, list[str]]:
    """Check which file hashes already exist in the database."""
    existing = session.exec(
        select(Photo.file_hash).where(col(Photo.file_hash).in_(hashes))
    ).all()
    existing_set = set(existing)
    return {
        "existing": [h for h in hashes if h in existing_set],
        "new": [h for h in hashes if h not in existing_set],
    }


def upload_photo(
    file_data: bytes,
    filename: str,
    content_type: str,
    user_id: str,
    session: Session,
    provided_hash: str | None = None,
) -> Photo:
    """Process and store an uploaded photo.

    1. Compute hash & check duplicates
    2. Extract EXIF metadata
    3. Save original file
    4. Generate thumbnails
    5. Insert DB record
    """
    # 1. Hash check
    file_hash = provided_hash or compute_file_hash(file_data)
    existing = session.exec(
        select(Photo).where(Photo.file_hash == file_hash)
    ).first()
    if existing:
        raise ValueError(f"duplicate:{existing.id}")

    # 2. EXIF extraction (images only)
    exif_data = {}
    is_video = content_type in VIDEO_TYPES
    if not is_video:
        exif_data = extract_exif(file_data)

    # 3. Determine storage path and save original
    taken_at = exif_data.get("taken_at")
    storage_path = get_photo_storage_path(taken_at)
    ext = ALL_TYPES.get(content_type, Path(filename).suffix or ".bin")
    # Use hash prefix + original extension for filename
    out_filename = f"{file_hash[:16]}{ext}"
    file_path = storage_path / out_filename
    file_path.write_bytes(file_data)

    # 4. Get dimensions & generate thumbnails
    width, height = None, None
    thumb_path = None
    duration = None
    if is_video:
        # Video: extract metadata and thumbnails via FFmpeg
        try:
            meta = get_video_metadata(file_path)
            width = meta.get("width")
            height = meta.get("height")
            duration = meta.get("duration")
        except Exception:
            pass
        try:
            thumb_results = generate_video_thumbnails(
                file_path, settings.thumbnail_dir, file_hash[:16]
            )
            thumb_path = thumb_results.get("small")
        except Exception:
            pass
    else:
        # Image: extract dimensions and generate thumbnails from bytes
        try:
            width, height = get_image_dimensions(file_data)
        except Exception:
            pass
        try:
            thumb_results = generate_thumbnails(file_data, settings.thumbnail_dir, file_hash[:16])
            thumb_path = thumb_results.get("small")
        except Exception:
            pass

    # 5. Create DB record
    photo = Photo(
        user_id=user_id,
        file_hash=file_hash,
        file_path=str(file_path),
        thumb_path=thumb_path,
        file_size=len(file_data),
        mime_type=content_type,
        width=width,
        height=height,
        taken_at=taken_at,
        latitude=exif_data.get("latitude"),
        longitude=exif_data.get("longitude"),
        camera_make=exif_data.get("camera_make"),
        camera_model=exif_data.get("camera_model"),
        exif_data=exif_data.get("exif_json"),
        is_video=is_video,
        duration=duration,
    )
    session.add(photo)
    session.commit()
    session.refresh(photo)
    return photo


def get_photo_timeline(
    session: Session,
    user_id: str | None = None,
    cursor: str | None = None,
    limit: int = 50,
    date_from: str | None = None,
    date_to: str | None = None,
    favorites_only: bool = False,
) -> tuple[list[Photo], str | None, int]:
    """Fetch photos in reverse chronological order with cursor pagination.

    Returns (photos, next_cursor, total_count).
    """
    # Base query
    query = select(Photo).where(Photo.status == "active")

    if user_id:
        query = query.where(Photo.user_id == user_id)
    if favorites_only:
        query = query.where(Photo.is_favorite == True)  # noqa: E712
    if date_from:
        query = query.where(Photo.taken_at >= date_from)
    if date_to:
        query = query.where(Photo.taken_at <= date_to)

    # Count
    count_query = select(func.count()).select_from(query.subquery())
    total_count = session.exec(count_query).one()

    # Cursor pagination (taken_at DESC, then created_at DESC)
    if cursor:
        query = query.where(Photo.taken_at < cursor)

    query = query.order_by(col(Photo.taken_at).desc(), col(Photo.created_at).desc())
    query = query.limit(limit + 1)  # Fetch one extra to determine next_cursor

    photos = list(session.exec(query).all())

    next_cursor = None
    if len(photos) > limit:
        photos = photos[:limit]
        last = photos[-1]
        next_cursor = (last.taken_at or last.created_at).isoformat()

    return photos, next_cursor, total_count


def soft_delete_photo(photo_id: str, user_id: str, session: Session) -> bool:
    """Soft delete a photo (set status='deleted')."""
    photo = session.get(Photo, photo_id)
    if not photo or photo.user_id != user_id:
        return False
    photo.status = "deleted"
    session.add(photo)
    session.commit()
    return True


def admin_delete_photo(photo_id: str, session: Session) -> bool:
    """Admin delete - no ownership check."""
    photo = session.get(Photo, photo_id)
    if not photo or photo.status != "active":
        return False
    photo.status = "deleted"
    session.add(photo)
    session.commit()
    return True


def batch_action(
    action: str, photo_ids: list[str], user_id: str, session: Session,
    is_admin: bool = False,
) -> tuple[int, int]:
    """Perform batch action on multiple photos. Returns (success, failed)."""
    success = 0
    failed = 0
    for pid in photo_ids:
        photo = session.get(Photo, pid)
        if not photo or (not is_admin and photo.user_id != user_id):
            failed += 1
            continue
        if action == "delete":
            photo.status = "deleted"
        elif action == "favorite":
            photo.is_favorite = True
        elif action == "unfavorite":
            photo.is_favorite = False
        else:
            failed += 1
            continue
        session.add(photo)
        success += 1
    session.commit()
    return success, failed
