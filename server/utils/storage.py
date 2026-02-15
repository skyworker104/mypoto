"""Storage utilities: path management, disk usage monitoring."""

import shutil
from datetime import datetime
from pathlib import Path

from server.config import settings


def get_photo_storage_path(taken_at: "str | datetime | None") -> Path:
    """Get the storage path for a photo based on its date.

    Structure: originals/YYYY/MM/DD/
    Falls back to current date if taken_at is not available.
    """
    if isinstance(taken_at, datetime):
        dt = taken_at
    elif taken_at:
        try:
            dt = datetime.fromisoformat(taken_at)
        except ValueError:
            dt = datetime.now()
    else:
        dt = datetime.now()

    path = settings.storage_dir / str(dt.year) / f"{dt.month:02d}" / f"{dt.day:02d}"
    path.mkdir(parents=True, exist_ok=True)
    return path


def get_storage_info() -> dict:
    """Get disk usage statistics for the storage directory."""
    usage = shutil.disk_usage(settings.storage_dir)
    return {
        "total_bytes": usage.total,
        "used_bytes": usage.used,
        "free_bytes": usage.free,
        "usage_percent": round(usage.used / usage.total * 100, 1),
    }
