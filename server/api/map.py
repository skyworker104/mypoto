"""Map API endpoints - location-based photo browsing."""

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from server.api.deps import get_current_user
from server.database import get_session
from server.models.user import User
from server.services.map_service import (
    get_photo_locations,
    get_location_clusters,
    get_photos_near,
)

router = APIRouter(prefix="/map", tags=["map"])


@router.get("/photos")
def map_photos(
    lat_min: float | None = Query(default=None),
    lat_max: float | None = Query(default=None),
    lon_min: float | None = Query(default=None),
    lon_max: float | None = Query(default=None),
    limit: int = Query(default=500, ge=1, le=2000),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get individual photo locations for map display."""
    bounds = None
    if all(v is not None for v in [lat_min, lat_max, lon_min, lon_max]):
        bounds = (lat_min, lat_max, lon_min, lon_max)

    photos = get_photo_locations(session, bounds=bounds, limit=limit)
    return {"photos": photos, "count": len(photos)}


@router.get("/clusters")
def map_clusters(
    precision: int = Query(default=2, ge=0, le=5, description="Decimal places for clustering"),
    lat_min: float | None = Query(default=None),
    lat_max: float | None = Query(default=None),
    lon_min: float | None = Query(default=None),
    lon_max: float | None = Query(default=None),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get clustered photo locations for map overview."""
    bounds = None
    if all(v is not None for v in [lat_min, lat_max, lon_min, lon_max]):
        bounds = (lat_min, lat_max, lon_min, lon_max)

    clusters = get_location_clusters(session, precision=precision, bounds=bounds)
    return {"clusters": clusters, "count": len(clusters)}


@router.get("/nearby")
def nearby_photos(
    lat: float = Query(..., description="Latitude"),
    lon: float = Query(..., description="Longitude"),
    radius: float = Query(default=5.0, ge=0.1, le=100, description="Radius in km"),
    limit: int = Query(default=50, ge=1, le=200),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get photos near a GPS coordinate."""
    photos = get_photos_near(session, lat, lon, radius_km=radius, limit=limit)
    return {"photos": photos, "count": len(photos)}
