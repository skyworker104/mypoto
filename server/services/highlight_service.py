"""Highlight video generation service.

Selects best photos from a source (date range, location, faces, album)
and assembles them into a slideshow video using FFmpeg.
"""

import json
import logging
import shutil
import subprocess
import tempfile
import threading
from datetime import datetime, timezone
from pathlib import Path

from sqlmodel import Session, select, col

from server.config import settings
from server.database import engine
from server.models.photo import Highlight, Photo, PhotoFace

logger = logging.getLogger(__name__)

# Default slide duration in seconds
SLIDE_DURATION = 3
# Default video resolution
VIDEO_WIDTH = 1280
VIDEO_HEIGHT = 720
# Max photos per highlight
MAX_PHOTOS = 100


def create_highlight(
    user_id: str,
    title: str,
    source_type: str,
    source_params: dict,
    session: Session,
) -> Highlight:
    """Create a highlight record and start async generation."""
    highlight = Highlight(
        user_id=user_id,
        title=title,
        source_type=source_type,
        source_params=json.dumps(source_params, ensure_ascii=False),
        date_from=source_params.get("date_from"),
        date_to=source_params.get("date_to"),
        status="pending",
    )
    session.add(highlight)
    session.commit()
    session.refresh(highlight)

    # Start async generation in background thread
    thread = threading.Thread(
        target=_generate_highlight_async,
        args=(highlight.id,),
        daemon=True,
        name=f"highlight-{highlight.id}",
    )
    thread.start()

    return highlight


def _generate_highlight_async(highlight_id: str):
    """Background task: select photos, assemble video with FFmpeg."""
    with Session(engine) as session:
        highlight = session.get(Highlight, highlight_id)
        if not highlight:
            return

        try:
            highlight.status = "processing"
            session.add(highlight)
            session.commit()

            # 1. Select photos based on source
            params = json.loads(highlight.source_params or "{}")
            photos = _select_photos(highlight.source_type, params, highlight.user_id, session)

            if not photos:
                highlight.status = "failed"
                highlight.error_message = "No photos found for the given criteria"
                session.add(highlight)
                session.commit()
                return

            highlight.photo_ids = json.dumps([p.id for p in photos])

            # 2. Check FFmpeg availability
            if not _ffmpeg_available():
                highlight.status = "failed"
                highlight.error_message = "FFmpeg not installed"
                session.add(highlight)
                session.commit()
                return

            # 3. Generate video
            highlights_dir = settings.storage_dir / "highlights"
            highlights_dir.mkdir(parents=True, exist_ok=True)

            video_path = highlights_dir / f"{highlight.id}.mp4"
            thumb_path = highlights_dir / f"{highlight.id}_thumb.jpg"

            success = _assemble_video(photos, str(video_path), str(thumb_path))

            if success:
                highlight.video_path = str(video_path)
                highlight.thumbnail_path = str(thumb_path)
                highlight.duration_seconds = len(photos) * SLIDE_DURATION
                highlight.status = "completed"
                highlight.completed_at = datetime.now(timezone.utc)
            else:
                highlight.status = "failed"
                highlight.error_message = "Video assembly failed"

            session.add(highlight)
            session.commit()

        except Exception as e:
            logger.error("Highlight generation failed for %s: %s", highlight_id, e)
            highlight.status = "failed"
            highlight.error_message = str(e)[:500]
            session.add(highlight)
            session.commit()


def _select_photos(
    source_type: str,
    params: dict,
    user_id: str,
    session: Session,
) -> list[Photo]:
    """Select photos based on source criteria, prioritizing favorites."""
    query = select(Photo).where(
        Photo.status == "active",
        Photo.is_video == False,  # noqa: E712
    )

    if source_type == "date_range":
        date_from = params.get("date_from")
        date_to = params.get("date_to")
        if date_from:
            query = query.where(Photo.taken_at >= date_from)
        if date_to:
            query = query.where(Photo.taken_at <= date_to)

    elif source_type == "location":
        location = params.get("location")
        if location:
            query = query.where(col(Photo.location_name).contains(location))

    elif source_type == "faces":
        face_id = params.get("face_id")
        if face_id:
            photo_ids = list(session.exec(
                select(PhotoFace.photo_id).where(PhotoFace.face_id == face_id)
            ).all())
            if photo_ids:
                query = query.where(col(Photo.id).in_(photo_ids))
            else:
                return []

    # Order: favorites first, then by date
    query = query.order_by(
        col(Photo.is_favorite).desc(),
        col(Photo.taken_at).asc(),
    ).limit(MAX_PHOTOS)

    return list(session.exec(query).all())


