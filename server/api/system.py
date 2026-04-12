"""System status API endpoints."""

import json
import logging
import socket
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import StreamingResponse
from sqlmodel import Session, func, select

from server.api.deps import get_current_user
from server.config import settings
from server.database import get_session
from server.models.photo import Photo
from server.models.user import User
from server.schemas.photo import SystemStatusResponse
from server.services.geocoding import batch_geocode_photos, reverse_geocode
from server.utils.exif import extract_exif
from server.utils.storage import get_storage_info

logger = logging.getLogger(__name__)


def _get_local_ip() -> str:
    """Get the actual local network IP (WiFi/LAN), not 0.0.0.0."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

router = APIRouter(prefix="/system", tags=["system"])


@router.get("/ping")
def system_ping():
    """Lightweight health check (no auth required)."""
    return {"status": "ok"}


@router.get("/pairing-status")
def pairing_status(request_obj: Request):
    """Get current pairing PIN status (localhost only)."""
    from server.services.auth_service import get_current_pin

    client_ip = request_obj.client.host if request_obj.client else ""
    if client_ip not in ("127.0.0.1", "::1", "localhost"):
        raise HTTPException(status_code=403, detail="Local access only")

    pin = get_current_pin()
    return {
        "active": pin is not None,
        "pin": pin,
    }


@router.get("/status", response_model=SystemStatusResponse)
def system_status(
    request_obj: Request,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get server system status: storage, photo count, etc."""
    storage = get_storage_info()

    # Photo stats
    photo_count = session.exec(
        select(func.count()).select_from(Photo).where(Photo.status == "active")
    ).one()
    total_size = session.exec(
        select(func.coalesce(func.sum(Photo.file_size), 0)).where(Photo.status == "active")
    ).one()

    # Build server URL using actual local network IP
    local_ip = _get_local_ip()
    scheme = request_obj.headers.get("x-forwarded-proto", "http")
    server_url = f"{scheme}://{local_ip}:{settings.port}"

    return SystemStatusResponse(
        server_name=settings.server_name,
        server_id=settings.server_id,
        server_url=server_url,
        version="0.1.0",
        photo_count=photo_count,
        total_size_bytes=total_size,
        storage_total_bytes=storage["total_bytes"],
        storage_used_bytes=storage["used_bytes"],
        storage_free_bytes=storage["free_bytes"],
        storage_usage_percent=storage["usage_percent"],
    )


