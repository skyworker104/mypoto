"""Search API endpoints."""

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from server.api.deps import get_current_user
from server.database import get_session
from server.models.user import User
from server.services.search_service import search_photos, search_places
from server.services.scene_service import get_scenes, get_scene_photos, get_all_tags

router = APIRouter(prefix="/search", tags=["search"])


@router.get("")
def search(
    q: str = Query(..., min_length=1, description="Search query"),
    limit: int = Query(default=50, ge=1, le=200),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Unified search: searches by person, place, and date."""
    return search_photos(q, session, limit=limit)


@router.get("/places")
def list_places(
    limit: int = Query(default=50, ge=1, le=200),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """List all places where photos were taken."""
    places = search_places(session, limit=limit)
    return {"places": places, "total": len(places)}


@router.get("/scenes")
def list_scenes(
    limit: int = Query(default=50, ge=1, le=200),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """List all scene categories with photo counts."""
    scenes = get_scenes(session, limit=limit)
    return {"scenes": scenes, "total": len(scenes)}


@router.get("/scenes/{scene}")
def scene_photos(
    scene: str,
    cursor: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get photos for a specific scene."""
    photos, next_cursor = get_scene_photos(scene, session, cursor=cursor, limit=limit)
    return {"photos": photos, "next_cursor": next_cursor, "count": len(photos)}


@router.get("/tags")
def list_tags(
    limit: int = Query(default=100, ge=1, le=500),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """List all AI-generated tags with counts."""
    tags = get_all_tags(session, limit=limit)
    return {"tags": tags, "total": len(tags)}
