"""Map service - location-based photo browsing with clustering."""

import math
from sqlmodel import Session, select, col, func

from server.models.photo import Photo


def get_photo_locations(
    session: Session,
    bounds: tuple[float, float, float, float] | None = None,
    limit: int = 500,
) -> list[dict]:
    """Get individual photo locations, optionally filtered by map bounds.

    bounds = (lat_min, lat_max, lon_min, lon_max)
    """
    query = select(Photo).where(
        Photo.status == "active",
        Photo.latitude != None,  # noqa: E711
        Photo.longitude != None,  # noqa: E711
    )

    if bounds:
        lat_min, lat_max, lon_min, lon_max = bounds
        query = query.where(
            Photo.latitude >= lat_min,
            Photo.latitude <= lat_max,
            Photo.longitude >= lon_min,
            Photo.longitude <= lon_max,
        )

    query = query.order_by(col(Photo.taken_at).desc()).limit(limit)
    photos = list(session.exec(query).all())

    return [
        {
            "id": p.id,
            "lat": p.latitude,
            "lon": p.longitude,
            "location_name": p.location_name,
            "thumb_url": f"/api/v1/photos/{p.id}/thumb",
            "taken_at": p.taken_at.isoformat() if p.taken_at else None,
        }
        for p in photos
    ]


def get_location_clusters(
    session: Session,
    precision: int = 2,
    bounds: tuple[float, float, float, float] | None = None,
) -> list[dict]:
    """Cluster photos by rounded GPS coordinates.

    precision: decimal places for rounding (2 = ~1.1km grid, 1 = ~11km grid)
    """
    query = select(Photo).where(
        Photo.status == "active",
        Photo.latitude != None,  # noqa: E711
        Photo.longitude != None,  # noqa: E711
    )

    if bounds:
        lat_min, lat_max, lon_min, lon_max = bounds
        query = query.where(
            Photo.latitude >= lat_min,
            Photo.latitude <= lat_max,
            Photo.longitude >= lon_min,
            Photo.longitude <= lon_max,
        )

    photos = list(session.exec(query).all())

    # Cluster by rounded coordinates
    clusters: dict[tuple[float, float], list] = {}
    for p in photos:
        key = (
            round(p.latitude, precision),
            round(p.longitude, precision),
        )
        if key not in clusters:
            clusters[key] = []
        clusters[key].append(p)

    result = []
    for (lat, lon), cluster_photos in clusters.items():
        # Use most common location_name as label
        names = [p.location_name for p in cluster_photos if p.location_name]
        name = max(set(names), key=names.count) if names else None

        # Pick most recent photo as cover
        cover = max(cluster_photos, key=lambda p: p.taken_at or p.created_at)

        result.append({
            "lat": lat,
            "lon": lon,
            "count": len(cluster_photos),
            "location_name": name,
            "cover_thumb_url": f"/api/v1/photos/{cover.id}/thumb",
            "photo_ids": [p.id for p in cluster_photos[:10]],
        })

    # Sort by count descending
    result.sort(key=lambda c: c["count"], reverse=True)
    return result


def get_photos_near(
    session: Session,
    lat: float,
    lon: float,
    radius_km: float = 5.0,
    limit: int = 50,
) -> list[dict]:
    """Get photos near a GPS coordinate within radius_km."""
    # Approximate bounding box
    lat_delta = radius_km / 111.0
    lon_delta = radius_km / (111.0 * max(math.cos(math.radians(lat)), 0.01))

    photos = list(session.exec(
        select(Photo).where(
            Photo.status == "active",
            Photo.latitude >= lat - lat_delta,
            Photo.latitude <= lat + lat_delta,
            Photo.longitude >= lon - lon_delta,
            Photo.longitude <= lon + lon_delta,
        ).order_by(col(Photo.taken_at).desc()).limit(limit)
    ).all())

    return [
        {
            "id": p.id,
            "lat": p.latitude,
            "lon": p.longitude,
            "location_name": p.location_name,
            "thumb_url": f"/api/v1/photos/{p.id}/thumb",
            "taken_at": p.taken_at.isoformat() if p.taken_at else None,
        }
        for p in photos
    ]
