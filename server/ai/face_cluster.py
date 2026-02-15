"""Face clustering using DBSCAN on embedding vectors.

Groups face embeddings into person clusters using cosine distance.
"""

import logging

import numpy as np

logger = logging.getLogger(__name__)

# Faces with cosine distance < threshold are same person
CLUSTER_DISTANCE_THRESHOLD = 0.6  # cosine distance (1 - similarity)
MIN_SAMPLES = 1  # Minimum faces to form a cluster


def cluster_faces(
    embeddings: list[np.ndarray],
    face_ids: list[str],
) -> dict[int, list[str]]:
    """Cluster face embeddings using DBSCAN.

    Args:
        embeddings: list of L2-normalized embedding vectors
        face_ids: corresponding face record IDs (parallel with embeddings)

    Returns:
        Dict mapping cluster_label -> list of face_ids.
        Label -1 means noise (unassigned).
    """
    if len(embeddings) < 2:
        if embeddings:
            return {0: [face_ids[0]]}
        return {}

    try:
        from sklearn.cluster import DBSCAN
    except ImportError:
        logger.warning("scikit-learn not installed, clustering disabled")
        # Fallback: each face is its own cluster
        return {i: [fid] for i, fid in enumerate(face_ids)}

    # Stack into matrix (N, D)
    X = np.stack(embeddings)

    # Use cosine distance: dist = 1 - similarity
    # For L2-normalized vectors: cosine_dist = 1 - dot(a, b)
    dbscan = DBSCAN(
        eps=CLUSTER_DISTANCE_THRESHOLD,
        min_samples=MIN_SAMPLES,
        metric="cosine",
    )
    labels = dbscan.fit_predict(X)

    clusters: dict[int, list[str]] = {}
    for label, fid in zip(labels, face_ids):
        clusters.setdefault(int(label), []).append(fid)

    return clusters


def find_nearest_face(
    embedding: np.ndarray,
    known_embeddings: list[np.ndarray],
    known_face_ids: list[str],
    threshold: float = 0.4,
) -> tuple[str | None, float]:
    """Find the nearest known face to a new embedding.

    Args:
        embedding: L2-normalized query embedding
        known_embeddings: list of known face embeddings
        known_face_ids: corresponding face IDs
        threshold: cosine distance threshold (lower = stricter)

    Returns:
        (face_id, distance) of best match, or (None, 1.0) if no match.
    """
    if not known_embeddings:
        return None, 1.0

    known_matrix = np.stack(known_embeddings)
    # Cosine similarity = dot product for L2-normalized vectors
    similarities = known_matrix @ embedding
    best_idx = int(np.argmax(similarities))
    best_sim = float(similarities[best_idx])
    best_dist = 1.0 - best_sim

    if best_dist <= threshold:
        return known_face_ids[best_idx], best_dist

    return None, best_dist


def compute_centroid(embeddings: list[np.ndarray]) -> np.ndarray:
    """Compute the centroid (mean) embedding for a cluster, L2-normalized."""
    if len(embeddings) == 1:
        return embeddings[0]
    centroid = np.mean(np.stack(embeddings), axis=0)
    norm = np.linalg.norm(centroid)
    if norm > 0:
        centroid = centroid / norm
    return centroid
