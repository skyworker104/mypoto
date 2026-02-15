"""Face embedding using ONNX Runtime with MobileFaceNet model.

Model: MobileFaceNet (~4MB ONNX)
Input: 112x112 RGB face crop
Output: 512-dimensional embedding vector (L2-normalized)
"""

import logging
from pathlib import Path

import numpy as np

logger = logging.getLogger(__name__)

EMBEDDING_DIM = 512


class FaceEmbedder:
    """ONNX-based face embedding generator."""

    def __init__(self, model_path: Path):
        self._session = None
        self._model_path = model_path

    def load(self) -> bool:
        """Load the ONNX model. Returns True if successful."""
        try:
            import onnxruntime as ort
            if not self._model_path.exists():
                logger.warning("Face embedding model not found: %s", self._model_path)
                return False
            self._session = ort.InferenceSession(
                str(self._model_path),
                providers=["CPUExecutionProvider"],
            )
            logger.info("Face embedding model loaded: %s", self._model_path.name)
            return True
        except ImportError:
            logger.warning("onnxruntime not installed, face embedding disabled")
            return False
        except Exception as e:
            logger.error("Failed to load face embedding model: %s", e)
            return False

    @property
    def available(self) -> bool:
        return self._session is not None

    def embed(self, face_crop: np.ndarray) -> np.ndarray | None:
        """Generate embedding for a 112x112 RGB face crop.

        Args:
            face_crop: numpy array of shape (112, 112, 3), float32, values in [0,255].

        Returns:
            512-dim L2-normalized embedding vector, or None on failure.
        """
        if not self._session:
            return None

        try:
            # Normalize: (pixel - 127.5) / 127.5 → [-1, 1]
            img = (face_crop - 127.5) / 127.5
            # Transpose to (C, H, W) and add batch dim
            img = np.transpose(img, (2, 0, 1))[np.newaxis, ...].astype(np.float32)

            input_name = self._session.get_inputs()[0].name
            outputs = self._session.run(None, {input_name: img})
            embedding = outputs[0][0]  # (512,)

            # L2 normalize
            norm = np.linalg.norm(embedding)
            if norm > 0:
                embedding = embedding / norm

            return embedding
        except Exception as e:
            logger.error("Face embedding inference error: %s", e)
            return None

    def embed_batch(self, face_crops: list[np.ndarray]) -> list[np.ndarray | None]:
        """Generate embeddings for multiple face crops."""
        return [self.embed(crop) for crop in face_crops]


def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    """Compute cosine similarity between two L2-normalized vectors."""
    return float(np.dot(a, b))


def embedding_to_bytes(embedding: np.ndarray) -> bytes:
    """Serialize a numpy embedding to bytes for DB storage."""
    return embedding.astype(np.float32).tobytes()


def bytes_to_embedding(data: bytes) -> np.ndarray:
    """Deserialize bytes back to numpy embedding."""
    return np.frombuffer(data, dtype=np.float32)
