"""Image processing: thumbnails, HEIC conversion, hashing."""

import hashlib
from io import BytesIO
from pathlib import Path

from PIL import Image

# Register HEIF/HEIC support
try:
    from pillow_heif import register_heif_opener
    register_heif_opener()
except ImportError:
    pass

THUMB_SMALL = (200, 200)
THUMB_MEDIUM = (800, 800)


def compute_file_hash(data: bytes) -> str:
    """Compute SHA-256 hash of file data."""
    return hashlib.sha256(data).hexdigest()


def generate_thumbnails(
    image_data: bytes,
    thumb_dir: Path,
    photo_id: str,
) -> dict[str, str]:
    """Generate small and medium WebP thumbnails.

    Returns dict with 'small' and 'medium' relative paths.
    """
    img = Image.open(BytesIO(image_data))

    # Auto-rotate based on EXIF orientation
    img = _auto_orient(img)

    results = {}
    for label, size in [("small", THUMB_SMALL), ("medium", THUMB_MEDIUM)]:
        sub_dir = thumb_dir / label
        sub_dir.mkdir(parents=True, exist_ok=True)

        thumb = img.copy()
        thumb.thumbnail(size, Image.LANCZOS)

        # Convert to RGB if needed (RGBA, P, etc.)
        if thumb.mode not in ("RGB", "L"):
            thumb = thumb.convert("RGB")

        out_path = sub_dir / f"{photo_id}.webp"
        thumb.save(out_path, "WEBP", quality=80)
        results[label] = str(out_path)

    return results


def get_image_dimensions(image_data: bytes) -> tuple[int, int]:
    """Return (width, height) of an image."""
    img = Image.open(BytesIO(image_data))
    img = _auto_orient(img)
    return img.size


def _auto_orient(img: Image.Image) -> Image.Image:
    """Auto-rotate image based on EXIF orientation tag."""
    try:
        exif = img.getexif()
        orientation = exif.get(0x0112)  # Orientation tag
        if orientation == 3:
            img = img.rotate(180, expand=True)
        elif orientation == 6:
            img = img.rotate(270, expand=True)
        elif orientation == 8:
            img = img.rotate(90, expand=True)
    except Exception:
        pass
    return img
