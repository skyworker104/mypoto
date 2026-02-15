"""Memory/recall service: "N years ago today", weekly best, notifications.

Generates memory cards from photo history.
"""

import logging
import random
from datetime import datetime, timedelta

from sqlmodel import Session, select, col, func

from server.models.photo import Photo

logger = logging.getLogger(__name__)


def get_memories_today(session: Session, limit: int = 20) -> list[dict]:
    """Get "on this day" memory photos from past years.

    Returns list of memory groups: [{year, years_ago, photos}]
    """
    now = datetime.utcnow()
    memories = []

    for years_ago in range(1, 20):
        try:
            target_date = now.replace(year=now.year - years_ago)
        except ValueError:
            # Feb 29 in non-leap year
            continue

        start = target_date.replace(hour=0, minute=0, second=0, microsecond=0)
        end = target_date.replace(hour=23, minute=59, second=59)

        photos = list(session.exec(
            select(Photo).where(
                Photo.status == "active",
                Photo.taken_at >= start,
                Photo.taken_at <= end,
            ).order_by(col(Photo.taken_at).asc()).limit(10)
        ).all())

        if photos:
            memories.append({
                "type": "on_this_day",
                "year": now.year - years_ago,
                "years_ago": years_ago,
                "date": start.strftime("%Y-%m-%d"),
                "photo_count": len(photos),
                "photos": [
                    {
                        "id": p.id,
                        "thumb_url": f"/api/v1/photos/{p.id}/thumb",
                        "taken_at": p.taken_at.isoformat() if p.taken_at else None,
                        "location": p.location_name,
                    }
                    for p in photos
                ],
            })

    return memories[:limit]


def get_weekly_highlights(session: Session, limit: int = 10) -> list[dict]:
    """Get best photos from the past week (most recently viewed, favorites)."""
    week_ago = datetime.utcnow() - timedelta(days=7)

    # Get favorites from past week
    favorites = list(session.exec(
        select(Photo).where(
            Photo.status == "active",
            Photo.is_favorite == True,  # noqa: E712
            Photo.taken_at >= week_ago,
        ).order_by(col(Photo.taken_at).desc()).limit(limit)
    ).all())

    if len(favorites) < limit:
        # Fill with recent photos
        recent = list(session.exec(
            select(Photo).where(
                Photo.status == "active",
                Photo.taken_at >= week_ago,
            ).order_by(col(Photo.taken_at).desc()).limit(limit * 2)
        ).all())

        # Exclude already-selected favorites
        fav_ids = {p.id for p in favorites}
        candidates = [p for p in recent if p.id not in fav_ids]
        if candidates:
            random.shuffle(candidates)
            favorites.extend(candidates[:limit - len(favorites)])

    return [
        {
            "id": p.id,
            "thumb_url": f"/api/v1/photos/{p.id}/thumb",
            "taken_at": p.taken_at.isoformat() if p.taken_at else None,
            "is_favorite": p.is_favorite,
            "location": p.location_name,
        }
        for p in favorites[:limit]
    ]


def get_memory_summary(session: Session) -> dict:
    """Get summary stats for the memories section."""
    now = datetime.utcnow()
    total_photos = session.exec(
        select(func.count()).select_from(Photo).where(Photo.status == "active")
    ).one()

    # Count photos with memories (taken on this day in past years)
    memory_count = 0
    for years_ago in range(1, 20):
        try:
            target_date = now.replace(year=now.year - years_ago)
        except ValueError:
            continue
        start = target_date.replace(hour=0, minute=0, second=0, microsecond=0)
        end = target_date.replace(hour=23, minute=59, second=59)
        count = session.exec(
            select(func.count()).select_from(Photo).where(
                Photo.status == "active",
                Photo.taken_at >= start,
                Photo.taken_at <= end,
            )
        ).one()
        memory_count += count

    # Oldest photo
    oldest = session.exec(
        select(Photo.taken_at).where(
            Photo.status == "active",
            Photo.taken_at != None,  # noqa: E711
        ).order_by(Photo.taken_at.asc()).limit(1)  # type: ignore
    ).first()

    return {
        "total_photos": total_photos,
        "memories_today": memory_count,
        "oldest_photo_date": oldest.isoformat() if oldest else None,
    }
