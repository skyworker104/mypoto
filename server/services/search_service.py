"""Unified search service - search photos by person, place, date, text."""

from datetime import datetime, timedelta

from sqlmodel import Session, select, col, func

from server.models.photo import Face, Photo, PhotoFace
from server.services.face_service import search_by_person


def search_photos(
    query: str,
    session: Session,
    limit: int = 50,
) -> dict:
    """Unified search: tries person, place, and date matching.

    Returns dict with search results grouped by type.
    """
    results: dict = {
        "query": query,
        "persons": [],
        "places": [],
        "dates": [],
        "descriptions": [],
        "total": 0,
    }

    # 1. Search by person (face name)
    person_photos = search_by_person(query, session, limit=20)
    if person_photos:
        results["persons"] = [
            {"id": p.id, "taken_at": p.taken_at.isoformat() if p.taken_at else None}
            for p in person_photos
        ]

    # 2. Search by place (location_name)
    place_photos = list(session.exec(
        select(Photo).where(
            Photo.status == "active",
            col(Photo.location_name).contains(query),
        ).order_by(col(Photo.taken_at).desc()).limit(20)
    ).all())
    if place_photos:
        results["places"] = [
            {"id": p.id, "location": p.location_name, "taken_at": p.taken_at.isoformat() if p.taken_at else None}
            for p in place_photos
        ]

    # 3. Search by description
    desc_photos = list(session.exec(
        select(Photo).where(
            Photo.status == "active",
            col(Photo.description).contains(query),
        ).order_by(col(Photo.taken_at).desc()).limit(20)
    ).all())
    if desc_photos:
        results["descriptions"] = [
            {"id": p.id, "description": p.description, "taken_at": p.taken_at.isoformat() if p.taken_at else None}
            for p in desc_photos
        ]

    # 4. Search by date expression (Korean)
    date_photos = _search_by_date_expr(query, session)
    if date_photos:
        results["dates"] = [
            {"id": p.id, "taken_at": p.taken_at.isoformat() if p.taken_at else None}
            for p in date_photos
        ]

    results["total"] = (
        len(results["persons"]) + len(results["places"])
        + len(results["descriptions"]) + len(results["dates"])
    )
    return results


def search_places(session: Session, limit: int = 50) -> list[dict]:
    """Get all unique place names with photo counts."""
    # Use raw SQL-like approach for grouping
    photos = list(session.exec(
        select(Photo.location_name, func.count().label("count"))
        .where(
            Photo.status == "active",
            Photo.location_name != None,  # noqa: E711
        )
        .group_by(Photo.location_name)
        .order_by(func.count().desc())
        .limit(limit)
    ).all())

    return [{"place": row[0], "count": row[1]} for row in photos]


def _search_by_date_expr(expr: str, session: Session) -> list[Photo]:
    """Parse Korean date expressions and search photos."""
    now = datetime.utcnow()
    start = None
    end = None

    # Korean date expression parsing
    date_map = {
        "오늘": (now.replace(hour=0, minute=0, second=0), now),
        "어제": (
            (now - timedelta(days=1)).replace(hour=0, minute=0, second=0),
            (now - timedelta(days=1)).replace(hour=23, minute=59, second=59),
        ),
        "그제": (
            (now - timedelta(days=2)).replace(hour=0, minute=0, second=0),
            (now - timedelta(days=2)).replace(hour=23, minute=59, second=59),
        ),
        "이번 주": (
            (now - timedelta(days=now.weekday())).replace(hour=0, minute=0, second=0),
            now,
        ),
        "지난 주": (
            (now - timedelta(days=now.weekday() + 7)).replace(hour=0, minute=0, second=0),
            (now - timedelta(days=now.weekday())).replace(hour=0, minute=0, second=0),
        ),
        "이번 달": (now.replace(day=1, hour=0, minute=0, second=0), now),
        "지난 달": (
            (now.replace(day=1) - timedelta(days=1)).replace(day=1, hour=0, minute=0, second=0),
            now.replace(day=1, hour=0, minute=0, second=0),
        ),
        "올해": (now.replace(month=1, day=1, hour=0, minute=0, second=0), now),
        "작년": (
            now.replace(year=now.year - 1, month=1, day=1, hour=0, minute=0, second=0),
            now.replace(year=now.year - 1, month=12, day=31, hour=23, minute=59, second=59),
        ),
        "재작년": (
            now.replace(year=now.year - 2, month=1, day=1, hour=0, minute=0, second=0),
            now.replace(year=now.year - 2, month=12, day=31, hour=23, minute=59, second=59),
        ),
    }

    if expr in date_map:
        start, end = date_map[expr]
    else:
        # Try "YYYY년" pattern
        import re
        year_match = re.match(r"(\d{4})년", expr)
        if year_match:
            year = int(year_match.group(1))
            start = datetime(year, 1, 1)
            end = datetime(year, 12, 31, 23, 59, 59)

        # Try "N월" pattern
        month_match = re.match(r"(\d{1,2})월", expr)
        if month_match:
            month = int(month_match.group(1))
            if 1 <= month <= 12:
                start = now.replace(month=month, day=1, hour=0, minute=0, second=0)
                if month == 12:
                    end = start.replace(day=31, hour=23, minute=59, second=59)
                else:
                    end = start.replace(month=month + 1) - timedelta(seconds=1)

    if start is None:
        return []

    return list(session.exec(
        select(Photo).where(
            Photo.status == "active",
            Photo.taken_at >= start,
            Photo.taken_at <= end,
        ).order_by(col(Photo.taken_at).desc()).limit(20)
    ).all())