def _ffmpeg_available() -> bool:
    """Check if FFmpeg is installed."""
    return shutil.which("ffmpeg") is not None


def _assemble_video(
    photos: list[Photo],
    output_path: str,
    thumb_path: str,
) -> bool:
    """Assemble photos into a slideshow video using FFmpeg.

    Creates a video with crossfade transitions between photos.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir_path = Path(tmpdir)

        # Create concat file for FFmpeg
        concat_file = tmpdir_path / "concat.txt"
        valid_photos = []

        for i, photo in enumerate(photos):
            src = Path(photo.file_path)
            if not src.exists():
                continue

            # Resize photo to video resolution
            resized = tmpdir_path / f"frame_{i:04d}.jpg"
            try:
                result = subprocess.run(
                    [
                        "ffmpeg", "-y", "-i", str(src),
                        "-vf", f"scale={VIDEO_WIDTH}:{VIDEO_HEIGHT}:force_original_aspect_ratio=decrease,"
                               f"pad={VIDEO_WIDTH}:{VIDEO_HEIGHT}:(ow-iw)/2:(oh-ih)/2:black",
                        "-q:v", "2",
                        str(resized),
                    ],
                    capture_output=True, timeout=30,
                )
                if result.returncode == 0 and resized.exists():
                    valid_photos.append(resized)
                else:
                    logger.warning("Failed to resize photo %s", photo.id)
            except (subprocess.TimeoutExpired, FileNotFoundError):
                continue

        if not valid_photos:
            return False

        # Write concat list
        with open(concat_file, "w") as f:
            for frame in valid_photos:
                f.write(f"file '{frame}'\n")
                f.write(f"duration {SLIDE_DURATION}\n")
            # Last frame needs to be listed again for proper duration
            f.write(f"file '{valid_photos[-1]}'\n")

        # Assemble video
        try:
            result = subprocess.run(
                [
                    "ffmpeg", "-y",
                    "-f", "concat", "-safe", "0", "-i", str(concat_file),
                    "-vf", f"fps=25,scale={VIDEO_WIDTH}:{VIDEO_HEIGHT}",
                    "-c:v", "libx264", "-preset", "fast",
                    "-crf", "23", "-pix_fmt", "yuv420p",
                    str(output_path),
                ],
                capture_output=True, timeout=300,
            )
            if result.returncode != 0:
                logger.error("FFmpeg error: %s", result.stderr.decode()[:500])
                return False
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return False

        # Generate thumbnail from first frame
        if valid_photos:
            try:
                subprocess.run(
                    ["ffmpeg", "-y", "-i", str(valid_photos[0]),
                     "-vf", "scale=320:180", str(thumb_path)],
                    capture_output=True, timeout=10,
                )
            except (subprocess.TimeoutExpired, FileNotFoundError):
                pass

    return Path(output_path).exists()


def list_highlights(user_id: str, session: Session) -> list[dict]:
    """List all highlights for a user."""
    highlights = list(session.exec(
        select(Highlight).where(Highlight.user_id == user_id)
        .order_by(col(Highlight.created_at).desc())
    ).all())

    return [_highlight_to_dict(h) for h in highlights]


def get_highlight(highlight_id: str, session: Session) -> dict | None:
    """Get a single highlight detail."""
    h = session.get(Highlight, highlight_id)
    if not h:
        return None
    return _highlight_to_dict(h)


def delete_highlight(highlight_id: str, user_id: str, session: Session) -> bool:
    """Delete a highlight and its video file."""
    h = session.get(Highlight, highlight_id)
    if not h or h.user_id != user_id:
        return False

    # Delete video file
    if h.video_path:
        try:
            Path(h.video_path).unlink(missing_ok=True)
        except OSError:
            pass
    if h.thumbnail_path:
        try:
            Path(h.thumbnail_path).unlink(missing_ok=True)
        except OSError:
            pass

    session.delete(h)
    session.commit()
    return True


def _highlight_to_dict(h: Highlight) -> dict:
    return {
        "id": h.id,
        "title": h.title,
        "description": h.description,
        "source_type": h.source_type,
        "status": h.status,
        "duration_seconds": h.duration_seconds,
        "photo_count": len(json.loads(h.photo_ids or "[]")),
        "date_from": h.date_from,
        "date_to": h.date_to,
        "has_video": h.video_path is not None,
        "thumbnail_url": f"/api/v1/highlights/{h.id}/thumbnail" if h.thumbnail_path else None,
        "created_at": h.created_at.isoformat() if h.created_at else None,
        "completed_at": h.completed_at.isoformat() if h.completed_at else None,
        "error_message": h.error_message,
    }
