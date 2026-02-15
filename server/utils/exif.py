"""EXIF metadata extraction from images."""

import json
from datetime import datetime
from io import BytesIO
from typing import Any, Optional

from PIL import Image
from PIL.ExifTags import TAGS, GPSTAGS


def extract_exif(image_data: bytes) -> dict[str, Any]:
    """Extract EXIF metadata from image bytes.

    Returns a dict with parsed fields:
      taken_at, latitude, longitude, camera_make, camera_model, exif_json
    """
    result: dict[str, Any] = {
        "taken_at": None,
        "latitude": None,
        "longitude": None,
        "camera_make": None,
        "camera_model": None,
        "exif_json": None,
    }

    try:
        img = Image.open(BytesIO(image_data))
        exif_data = img.getexif()
    except Exception:
        return result

    if not exif_data:
        return result

    decoded: dict[str, Any] = {}
    for tag_id, value in exif_data.items():
        tag_name = TAGS.get(tag_id, str(tag_id))
        # Convert bytes/non-serializable to string
        if isinstance(value, bytes):
            try:
                value = value.decode("utf-8", errors="replace")
            except Exception:
                value = str(value)
        decoded[tag_name] = value

    # Camera info
    result["camera_make"] = _str_or_none(decoded.get("Make"))
    result["camera_model"] = _str_or_none(decoded.get("Model"))

    # Date taken
    date_str = decoded.get("DateTimeOriginal") or decoded.get("DateTime")
    if date_str and isinstance(date_str, str):
        result["taken_at"] = _parse_exif_date(date_str)

    # GPS
    gps_info = _extract_gps(exif_data)
    if gps_info:
        result["latitude"] = gps_info[0]
        result["longitude"] = gps_info[1]

    # Store full EXIF as JSON (only serializable fields)
    safe = {}
    for k, v in decoded.items():
        try:
            json.dumps(v)
            safe[k] = v
        except (TypeError, ValueError):
            safe[k] = str(v)
    result["exif_json"] = json.dumps(safe, ensure_ascii=False)

    return result


def _extract_gps(exif_data) -> Optional[tuple[float, float]]:
    """Extract GPS coordinates from EXIF data."""
    try:
        gps_ifd = exif_data.get_ifd(0x8825)  # GPSInfo IFD
        if not gps_ifd:
            return None

        gps = {}
        for tag_id, value in gps_ifd.items():
            tag_name = GPSTAGS.get(tag_id, str(tag_id))
            gps[tag_name] = value

        lat = _gps_to_decimal(
            gps.get("GPSLatitude"), gps.get("GPSLatitudeRef", "N")
        )
        lon = _gps_to_decimal(
            gps.get("GPSLongitude"), gps.get("GPSLongitudeRef", "E")
        )
        if lat is not None and lon is not None:
            return (lat, lon)
    except Exception:
        pass
    return None


def _gps_to_decimal(coords, ref: str) -> Optional[float]:
    """Convert GPS DMS coordinates to decimal degrees."""
    if not coords or len(coords) != 3:
        return None
    try:
        degrees = float(coords[0])
        minutes = float(coords[1])
        seconds = float(coords[2])
        decimal = degrees + minutes / 60.0 + seconds / 3600.0
        if ref in ("S", "W"):
            decimal = -decimal
        return round(decimal, 6)
    except (ValueError, TypeError):
        return None


def _parse_exif_date(date_str: str) -> Optional[datetime]:
    """Parse EXIF date string (e.g., '2026:01:15 14:30:00') to datetime object."""
    for fmt in ("%Y:%m:%d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y:%m:%d"):
        try:
            return datetime.strptime(date_str.strip(), fmt)
        except ValueError:
            continue
    return None


def _str_or_none(val) -> Optional[str]:
    if val is None:
        return None
    s = str(val).strip()
    return s if s else None
