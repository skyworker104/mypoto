"""TV slideshow session management."""

import random
import time
from dataclasses import dataclass, field

from sqlmodel import Session, select, col

from server.models.photo import Photo


@dataclass
class SlideshowSession:
    """Active slideshow state."""
    active: bool = False
    photo_ids: list[str] = field(default_factory=list)
    current_index: int = 0
    interval_seconds: int = 10
    order: str = "random"  # 'random' | 'date'
    album_id: str | None = None
    paused: bool = False
    started_at: float = 0.0


# Module-level singleton
_session = SlideshowSession()


def start_slideshow(
    db: Session,
    interval: int = 10,
    order: str = "random",
    album_id: str | None = None,
    user_id: str | None = None,
    limit: int = 200,
) -> dict:
    """Start a new slideshow session."""
    global _session

    # Build photo query
    query = select(Photo.id).where(Photo.status == "active")
    if user_id:
        query = query.where(Photo.user_id == user_id)

    if album_id:
        from server.models.album import PhotoAlbum
        photo_ids_in_album = db.exec(
            select(PhotoAlbum.photo_id).where(PhotoAlbum.album_id == album_id)
        ).all()
        if photo_ids_in_album:
            query = query.where(col(Photo.id).in_(photo_ids_in_album))

    if order == "date":
        query = query.order_by(col(Photo.taken_at).desc())
    query = query.limit(limit)

    photo_ids = list(db.exec(query).all())

    if not photo_ids:
        return {"active": False, "message": "No photos found"}

    if order == "random":
        random.shuffle(photo_ids)

    _session = SlideshowSession(
        active=True,
        photo_ids=photo_ids,
        current_index=0,
        interval_seconds=interval,
        order=order,
        album_id=album_id,
        started_at=time.time(),
    )

    return {
        "active": True,
        "total_photos": len(photo_ids),
        "current_photo_id": photo_ids[0],
        "interval": interval,
    }


def stop_slideshow() -> dict:
    global _session
    _session = SlideshowSession()
    return {"active": False}


def control_slideshow(action: str) -> dict:
    """Control: next, prev, pause, resume."""
    if not _session.active:
        return {"active": False, "message": "No active slideshow"}

    if action == "next":
        _session.current_index = (_session.current_index + 1) % len(_session.photo_ids)
    elif action == "prev":
        _session.current_index = (_session.current_index - 1) % len(_session.photo_ids)
    elif action == "pause":
        _session.paused = True
    elif action == "resume":
        _session.paused = False

    return get_slideshow_status()


def get_slideshow_status() -> dict:
    if not _session.active:
        return {"active": False}

    return {
        "active": True,
        "paused": _session.paused,
        "current_index": _session.current_index,
        "current_photo_id": _session.photo_ids[_session.current_index],
        "total_photos": len(_session.photo_ids),
        "interval": _session.interval_seconds,
    }
