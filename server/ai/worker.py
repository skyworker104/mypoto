"""Background AI worker for processing photos (face detection + embedding + scene).

Runs as a daemon thread, processes a queue of photo IDs.
"""

import json
import logging
import queue
import threading
import time
from pathlib import Path

import numpy as np
from PIL import Image
from sqlmodel import Session, select

from server.ai.face_cluster import compute_centroid, find_nearest_face
from server.ai.face_detector import FaceDetector
from server.ai.face_embedder import (
    FaceEmbedder,
    bytes_to_embedding,
    embedding_to_bytes,
)
from server.ai.scene_classifier import classify_scene_local
from server.config import settings
from server.database import engine
from server.models.photo import Face, Photo, PhotoFace

logger = logging.getLogger(__name__)

# Match threshold: cosine distance below this = same person
MATCH_THRESHOLD = 0.4


class AIWorker:
    """Background worker that processes photos for face detection."""

    def __init__(self):
        self._queue: queue.Queue[str] = queue.Queue()
        self._thread: threading.Thread | None = None
        self._running = False
        self._detector = FaceDetector(
            settings.ai_dir / "models" / "face_detection.onnx"
        )
        self._embedder = FaceEmbedder(
            settings.ai_dir / "models" / "face_embedding.onnx"
        )

    def start(self) -> bool:
        """Start the worker thread. Returns True if AI models are available."""
        det_ok = self._detector.load()
        emb_ok = self._embedder.load()

        if not (det_ok and emb_ok):
            logger.info(
                "AI models not available, face detection disabled. "
                "Place ONNX models in: %s",
                settings.ai_dir / "models",
            )
            return False

        self._running = True
        self._thread = threading.Thread(target=self._run, daemon=True, name="ai-worker")
        self._thread.start()
        logger.info("AI worker started")
        return True

    def stop(self):
        """Stop the worker thread."""
        self._running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=5)
        logger.info("AI worker stopped")

    @property
    def available(self) -> bool:
        return self._detector.available and self._embedder.available

    def enqueue(self, photo_id: str):
        """Add a photo to the processing queue."""
        if self.available:
            self._queue.put(photo_id)

    def enqueue_batch(self, photo_ids: list[str]):
        """Add multiple photos to the processing queue."""
        for pid in photo_ids:
            self.enqueue(pid)

    @property
    def queue_size(self) -> int:
        return self._queue.qsize()

    def _run(self):
        """Main worker loop."""
        while self._running:
            try:
                photo_id = self._queue.get(timeout=2)
                self._process_photo(photo_id)
            except queue.Empty:
                continue
            except Exception as e:
                logger.error("AI worker error processing photo: %s", e)

    def _process_photo(self, photo_id: str):
        """Process a single photo: detect faces, generate embeddings, match/create."""
        with Session(engine) as session:
            photo = session.get(Photo, photo_id)
            if not photo or photo.status != "active":
                return

            # Skip videos and already-processed photos
            if photo.is_video:
                return
            existing = session.exec(
                select(PhotoFace).where(PhotoFace.photo_id == photo_id)
            ).first()
            if existing:
                return

            # Load image
            file_path = Path(photo.file_path)
            if not file_path.exists():
                logger.warning("Photo file not found: %s", file_path)
                return

            try:
                image = Image.open(file_path)
            except Exception as e:
                logger.error("Failed to open image %s: %s", photo_id, e)
                return

            # Scene classification (always runs, even without face models)
            if not photo.ai_scene:
                try:
                    exif = json.loads(photo.exif_data) if photo.exif_data else {}
                    exif["taken_at"] = photo.taken_at
                    scene, tags = classify_scene_local(image, exif)
                    photo.ai_scene = scene
                    photo.ai_tags = json.dumps(tags, ensure_ascii=False)
                    session.add(photo)
                    session.commit()
                    session.refresh(photo)
                    logger.info("Classified photo %s: scene=%s tags=%s", photo_id, scene, tags)
                except Exception as e:
                    logger.error("Scene classification failed for %s: %s", photo_id, e)

            # Detect faces
            detected = self._detector.detect(image)
            if not detected:
                return

            logger.info("Found %d face(s) in photo %s", len(detected), photo_id)

            # Load known faces for matching
            known_faces = list(session.exec(
                select(Face).where(Face.embedding != None)  # noqa: E711
            ).all())
            known_embeddings = []
            known_ids = []
            for f in known_faces:
                if f.embedding:
                    known_embeddings.append(bytes_to_embedding(f.embedding))
                    known_ids.append(f.id)

            # Process each detected face
            for det in detected:
                embedding = self._embedder.embed(det.crop)
                if embedding is None:
                    continue

                # Try to match with known faces
                matched_id, dist = find_nearest_face(
                    embedding, known_embeddings, known_ids, MATCH_THRESHOLD
                )

                if matched_id:
                    # Matched existing face - update centroid
                    face = session.get(Face, matched_id)
                    if face:
                        face.photo_count += 1
                        # Update centroid as running average
                        if face.embedding:
                            old_emb = bytes_to_embedding(face.embedding)
                            new_centroid = compute_centroid([old_emb, embedding])
                            face.embedding = embedding_to_bytes(new_centroid)
                        session.add(face)
                        face_id = matched_id
                else:
                    # New face - create entry
                    new_face = Face(
                        embedding=embedding_to_bytes(embedding),
                        photo_count=1,
                    )
                    session.add(new_face)
                    session.flush()
                    face_id = new_face.id

                    # Add to known list for subsequent faces in same photo
                    known_embeddings.append(embedding)
                    known_ids.append(face_id)

                # Create PhotoFace link
                photo_face = PhotoFace(
                    photo_id=photo_id,
                    face_id=face_id,
                    bbox_x=det.bbox_x,
                    bbox_y=det.bbox_y,
                    bbox_w=det.bbox_w,
                    bbox_h=det.bbox_h,
                    confidence=det.confidence,
                )
                session.add(photo_face)

            session.commit()


# Singleton worker instance
ai_worker = AIWorker()


def process_existing_photos():
    """Enqueue all unprocessed photos for face detection (migration)."""
    if not ai_worker.available:
        return 0

    with Session(engine) as session:
        # Find photos that have no PhotoFace entries
        processed_ids = set(
            session.exec(select(PhotoFace.photo_id)).all()
        )
        all_photo_ids = session.exec(
            select(Photo.id).where(
                Photo.status == "active",
                Photo.is_video == False,  # noqa: E712
            )
        ).all()
        unprocessed = [pid for pid in all_photo_ids if pid not in processed_ids]

    if unprocessed:
        logger.info("Enqueuing %d unprocessed photos for face detection", len(unprocessed))
        ai_worker.enqueue_batch(unprocessed)

    return len(unprocessed)
