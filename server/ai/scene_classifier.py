"""Scene classification for photos.

Uses EXIF metadata + lightweight image analysis for local classification.
Supports optional cloud API (Google Vision) for accurate classification.

Categories (Korean labels):
  해변(beach), 산(mountain), 음식(food), 건물(building),
  실내(indoor), 야외(outdoor), 자연(nature), 도시(city),
  야경(night), 인물(portrait), 풍경(landscape)
"""

import json
import logging
from pathlib import Path

import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)

# Scene categories with Korean labels
SCENE_CATEGORIES = {
    "beach": "해변",
    "mountain": "산",
    "food": "음식",
    "building": "건물",
    "indoor": "실내",
    "outdoor": "야외",
    "nature": "자연",
    "city": "도시",
    "night": "야경",
    "portrait": "인물",
    "landscape": "풍경",
}

# Reverse mapping
SCENE_KO_TO_EN = {v: k for k, v in SCENE_CATEGORIES.items()}


def classify_scene_local(
    image: Image.Image,
    exif_data: dict | None = None,
) -> tuple[str, list[str]]:
    """Classify scene using EXIF + image analysis heuristics.

    Returns (scene_label, tags_list).
    """
    tags: list[str] = []
    scores: dict[str, float] = {k: 0.0 for k in SCENE_CATEGORIES}

    # --- EXIF-based hints ---
    if exif_data:
        _score_from_exif(exif_data, scores, tags)

    # --- Image analysis ---
    _score_from_image(image, scores, tags)

    # Pick top scene
    scene = max(scores, key=scores.get)  # type: ignore[arg-type]
    if scores[scene] <= 0:
        scene = "outdoor"  # default

    # Add scene as tag
    ko_label = SCENE_CATEGORIES[scene]
    if ko_label not in tags:
        tags.insert(0, ko_label)

    return scene, tags


def _score_from_exif(exif_data: dict, scores: dict, tags: list):
    """Score scenes based on EXIF metadata."""
    # Flash used → likely indoor
    if exif_data.get("flash"):
        scores["indoor"] += 2.0
        tags.append("플래시")

    # Focal length hints
    focal = exif_data.get("focal_length")
    if focal:
        if focal <= 24:
            scores["landscape"] += 1.5
            scores["outdoor"] += 0.5
        elif focal >= 85:
            scores["portrait"] += 2.0
            tags.append("인물")

    # ISO hints (high ISO → indoor or night)
    iso = exif_data.get("iso")
    if iso:
        if iso >= 1600:
            scores["night"] += 1.5
            scores["indoor"] += 1.0
        elif iso <= 200:
            scores["outdoor"] += 1.0

    # Exposure time (long exposure → night/landscape)
    exposure = exif_data.get("exposure_time")
    if exposure and isinstance(exposure, (int, float)):
        if exposure >= 1.0:
            scores["night"] += 2.0
            scores["landscape"] += 1.0
        elif exposure <= 1 / 500:
            scores["outdoor"] += 0.5

    # Time of day from taken_at
    taken_at = exif_data.get("taken_at")
    if taken_at:
        try:
            from datetime import datetime

            if isinstance(taken_at, str):
                dt = datetime.fromisoformat(taken_at)
            elif isinstance(taken_at, datetime):
                dt = taken_at
            else:
                dt = None
            if dt:
                hour = dt.hour
                if hour < 6 or hour >= 20:
                    scores["night"] += 1.5
                elif 10 <= hour <= 14:
                    scores["outdoor"] += 0.5
        except (ValueError, AttributeError):
            pass


def _score_from_image(image: Image.Image, scores: dict, tags: list):
    """Score scenes based on image pixel analysis."""
    try:
        img = image.convert("RGB")
        # Resize for fast analysis
        img = img.resize((64, 64), Image.LANCZOS)
        arr = np.array(img, dtype=np.float32)

        # Average color channels
        r_mean = arr[:, :, 0].mean()
        g_mean = arr[:, :, 1].mean()
        b_mean = arr[:, :, 2].mean()
        brightness = arr.mean()

        # Aspect ratio
        w, h = image.size
        aspect = w / max(h, 1)

        # --- Color-based heuristics ---

        # Blue-dominant top half → sky → outdoor/landscape
        top_half = arr[: 32, :, :]
        top_r = top_half[:, :, 0].mean()
        top_g = top_half[:, :, 1].mean()
        top_b = top_half[:, :, 2].mean()
        if top_b > 140 and top_b > top_r * 1.1 and top_b > top_g * 1.05:
            scores["outdoor"] += 2.0
            scores["landscape"] += 1.5
            tags.append("하늘")

        # Very blue overall → beach/ocean
        if b_mean > 140 and b_mean > r_mean * 1.2 and b_mean > g_mean * 1.1:
            scores["beach"] += 2.0
            tags.append("바다")

        # Green-dominant → nature/mountain
        if g_mean > r_mean * 1.1 and g_mean > b_mean * 1.1 and g_mean > 100:
            scores["nature"] += 2.5
            scores["mountain"] += 1.5
            tags.append("녹색")

        # Warm colors (orange/brown) → food
        if r_mean > 140 and g_mean > 90 and b_mean < 100:
            scores["food"] += 2.0

        # Dark overall → night
        if brightness < 60:
            scores["night"] += 3.0
            tags.append("어두움")
        elif brightness < 100:
            scores["night"] += 1.0
            scores["indoor"] += 0.5

        # Very bright, low saturation → indoor (fluorescent light)
        saturation = arr.std(axis=2).mean()
        if brightness >= 170 and saturation < 30:
            scores["indoor"] += 2.0

        # High saturation, lots of color variety → city
        if saturation > 60 and brightness > 100:
            scores["city"] += 1.0

        # Landscape format + outdoor hints
        if aspect > 1.5:
            scores["landscape"] += 1.0
        elif aspect < 0.8:
            scores["portrait"] += 1.0

        # Bottom half green + top half blue → classic landscape
        bottom_half = arr[32:, :, :]
        bot_g = bottom_half[:, :, 1].mean()
        bot_r = bottom_half[:, :, 0].mean()
        bot_b = bottom_half[:, :, 2].mean()
        if (bot_g > bot_r * 1.1 and bot_g > bot_b * 1.1
                and top_b > top_r * 1.05):
            scores["landscape"] += 2.0
            scores["nature"] += 1.0

    except Exception as e:
        logger.debug("Image analysis failed: %s", e)


def get_scene_categories() -> dict[str, str]:
    """Return all scene categories {en: ko}."""
    return dict(SCENE_CATEGORIES)
