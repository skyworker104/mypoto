"""TV slideshow API endpoints."""

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from server.api.deps import get_current_user
from server.database import get_session
from server.models.user import User
from server.services.tv_service import (
    control_slideshow,
    get_slideshow_status,
    start_slideshow,
    stop_slideshow,
)

router = APIRouter(prefix="/tv", tags=["tv"])


@router.post("/slideshow/start")
def tv_start(
    interval: int = Query(default=10, ge=3, le=60),
    order: str = Query(default="random", regex="^(random|date)$"),
    album_id: str | None = Query(default=None),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Start a slideshow on the TV/display."""
    return start_slideshow(
        db=session,
        interval=interval,
        order=order,
        album_id=album_id,
    )


@router.post("/slideshow/stop")
def tv_stop(user: User = Depends(get_current_user)):
    """Stop the current slideshow."""
    return stop_slideshow()


@router.post("/slideshow/control")
def tv_control(
    action: str = Query(..., regex="^(next|prev|pause|resume)$"),
    user: User = Depends(get_current_user),
):
    """Control slideshow: next, prev, pause, resume."""
    return control_slideshow(action)


@router.get("/slideshow/status")
def tv_status(user: User = Depends(get_current_user)):
    """Get current slideshow status."""
    return get_slideshow_status()
