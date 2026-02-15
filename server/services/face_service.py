"""Face recognition business logic - querying, tagging, merging."""

from sqlmodel import Session, select, func, col

from server.ai.face_cluster import cluster_faces, compute_centroid
from server.ai.face_embedder import bytes_to_embedding, embedding_to_bytes
from server.models.photo import Face, Photo, PhotoFace


def get_faces(
    session: Session,
    named_only: bool = False,
    min_photos: int = 1,
    limit: int = 100,
) -> list[dict]:
    """Get face clusters (persons) with photo counts.

    Returns list of dicts with face info + representative photo thumbnail.
    """
    query = select(Face).where(Face.photo_count >= min_photos)
    if named_only:
        query = query.where(Face.name != None)  # noqa: E711

    query = query.order_by(col(Face.photo_count).desc()).limit(limit)
    faces = list(session.exec(query).all())

    results = []
    for face in faces:
        # Get a representative photo (first photo with this face)
        pf = session.exec(
            select(PhotoFace).where(PhotoFace.face_id == face.id).limit(1)
        ).first()
        cover_photo_id = pf.photo_id if pf else None

        results.append({
            "id": face.id,
            "name": face.name,
            "photo_count": face.photo_count,
            "cover_photo_id": cover_photo_id,
            "created_at": face.created_at.isoformat() if face.created_at else "",
        })

    return results


def get_face_photos(
    face_id: str,
    session: Session,
    cursor: str | None = None,
    limit: int = 50,
) -> tuple[list[Photo], str | None]:
    """Get photos containing a specific face, with cursor pagination."""
    # Get photo IDs linked to this face
    pf_query = select(PhotoFace.photo_id).where(PhotoFace.face_id == face_id)
    photo_ids = list(session.exec(pf_query).all())

    if not photo_ids:
        return [], None

    query = select(Photo).where(
        Photo.id.in_(photo_ids),  # type: ignore
        Photo.status == "active",
    )

    if cursor:
        query = query.where(Photo.taken_at < cursor)

    query = query.order_by(col(Photo.taken_at).desc()).limit(limit + 1)
    photos = list(session.exec(query).all())

    next_cursor = None
    if len(photos) > limit:
        photos = photos[:limit]
        last = photos[-1]
        next_cursor = (last.taken_at or last.created_at).isoformat()

    return photos, next_cursor


def tag_face(face_id: str, name: str, session: Session) -> dict | None:
    """Assign a name to a face cluster."""
    face = session.get(Face, face_id)
    if not face:
        return None

    face.name = name
    session.add(face)
    session.commit()
    session.refresh(face)

    return {"id": face.id, "name": face.name, "photo_count": face.photo_count}


def merge_faces(
    target_face_id: str,
    source_face_ids: list[str],
    session: Session,
) -> dict | None:
    """Merge multiple face clusters into one.

    Moves all PhotoFace links from source faces to the target face,
    updates the centroid embedding, and deletes source faces.
    """
    target = session.get(Face, target_face_id)
    if not target:
        return None

    merged_count = 0
    all_embeddings = []

    # Collect target's embedding
    if target.embedding:
        all_embeddings.append(bytes_to_embedding(target.embedding))

    for src_id in source_face_ids:
        if src_id == target_face_id:
            continue
        source = session.get(Face, src_id)
        if not source:
            continue

        # Move all PhotoFace links to target
        photo_faces = session.exec(
            select(PhotoFace).where(PhotoFace.face_id == src_id)
        ).all()
        for pf in photo_faces:
            pf.face_id = target_face_id
            session.add(pf)
            merged_count += 1

        # Collect source embedding
        if source.embedding:
            all_embeddings.append(bytes_to_embedding(source.embedding))

        # Delete source face
        session.delete(source)

    # Update target centroid and photo count
    if all_embeddings:
        centroid = compute_centroid(all_embeddings)
        target.embedding = embedding_to_bytes(centroid)

    # Recount photos
    count = session.exec(
        select(func.count()).select_from(PhotoFace).where(
            PhotoFace.face_id == target_face_id
        )
    ).one()
    target.photo_count = count
    session.add(target)
    session.commit()

    return {
        "id": target.id,
        "name": target.name,
        "photo_count": target.photo_count,
        "merged": merged_count,
    }


def recluster_faces(session: Session) -> dict:
    """Re-run DBSCAN clustering on all face embeddings.

    This is used to merge faces that should be the same person
    but were detected in separate batches.
    """
    faces = list(session.exec(
        select(Face).where(Face.embedding != None)  # noqa: E711
    ).all())

    if len(faces) < 2:
        return {"clusters": len(faces), "merged": 0}

    embeddings = [bytes_to_embedding(f.embedding) for f in faces if f.embedding]
    face_ids = [f.id for f in faces if f.embedding]

    clusters = cluster_faces(embeddings, face_ids)

    merged_total = 0
    for label, cluster_fids in clusters.items():
        if label == -1:
            continue  # noise - skip
        if len(cluster_fids) <= 1:
            continue

        # Merge: keep the face with the most photos as target
        cluster_faces_db = [session.get(Face, fid) for fid in cluster_fids]
        cluster_faces_db = [f for f in cluster_faces_db if f is not None]
        cluster_faces_db.sort(key=lambda f: f.photo_count, reverse=True)

        target = cluster_faces_db[0]
        sources = [f.id for f in cluster_faces_db[1:]]
        if sources:
            result = merge_faces(target.id, sources, session)
            if result:
                merged_total += result.get("merged", 0)

    return {"clusters": len(clusters), "merged": merged_total}


def search_by_person(
    name: str,
    session: Session,
    limit: int = 20,
) -> list[Photo]:
    """Search photos by person name (face tag)."""
    # Find faces matching the name
    faces = list(session.exec(
        select(Face).where(col(Face.name).contains(name))
    ).all())

    if not faces:
        return []

    face_ids = [f.id for f in faces]
    photo_ids = list(session.exec(
        select(PhotoFace.photo_id).where(
            PhotoFace.face_id.in_(face_ids)  # type: ignore
        )
    ).all())

    if not photo_ids:
        return []

    photos = list(session.exec(
        select(Photo).where(
            Photo.id.in_(photo_ids),  # type: ignore
            Photo.status == "active",
        ).order_by(col(Photo.taken_at).desc()).limit(limit)
    ).all())

    return photos
