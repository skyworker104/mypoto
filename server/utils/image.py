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


def generate_video_thumbnails(
    video_path: str | Path,
    thumb_dir: Path,
    video_id: str,
) -> dict[str, str]:
    """Generate thumbnails from a video file using FFmpeg.

    Extracts a frame at 1 second and creates small/medium WebP thumbnails.
    Returns dict with 'small' and 'medium' paths, or empty if FFmpeg unavailable.
    """
    import json
    import subprocess

    results = {}
    video_path = str(video_path)

    for label, width in [("small", 200), ("medium", 800)]:
        sub_dir = thumb_dir / label
        sub_dir.mkdir(parents=True, exist_ok=True)
        out_path = sub_dir / f"{video_id}.webp"

        try:
            subprocess.run(
                [
                    "ffmpeg", "-i", video_path,
                    "-ss", "00:00:01", "-vframes", "1",
                    "-vf", f"scale={width}:-1",
                    "-y", str(out_path),
                ],
                capture_output=True,
                timeout=30,
            )
            if out_path.exists() and out_path.stat().st_size > 0:
                results[label] = str(out_path)
        except (FileNotFoundError, subprocess.TimeoutExpired):
            break  # FFmpeg not installed or timeout

    return results


def get_video_metadata(video_path: str | Path) -> dict:
    """Extract video duration and dimensions using ffprobe.

    Returns dict with 'duration', 'width', 'height' keys.
    """
    import json
    import subprocess

    video_path = str(video_path)
    try:
        result = subprocess.run(
            [
                "ffprobe", "-v", "quiet",
                "-print_format", "json",
                "-show_format", "-show_streams",
                video_path,
            ],
            capture_output=True,
            text=True,
            timeout=15,
        )
        data = json.loads(result.stdout)
        duration = float(data.get("format", {}).get("duration", 0))

        width, height = None, None
        for stream in data.get("streams", []):
            if stream.get("codec_type") == "video":
                width = stream.get("width")
                height = stream.get("height")
                break

        return {"duration": duration, "width": width, "height": height}
    except (FileNotFoundError, subprocess.TimeoutExpired, Exception):
        return {}


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
