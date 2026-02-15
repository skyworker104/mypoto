"""Highlight video API endpoints."""

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlmodel import Session

from server.api.deps import get_current_user
from server.database import get_session
from server.models.user import User
from server.services.highlight_service import (
    create_highlight,
    delete_highlight,
    get_highlight,
    list_highlights,
)

router = APIRouter(prefix="/highlights", tags=["highlights"])


class HighlightCreateRequest(BaseModel):
    title: str
    source_type: str = "date_range"  # date_range | location | faces | album
    date_from: str | None = None
    date_to: str | None = None
    location: str | None = None
    face_id: str | None = None
    album_id: str | None = None


@router.get("")
def list_user_highlights(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """List all highlights for current user."""
    highlights = list_highlights(user.id, session)
    return {"highlights": highlights, "count": len(highlights)}


@router.post("/generate")
def generate_highlight(
    req: HighlightCreateRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Generate a new highlight video from selected photos."""
    source_params = {}
    if req.source_type == "date_range":
        source_params = {"date_from": req.date_from, "date_to": req.date_to}
    elif req.source_type == "location":
        source_params = {"location": req.location}
    elif req.source_type == "faces":
        source_params = {"face_id": req.face_id}
    elif req.source_type == "album":
        source_params = {"album_id": req.album_id}

    highlight = create_highlight(
        user_id=user.id,
        title=req.title,
        source_type=req.source_type,
        source_params=source_params,
        session=session,
    )
    return {
        "id": highlight.id,
        "status": highlight.status,
        "message": "하이라이트 생성이 시작되었습니다",
    }


@router.get("/{highlight_id}")
def get_highlight_detail(
    highlight_id: str,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get highlight detail."""
    result = get_highlight(highlight_id, session)
    if not result:
        raise HTTPException(404, "Highlight not found")
    return result


@router.get("/{highlight_id}/video")
def get_highlight_video(
    highlight_id: str,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Stream highlight video file."""
    from pathlib import Path
    from server.models.photo import Highlight

    h = session.get(Highlight, highlight_id)
    if not h or not h.video_path:
        raise HTTPException(404, "Video not found")

    video_path = Path(h.video_path)
    if not video_path.exists():
        raise HTTPException(404, "Video file missing")

    return FileResponse(
        path=str(video_path),
        media_type="video/mp4",
        filename=f"{h.title}.mp4",
    )


@router.get("/{highlight_id}/thumbnail")
def get_highlight_thumbnail(
    highlight_id: str,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get highlight thumbnail image."""
    from pathlib import Path
    from server.models.photo import Highlight

    h = session.get(Highlight, highlight_id)
    if not h or not h.thumbnail_path:
        raise HTTPException(404, "Thumbnail not found")

    thumb_path = Path(h.thumbnail_path)
    if not thumb_path.exists():
        raise HTTPException(404, "Thumbnail file missing")

    return FileResponse(
        path=str(thumb_path),
        media_type="image/jpeg",
    )


@router.delete("/{highlight_id}")
def delete_user_highlight(
    highlight_id: str,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Delete a highlight and its video."""
    if not delete_highlight(highlight_id, user.id, session):
        raise HTTPException(404, "Highlight not found")
    return {"deleted": True}
