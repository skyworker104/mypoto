"""System status API endpoints."""

import socket

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlmodel import Session, func, select

from server.api.deps import get_current_user
from server.config import settings
from server.database import get_session
from server.models.photo import Photo
from server.models.user import User
from server.schemas.photo import SystemStatusResponse
from server.utils.storage import get_storage_info


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
