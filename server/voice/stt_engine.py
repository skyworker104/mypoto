"""Speech-to-Text engine using Vosk (offline Korean ASR).

Vosk provides offline speech recognition with Korean language support.
Model: vosk-model-small-ko-0.22 (~50MB)
"""

import json
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

# Expected model directory
DEFAULT_MODEL_PATH = Path.home() / "photonest" / "ai" / "models" / "vosk-ko"


class STTEngine:
    """Vosk-based Speech-to-Text engine for Korean."""

    def __init__(self, model_path: Path | None = None):
        self._model = None
        self._recognizer = None
        self._model_path = model_path or DEFAULT_MODEL_PATH

    def load(self) -> bool:
        """Load the Vosk model. Returns True if successful."""
        try:
            from vosk import Model, KaldiRecognizer

            if not self._model_path.exists():
                logger.warning(
                    "Vosk Korean model not found at: %s. "
                    "Download from: https://alphacephei.com/vosk/models",
                    self._model_path,
                )
                return False

            self._model = Model(str(self._model_path))
            self._recognizer = KaldiRecognizer(self._model, 16000)
            logger.info("Vosk STT model loaded: %s", self._model_path.name)
            return True

        except ImportError:
            logger.warning(
                "vosk not installed. Install with: pip install vosk"
            )
            return False
        except Exception as e:
            logger.error("Failed to load Vosk model: %s", e)
            return False

    @property
    def available(self) -> bool:
        return self._model is not None and self._recognizer is not None

    def transcribe_audio(self, audio_data: bytes) -> str:
        """Transcribe a complete audio buffer (16kHz, 16-bit PCM mono).

        Returns the recognized text.
        """
        if not self._recognizer:
            return ""

        from vosk import KaldiRecognizer
        # Create a fresh recognizer for each complete utterance
        rec = KaldiRecognizer(self._model, 16000)
        rec.AcceptWaveform(audio_data)
        result = json.loads(rec.FinalResult())
        return result.get("text", "")

    def start_stream(self) -> "STTStream":
        """Create a new streaming recognition session."""
        if not self._model:
            raise RuntimeError("STT model not loaded")
        return STTStream(self._model)


class STTStream:
    """Streaming speech recognition session."""

    def __init__(self, model):
        from vosk import KaldiRecognizer
        self._recognizer = KaldiRecognizer(model, 16000)
        self._final_text = ""

    def feed(self, audio_chunk: bytes) -> str | None:
        """Feed an audio chunk. Returns partial text if available."""
        if self._recognizer.AcceptWaveform(audio_chunk):
            result = json.loads(self._recognizer.Result())
            text = result.get("text", "")
            if text:
                self._final_text = text
                return text
        else:
            partial = json.loads(self._recognizer.PartialResult())
            return partial.get("partial", "")
        return None

    def finalize(self) -> str:
        """Finalize recognition and return final text."""
        result = json.loads(self._recognizer.FinalResult())
        text = result.get("text", "")
        return text or self._final_text
