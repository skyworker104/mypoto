"""Reverse geocoding: GPS coordinates -> place name.

Uses Nominatim (OpenStreetMap) with local caching to minimize API calls.
"""

import json
import logging
import time
import urllib.request
from pathlib import Path

from server.config import settings

logger = logging.getLogger(__name__)

# In-memory cache: (lat_round, lon_round) -> place_name
_cache: dict[tuple[float, float], str] = {}

# File-based persistent cache
_CACHE_FILE = settings.data_dir / "geocache.json"

# Nominatim rate limit: max 1 request per second
_last_request_time = 0.0
_RATE_LIMIT_SECONDS = 1.1

# Round GPS to ~100m precision for cache key
_GPS_PRECISION = 3  # 3 decimal places ≈ 111m


def _load_cache():
    """Load cache from disk."""
    global _cache
    if _CACHE_FILE.exists():
        try:
            data = json.loads(_CACHE_FILE.read_text(encoding="utf-8"))
            _cache = {
                (float(k.split(",")[0]), float(k.split(",")[1])): v
                for k, v in data.items()
            }
            logger.info("Geocache loaded: %d entries", len(_cache))
        except Exception as e:
            logger.warning("Failed to load geocache: %s", e)


def _save_cache():
    """Persist cache to disk."""
    try:
        data = {f"{lat},{lon}": name for (lat, lon), name in _cache.items()}
        _CACHE_FILE.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    except Exception as e:
        logger.warning("Failed to save geocache: %s", e)


def _round_gps(lat: float, lon: float) -> tuple[float, float]:
    return round(lat, _GPS_PRECISION), round(lon, _GPS_PRECISION)


def reverse_geocode(lat: float, lon: float) -> str | None:
    """Convert GPS coordinates to a human-readable place name.

    Returns place name string or None if lookup fails.
    Uses Nominatim with caching.
    """
    global _last_request_time

    if not _cache:
        _load_cache()

    # Check cache
    key = _round_gps(lat, lon)
    if key in _cache:
        return _cache[key]

    # Rate limiting
    now = time.time()
    elapsed = now - _last_request_time
    if elapsed < _RATE_LIMIT_SECONDS:
        time.sleep(_RATE_LIMIT_SECONDS - elapsed)

    # Call Nominatim
    url = (
        f"https://nominatim.openstreetmap.org/reverse"
        f"?lat={lat}&lon={lon}&format=json&zoom=14"
        f"&accept-language=ko&addressdetails=1"
    )
    headers = {"User-Agent": "PhotoNest/1.0 (self-hosted family photo server)"}
    req = urllib.request.Request(url, headers=headers)

    try:
        _last_request_time = time.time()
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))

        place_name = _extract_place_name(data)
        if place_name:
            _cache[key] = place_name
            # Save periodically (every 10 new entries)
            if len(_cache) % 10 == 0:
                _save_cache()
            return place_name

    except Exception as e:
        logger.warning("Geocoding failed for (%s, %s): %s", lat, lon, e)

    return None


def _extract_place_name(data: dict) -> str | None:
    """Extract a meaningful place name from Nominatim response."""
    address = data.get("address", {})

    # Priority: city/town > county > state
    parts = []

    # Country
    country = address.get("country")

    # State/Province
    state = address.get("state") or address.get("province")

    # City-level
    city = (
        address.get("city")
        or address.get("town")
        or address.get("village")
        or address.get("municipality")
    )

    # District/suburb
    district = (
        address.get("suburb")
        or address.get("borough")
        or address.get("district")
        or address.get("quarter")
    )

    if city:
        parts.append(city)
    elif state:
        parts.append(state)
    elif country:
        parts.append(country)

    if district and city:
        parts.append(district)

    return " ".join(parts) if parts else data.get("display_name", "").split(",")[0]


def batch_geocode_photos(session) -> int:
    """Geocode all photos that have GPS but no location_name.

    Returns count of photos updated.
    """
    from sqlmodel import select, col
    from server.models.photo import Photo

    photos = list(session.exec(
        select(Photo).where(
            Photo.status == "active",
            Photo.latitude != None,  # noqa: E711
            Photo.longitude != None,  # noqa: E711
            Photo.location_name == None,  # noqa: E711
        ).limit(100)  # Process in batches
    ).all())

    updated = 0
    for photo in photos:
        if photo.latitude is not None and photo.longitude is not None:
            name = reverse_geocode(photo.latitude, photo.longitude)
            if name:
                photo.location_name = name
                session.add(photo)
                updated += 1

    if updated:
        session.commit()
        _save_cache()
        logger.info("Geocoded %d photos", updated)

    return updated
