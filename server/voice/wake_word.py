"""Wake word detection using OpenWakeWord.

Listens to microphone input and triggers when "Hey Nesty" is detected.
Designed for direct mode (server-side mic, e.g., set-top box with mic).
"""

import logging
import threading
from typing import Callable

logger = logging.getLogger(__name__)

# Wake word model configuration
WAKE_WORD = "hey_nesty"
DETECTION_THRESHOLD = 0.5
CHUNK_SIZE = 1280  # 80ms at 16kHz


class WakeWordDetector:
    """Wake word detection with OpenWakeWord."""

    def __init__(self, on_wake: Callable[[], None] | None = None):
        self._model = None
        self._on_wake = on_wake
        self._running = False
        self._thread: threading.Thread | None = None

    def load(self) -> bool:
        """Load the wake word model. Returns True if successful."""
        try:
            from openwakeword.model import Model
            self._model = Model(
                wakeword_models=[WAKE_WORD],
                inference_framework="onnx",
            )
            logger.info("Wake word model loaded: %s", WAKE_WORD)
            return True
        except ImportError:
            logger.warning(
                "openwakeword not installed. "
                "Install with: pip install openwakeword"
            )
            return False
        except Exception as e:
            logger.error("Failed to load wake word model: %s", e)
            return False

    @property
    def available(self) -> bool:
        return self._model is not None

    def start_listening(self):
        """Start background listening for wake word (requires microphone)."""
        if not self._model:
            logger.warning("Wake word model not loaded, cannot start")
            return

        self._running = True
        self._thread = threading.Thread(
            target=self._listen_loop, daemon=True, name="wake-word"
        )
        self._thread.start()
        logger.info("Wake word detection started")

    def stop_listening(self):
        """Stop listening."""
        self._running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=3)
        logger.info("Wake word detection stopped")

    def _listen_loop(self):
        """Main listening loop using PyAudio microphone input."""
        try:
            import pyaudio
        except ImportError:
            logger.warning("pyaudio not installed, wake word listening disabled")
            return

        pa = pyaudio.PyAudio()
        stream = None

        try:
            stream = pa.open(
                rate=16000,
                channels=1,
                format=pyaudio.paInt16,
                input=True,
                frames_per_buffer=CHUNK_SIZE,
            )

            logger.info("Microphone opened, listening for wake word...")

            while self._running:
                audio_chunk = stream.read(CHUNK_SIZE, exception_on_overflow=False)

                # Feed to model
                import numpy as np
                audio_array = np.frombuffer(audio_chunk, dtype=np.int16)
                prediction = self._model.predict(audio_array)

                # Check wake word score
                for key, score in prediction.items():
                    if WAKE_WORD in key and score > DETECTION_THRESHOLD:
                        logger.info("Wake word detected! (score=%.2f)", score)
                        self._model.reset()
                        if self._on_wake:
                            self._on_wake()
                        break

        except Exception as e:
            logger.error("Wake word listening error: %s", e)
        finally:
            if stream:
                stream.stop_stream()
                stream.close()
            pa.terminate()

    def process_audio_chunk(self, audio_data: bytes) -> bool:
        """Process a single audio chunk (for WebSocket streaming).

        Returns True if wake word detected.
        """
        if not self._model:
            return False

        import numpy as np
        audio_array = np.frombuffer(audio_data, dtype=np.int16)
        prediction = self._model.predict(audio_array)

        for key, score in prediction.items():
            if WAKE_WORD in key and score > DETECTION_THRESHOLD:
                self._model.reset()
                return True

        return False