@router.post("/reprocess-location")
def reprocess_location(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict:
    """Re-extract GPS from EXIF for all photos and run batch geocoding.

    1. Re-reads EXIF from original files to extract missing GPS data.
    2. Runs reverse geocoding for photos with GPS but no location_name.
    """
    from pathlib import Path

    from server.services.geocoding import batch_geocode_photos
    from server.utils.exif import extract_exif

    # Step 1: Re-extract GPS from ALL image photos (re-check even those without GPS)
    photos = list(session.exec(
        select(Photo).where(
            Photo.status == "active",
            Photo.is_video == False,  # noqa: E712
        )
    ).all())

    logger.info("Reprocess-location: checking %d photos for GPS", len(photos))

    gps_updated = 0
    for photo in photos:
        # Skip if already has GPS
        if photo.latitude is not None and photo.longitude is not None:
            continue
        file_path = Path(photo.file_path)
        if not file_path.exists():
            logger.debug("File not found: %s", photo.file_path)
            continue
        try:
            file_data = file_path.read_bytes()
            exif = extract_exif(file_data)
            lat = exif.get("latitude")
            lon = exif.get("longitude")
            if lat is not None and lon is not None:
                photo.latitude = lat
                photo.longitude = lon
                session.add(photo)
                gps_updated += 1
                logger.info("GPS found for photo %s: %.6f, %.6f", photo.id, lat, lon)
        except Exception as e:
            logger.warning("GPS re-extract failed for %s: %s", photo.id, e)

    if gps_updated:
        session.commit()
        logger.info("GPS re-extracted for %d photos", gps_updated)

    # Step 2: Batch geocode (photos with GPS but no location_name)
    geocoded = batch_geocode_photos(session)

    msg = f"GPS 추출: {gps_updated}장, 지명 변환: {geocoded}장"
    logger.info("Reprocess-location complete: %s", msg)
    return {
        "gps_extracted": gps_updated,
        "geocoded": geocoded,
        "message": msg,
    }


def _sse_event(data: dict) -> str:
    """Format a dict as an SSE data line."""
    return f"data: {json.dumps(data, ensure_ascii=False)}\n\n"


@router.get("/reprocess-location-stream")
def reprocess_location_stream(
    token: str = Query(..., description="JWT access token"),
    session: Session = Depends(get_session),
):
    """SSE stream: re-extract GPS from EXIF with per-photo progress.

    Uses query param `token` for auth since EventSource cannot set headers.
    """
    from server.utils.security import decode_token

    try:
        payload = decode_token(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")
    if payload.get("type") != "access":
        raise HTTPException(status_code=401, detail="Invalid token type")
    user = session.get(User, payload["sub"])
    if not user:
        raise HTTPException(status_code=401, detail="User not found")

    def _generate():
        # Phase 1: Collect target photos
        photos = list(session.exec(
            select(Photo).where(
                Photo.status == "active",
                Photo.is_video == False,  # noqa: E712
            )
        ).all())

        total = len(photos)
        yield _sse_event({
            "type": "start",
            "total": total,
            "message": f"총 {total}장의 사진을 검사합니다...",
        })

        gps_updated = 0
        gps_skipped = 0
        gps_failed = 0
        gps_not_found = 0

        for idx, photo in enumerate(photos):
            filename = Path(photo.file_path).name if photo.file_path else "unknown"
            progress = {"type": "progress", "current": idx + 1, "total": total, "filename": filename}

            # Already has GPS
            if photo.latitude is not None and photo.longitude is not None:
                gps_skipped += 1
                progress["status"] = "skip"
                progress["message"] = f"[{idx+1}/{total}] {filename} — GPS 있음 ({photo.latitude:.4f}, {photo.longitude:.4f}), 건너뜀"
                yield _sse_event(progress)
                continue

            file_path = Path(photo.file_path) if photo.file_path else None
            if not file_path or not file_path.exists():
                gps_failed += 1
                progress["status"] = "error"
                progress["message"] = f"[{idx+1}/{total}] {filename} — 파일 없음"
                yield _sse_event(progress)
                continue

            try:
                file_data = file_path.read_bytes()
                exif = extract_exif(file_data)
                lat = exif.get("latitude")
                lon = exif.get("longitude")

                if lat is not None and lon is not None:
                    photo.latitude = lat
                    photo.longitude = lon
                    session.add(photo)
                    gps_updated += 1
                    progress["status"] = "extracted"
                    progress["message"] = f"[{idx+1}/{total}] {filename} — GPS 추출 성공 ({lat:.4f}, {lon:.4f})"
                else:
                    gps_not_found += 1
                    progress["status"] = "no_gps"
                    progress["message"] = f"[{idx+1}/{total}] {filename} — GPS 정보 없음"
            except Exception as e:
                gps_failed += 1
                progress["status"] = "error"
                progress["message"] = f"[{idx+1}/{total}] {filename} — 오류: {e}"

            yield _sse_event(progress)

        if gps_updated:
            session.commit()

        yield _sse_event({
            "type": "phase",
            "message": f"GPS 추출 완료: 신규 {gps_updated}장, 기존 {gps_skipped}장, 없음 {gps_not_found}장, 실패 {gps_failed}장",
        })

        # Phase 2: Geocoding
        yield _sse_event({
            "type": "phase",
            "message": "지명 변환을 시작합니다...",
        })

        # Geocode individually with progress
        geo_photos = list(session.exec(
            select(Photo).where(
                Photo.status == "active",
                Photo.latitude != None,   # noqa: E711
                Photo.longitude != None,  # noqa: E711
                Photo.location_name == None,  # noqa: E711
            ).limit(200)
        ).all())

        geo_total = len(geo_photos)
        geo_success = 0

        if geo_total == 0:
            yield _sse_event({
                "type": "phase",
                "message": "지명 변환 대상 없음 (모두 완료됨)",
            })
        else:
            for gi, gp in enumerate(geo_photos):
                gname = reverse_geocode(gp.latitude, gp.longitude)
                gfn = Path(gp.file_path).name if gp.file_path else gp.id
                if gname:
                    gp.location_name = gname
                    session.add(gp)
                    geo_success += 1
                    yield _sse_event({
                        "type": "geocode",
                        "current": gi + 1,
                        "total": geo_total,
                        "message": f"[{gi+1}/{geo_total}] {gfn} → {gname}",
                    })
                else:
                    yield _sse_event({
                        "type": "geocode",
                        "current": gi + 1,
                        "total": geo_total,
                        "message": f"[{gi+1}/{geo_total}] {gfn} → 변환 실패",
                    })

            if geo_success:
                session.commit()

        # Done
        yield _sse_event({
            "type": "done",
            "gps_extracted": gps_updated,
            "geocoded": geo_success,
            "message": f"완료 — GPS 추출: {gps_updated}장, 지명 변환: {geo_success}장",
        })

    return StreamingResponse(
        _generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )
