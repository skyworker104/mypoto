"""Scene classification service - manage scene tags on photos."""

import json
import logging

from sqlmodel import Session, select, col, func

from server.models.photo import Photo

logger = logging.getLogger(__name__)


def get_scenes(session: Session, limit: int = 50) -> list[dict]:
    """Get all unique scene labels with photo counts."""
    rows = list(session.exec(
        select(Photo.ai_scene, func.count().label("count"))
        .where(
            Photo.status == "active",
            Photo.ai_scene != None,  # noqa: E711
        )
        .group_by(Photo.ai_scene)
        .order_by(func.count().desc())
        .limit(limit)
    ).all())
    return [{"scene": row[0], "count": row[1]} for row in rows]


def get_scene_photos(
    scene: str,
    session: Session,
    cursor: str | None = None,
    limit: int = 50,
) -> tuple[list[dict], str | None]:
    """Get photos for a specific scene with cursor pagination."""
    query = select(Photo).where(
        Photo.status == "active",
        Photo.ai_scene == scene,
    ).order_by(col(Photo.taken_at).desc())

    if cursor:
        query = query.where(Photo.taken_at < cursor)

    query = query.limit(limit + 1)
    photos = list(session.exec(query).all())

    next_cursor = None
    if len(photos) > limit:
        photos = photos[:limit]
        last = photos[-1]
        next_cursor = (last.taken_at or last.created_at).isoformat()

    result = []
    for p in photos:
        result.append({
            "id": p.id,
            "thumb_url": f"/api/v1/photos/{p.id}/thumb",
            "taken_at": p.taken_at.isoformat() if p.taken_at else None,
            "ai_scene": p.ai_scene,
            "ai_tags": json.loads(p.ai_tags) if p.ai_tags else [],
        })

    return result, next_cursor


def get_all_tags(session: Session, limit: int = 100) -> list[dict]:
    """Get all unique AI tags with counts.

    Since ai_tags is a JSON array stored as text, we fetch all photos
    and aggregate in Python.
    """
    photos = list(session.exec(
        select(Photo.ai_tags).where(
            Photo.status == "active",
            Photo.ai_tags != None,  # noqa: E711
        )
    ).all())

    tag_counts: dict[str, int] = {}
    for tags_json in photos:
        try:
            tags = json.loads(tags_json)
            for tag in tags:
                tag_counts[tag] = tag_counts.get(tag, 0) + 1
        except (json.JSONDecodeError, TypeError):
            continue

    sorted_tags = sorted(tag_counts.items(), key=lambda x: x[1], reverse=True)
    return [{"tag": t, "count": c} for t, c in sorted_tags[:limit]]


def search_by_scene(query: str, session: Session, limit: int = 50) -> list[Photo]:
    """Search photos by scene label or tag."""
    # Try exact scene match first
    photos = list(session.exec(
        select(Photo).where(
            Photo.status == "active",
            Photo.ai_scene == query,
        ).order_by(col(Photo.taken_at).desc()).limit(limit)
    ).all())

    if photos:
        return photos

    # Try tag search (contains in JSON array)
    photos = list(session.exec(
        select(Photo).where(
            Photo.status == "active",
            col(Photo.ai_tags).contains(query),
        ).order_by(col(Photo.taken_at).desc()).limit(limit)
    ).all())

    return photos
