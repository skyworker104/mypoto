"""Album API endpoints."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session, select, func

from server.api.deps import get_current_user
from server.database import get_session
from server.models.album import Album, AlbumMember, PhotoAlbum
from server.models.photo import Photo
from server.models.user import User
from server.schemas.album import (
    AlbumCreateRequest,
    AlbumDetailResponse,
    AlbumPhotosRequest,
    AlbumResponse,
    AlbumShareRequest,
    AlbumUpdateRequest,
)

router = APIRouter(prefix="/albums", tags=["albums"])


def _album_to_response(album: Album, photo_count: int) -> AlbumResponse:
    return AlbumResponse(
        id=album.id,
        name=album.name,
        type=album.type,
        cover_photo=album.cover_photo_id,
        is_shared=bool(album.is_shared),
        photo_count=photo_count,
        created_by=album.user_id,
        created_at=album.created_at.isoformat() if album.created_at else "",
    )


@router.get("", response_model=list[AlbumResponse])
def list_albums(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """List all albums accessible to the current user (own + shared family)."""
    # Own albums
    own = session.exec(
        select(Album).where(Album.user_id == user.id)
    ).all()

    # Shared albums from family (where user is a member)
    member_album_ids = session.exec(
        select(AlbumMember.album_id).where(AlbumMember.user_id == user.id)
    ).all()
    shared = []
    if member_album_ids:
        shared = session.exec(
            select(Album).where(
                Album.id.in_(member_album_ids),  # type: ignore
                Album.user_id != user.id,
            )
        ).all()

    all_albums = list(own) + list(shared)
    results = []
    for album in all_albums:
        count = session.exec(
            select(func.count()).select_from(PhotoAlbum).where(
                PhotoAlbum.album_id == album.id
            )
        ).one()
        results.append(_album_to_response(album, count))

    return results


@router.post("", response_model=AlbumResponse, status_code=201)
def create_album(
    request: AlbumCreateRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Create a new album."""
    album = Album(
        user_id=user.id,
        name=request.name,
        type=request.type,
        is_shared=request.is_shared,
    )
    session.add(album)

    # If shared, add creator as member
    if request.is_shared:
        member = AlbumMember(
            album_id=album.id,
            user_id=user.id,
            role="owner",
        )
        session.add(member)

    session.commit()
    session.refresh(album)
    return _album_to_response(album, 0)


@router.get("/{album_id}", response_model=AlbumDetailResponse)
def get_album(
    album_id: str,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get album details with photos and members."""
    album = session.get(Album, album_id)
    if not album:
        raise HTTPException(status_code=404, detail="Album not found")

    # Check access
    if album.user_id != user.id and not album.is_shared:
        raise HTTPException(status_code=403, detail="Access denied")

    photo_ids = session.exec(
        select(PhotoAlbum.photo_id).where(PhotoAlbum.album_id == album_id)
    ).all()

    member_ids = session.exec(
        select(AlbumMember.user_id).where(AlbumMember.album_id == album_id)
    ).all()

    return AlbumDetailResponse(
        id=album.id,
        name=album.name,
        type=album.type,
        cover_photo=album.cover_photo_id,
        is_shared=bool(album.is_shared),
        photo_count=len(photo_ids),
        created_by=album.user_id,
        created_at=album.created_at.isoformat() if album.created_at else "",
        photos=list(photo_ids),
        members=list(member_ids),
    )


@router.patch("/{album_id}", response_model=AlbumResponse)
def update_album(
    album_id: str,
    request: AlbumUpdateRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Update album properties."""
    album = session.get(Album, album_id)
    if not album or album.user_id != user.id:
        raise HTTPException(status_code=404, detail="Album not found")

    if request.name is not None:
        album.name = request.name
    if request.cover_photo is not None:
        album.cover_photo_id = request.cover_photo
    if request.is_shared is not None:
        album.is_shared = request.is_shared

    session.add(album)
    session.commit()
    session.refresh(album)

    count = session.exec(
        select(func.count()).select_from(PhotoAlbum).where(
            PhotoAlbum.album_id == album_id
        )
    ).one()
    return _album_to_response(album, count)


@router.delete("/{album_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_album(
    album_id: str,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Delete an album (does not delete the photos)."""
    album = session.get(Album, album_id)
    if not album or album.user_id != user.id:
        raise HTTPException(status_code=404, detail="Album not found")

    # Delete photo-album links and members
    for pa in session.exec(select(PhotoAlbum).where(PhotoAlbum.album_id == album_id)).all():
        session.delete(pa)
    for am in session.exec(select(AlbumMember).where(AlbumMember.album_id == album_id)).all():
        session.delete(am)

    session.delete(album)
    session.commit()


@router.post("/{album_id}/photos", status_code=201)
def add_photos_to_album(
    album_id: str,
    request: AlbumPhotosRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Add photos to an album."""
    album = session.get(Album, album_id)
    if not album:
        raise HTTPException(status_code=404, detail="Album not found")

    added = 0
    for photo_id in request.photo_ids:
        # Check photo exists
        photo = session.get(Photo, photo_id)
        if not photo:
            continue
        # Check not already in album
        existing = session.exec(
            select(PhotoAlbum).where(
                PhotoAlbum.album_id == album_id,
                PhotoAlbum.photo_id == photo_id,
            )
        ).first()
        if existing:
            continue

        pa = PhotoAlbum(album_id=album_id, photo_id=photo_id)
        session.add(pa)
        added += 1

    # Set cover photo if album has none
    if album.cover_photo_id is None and request.photo_ids:
        album.cover_photo_id = request.photo_ids[0]
        session.add(album)

    session.commit()
    return {"added": added}


@router.delete("/{album_id}/photos")
def remove_photos_from_album(
    album_id: str,
    request: AlbumPhotosRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Remove photos from an album."""
    removed = 0
    for photo_id in request.photo_ids:
        pa = session.exec(
            select(PhotoAlbum).where(
                PhotoAlbum.album_id == album_id,
                PhotoAlbum.photo_id == photo_id,
            )
        ).first()
        if pa:
            session.delete(pa)
            removed += 1
    session.commit()
    return {"removed": removed}


@router.post("/{album_id}/share", status_code=201)
def share_album(
    album_id: str,
    request: AlbumShareRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Share an album with family members."""
    album = session.get(Album, album_id)
    if not album or album.user_id != user.id:
        raise HTTPException(status_code=404, detail="Album not found")

    album.is_shared = True
    session.add(album)

    added = 0
    for uid in request.user_ids:
        existing = session.exec(
            select(AlbumMember).where(
                AlbumMember.album_id == album_id,
                AlbumMember.user_id == uid,
            )
        ).first()
        if not existing:
            session.add(AlbumMember(
                album_id=album_id, user_id=uid, role="viewer"
            ))
            added += 1

    session.commit()
    return {"shared_with": added}
