"""EXIF metadata extraction from images."""

import json
import logging
from datetime import datetime
from io import BytesIO
from typing import Any, Optional

from PIL import Image
from PIL.ExifTags import TAGS, GPSTAGS

logger = logging.getLogger(__name__)


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
        if isinstance(value, bytes):
            try:
                value = value.decode("utf-8", errors="replace")
            except Exception:
                value = str(value)
        decoded[tag_name] = value

    # Also read ExifIFD (0x8769) for DateTimeOriginal, FocalLength, etc.
    try:
        exif_ifd = exif_data.get_ifd(0x8769)
        if exif_ifd:
            for tag_id, value in exif_ifd.items():
                tag_name = TAGS.get(tag_id, str(tag_id))
                if isinstance(value, bytes):
                    try:
                        value = value.decode("utf-8", errors="replace")
                    except Exception:
                        value = str(value)
                decoded[tag_name] = value
    except Exception:
        pass

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
    """Extract GPS coordinates from EXIF data.

    Tries multiple methods for Pillow version compatibility:
    1. get_ifd(0x8825) — Pillow 10.x+ IFD access
    2. Direct tag 0x8825 from exif_data — older Pillow / some JPEG files
    3. _getexif() fallback — legacy Pillow API
    """
    gps = _try_gps_ifd(exif_data)
    if gps is None:
        gps = _try_gps_tag_direct(exif_data)
    if gps is None:
        return None

    lat = _gps_to_decimal(
        gps.get("GPSLatitude"), gps.get("GPSLatitudeRef", "N")
    )
    lon = _gps_to_decimal(
        gps.get("GPSLongitude"), gps.get("GPSLongitudeRef", "E")
    )
    if lat is not None and lon is not None:
        logger.debug("GPS extracted: %.6f, %.6f", lat, lon)
        return (lat, lon)

    logger.debug("GPS tags found but could not parse coordinates: %s", list(gps.keys()))
    return None


def _try_gps_ifd(exif_data) -> Optional[dict]:
    """Method 1: get_ifd(0x8825) — Pillow 10.x+."""
    try:
        gps_ifd = exif_data.get_ifd(0x8825)
        if not gps_ifd:
            return None
        gps = {}
        for tag_id, value in gps_ifd.items():
            tag_name = GPSTAGS.get(tag_id, str(tag_id))
            gps[tag_name] = value
        if "GPSLatitude" in gps:
            return gps
    except Exception as e:
        logger.debug("get_ifd(0x8825) failed: %s", e)
    return None


def _try_gps_tag_direct(exif_data) -> Optional[dict]:
    """Method 2: Direct access to GPSInfo tag (0x8825) from exif dict."""
    try:
        # Some Pillow versions store GPSInfo as a dict directly in tag 0x8825
        gps_raw = exif_data.get(0x8825)
        if isinstance(gps_raw, dict):
            gps = {}
            for tag_id, value in gps_raw.items():
                tag_name = GPSTAGS.get(tag_id, str(tag_id))
                gps[tag_name] = value
            if "GPSLatitude" in gps:
                return gps
        elif isinstance(gps_raw, int):
            # gps_raw is an IFD pointer, try get_ifd with it
            pass
    except Exception as e:
        logger.debug("Direct GPS tag access failed: %s", e)
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
