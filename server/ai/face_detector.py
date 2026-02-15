"""Face detection using ONNX Runtime with UltraFace-slim model.

Model: version-slim-320 (~300KB ONNX)
Input: 320x240 RGB
Output: bounding boxes + confidence scores
"""

import logging
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)

# Detection threshold
CONFIDENCE_THRESHOLD = 0.7


@dataclass
class DetectedFace:
    """A face detected in an image."""
    bbox_x: float  # relative [0,1]
    bbox_y: float
    bbox_w: float
    bbox_h: float
    confidence: float
    crop: np.ndarray  # aligned face crop (112x112 RGB)


class FaceDetector:
    """ONNX-based face detector."""

    def __init__(self, model_path: Path):
        self._session = None
        self._model_path = model_path

    def load(self) -> bool:
        """Load the ONNX model. Returns True if successful."""
        try:
            import onnxruntime as ort
            if not self._model_path.exists():
                logger.warning("Face detection model not found: %s", self._model_path)
                return False
            self._session = ort.InferenceSession(
                str(self._model_path),
                providers=["CPUExecutionProvider"],
            )
            logger.info("Face detection model loaded: %s", self._model_path.name)
            return True
        except ImportError:
            logger.warning("onnxruntime not installed, face detection disabled")
            return False
        except Exception as e:
            logger.error("Failed to load face detection model: %s", e)
            return False

    @property
    def available(self) -> bool:
        return self._session is not None

    def detect(self, image: Image.Image) -> list[DetectedFace]:
        """Detect faces in a PIL Image. Returns list of DetectedFace."""
        if not self._session:
            return []

        orig_w, orig_h = image.size

        # Preprocess: resize to 320x240, normalize to [0,1]
        img_resized = image.convert("RGB").resize((320, 240))
        img_array = np.array(img_resized, dtype=np.float32)
        # Normalize: (pixel - 127) / 128
        img_array = (img_array - 127.0) / 128.0
        # Add batch dimension: (1, H, W, C) -> (1, C, H, W) for NCHW or keep NHWC
        img_input = np.transpose(img_array, (2, 0, 1))[np.newaxis, ...]

        try:
            input_name = self._session.get_inputs()[0].name
            # UltraFace outputs: confidences (1, N, 2), boxes (1, N, 4)
            outputs = self._session.run(None, {input_name: img_input})
            confidences = outputs[0][0]  # (N, 2) - [bg_score, face_score]
            boxes = outputs[1][0]  # (N, 4) - [x1, y1, x2, y2] normalized
        except Exception as e:
            logger.error("Face detection inference error: %s", e)
            return []

        faces = []
        for i in range(confidences.shape[0]):
            face_score = confidences[i, 1]
            if face_score < CONFIDENCE_THRESHOLD:
                continue

            x1, y1, x2, y2 = boxes[i]
            # Clamp to [0, 1]
            x1, y1 = max(0, x1), max(0, y1)
            x2, y2 = min(1, x2), min(1, y2)

            # Convert to pixel coords on original image
            px1 = int(x1 * orig_w)
            py1 = int(y1 * orig_h)
            px2 = int(x2 * orig_w)
            py2 = int(y2 * orig_h)

            # Expand bbox slightly for better alignment
            pad_w = int((px2 - px1) * 0.15)
            pad_h = int((py2 - py1) * 0.15)
            px1 = max(0, px1 - pad_w)
            py1 = max(0, py1 - pad_h)
            px2 = min(orig_w, px2 + pad_w)
            py2 = min(orig_h, py2 + pad_h)

            # Crop and resize to 112x112 for embedding
            face_crop = image.crop((px1, py1, px2, py2)).resize((112, 112))
            face_array = np.array(face_crop.convert("RGB"), dtype=np.float32)

            faces.append(DetectedFace(
                bbox_x=x1,
                bbox_y=y1,
                bbox_w=x2 - x1,
                bbox_h=y2 - y1,
                confidence=float(face_score),
                crop=face_array,
            ))

        return faces
