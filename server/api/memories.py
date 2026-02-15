"""Memory/recall API endpoints."""

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from server.api.deps import get_current_user
from server.database import get_session
from server.models.user import User
from server.services.memory_service import (
    get_memories_today,
    get_memory_summary,
    get_weekly_highlights,
)

router = APIRouter(prefix="/memories", tags=["memories"])


@router.get("")
def list_memories(
    limit: int = Query(default=20, ge=1, le=50),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get today's memories (on this day in past years)."""
    memories = get_memories_today(session, limit=limit)
    return {"memories": memories, "total": len(memories)}


@router.get("/highlights")
def weekly_highlights(
    limit: int = Query(default=10, ge=1, le=50),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get weekly photo highlights."""
    highlights = get_weekly_highlights(session, limit=limit)
    return {"highlights": highlights, "total": len(highlights)}


@router.get("/summary")
def memory_summary(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get memory statistics summary."""
    return get_memory_summary(session)
