"""Text-to-Speech engine.

Supports multiple backends:
1. termux-tts-speak (Android/Termux - uses device TTS)
2. pyttsx3 (cross-platform fallback)
3. WebSocket streaming (send text to client for TTS)
"""

import logging
import subprocess
import threading

logger = logging.getLogger(__name__)


class TTSEngine:
    """Text-to-Speech engine with multiple backends."""

    def __init__(self):
        self._backend: str | None = None
        self._engine = None
        self._lock = threading.Lock()

    def load(self) -> bool:
        """Detect and load the best available TTS backend."""
        # Try termux-tts-speak first (Android)
        if self._try_termux():
            self._backend = "termux"
            logger.info("TTS backend: termux-tts-speak")
            return True

        # Try pyttsx3 (cross-platform)
        if self._try_pyttsx3():
            self._backend = "pyttsx3"
            logger.info("TTS backend: pyttsx3")
            return True

        # Fallback: client-side TTS via WebSocket
        self._backend = "client"
        logger.info("TTS backend: client-side (WebSocket)")
        return True

    def _try_termux(self) -> bool:
        try:
            result = subprocess.run(
                ["which", "termux-tts-speak"],
                capture_output=True, timeout=3,
            )
            return result.returncode == 0
        except Exception:
            return False

    def _try_pyttsx3(self) -> bool:
        try:
            import pyttsx3
            self._engine = pyttsx3.init()
            # Set Korean voice if available
            voices = self._engine.getProperty("voices")
            for voice in voices:
                if "ko" in voice.id.lower() or "korean" in voice.name.lower():
                    self._engine.setProperty("voice", voice.id)
                    break
            self._engine.setProperty("rate", 170)
            return True
        except Exception:
            return False

    @property
    def backend(self) -> str | None:
        return self._backend

    @property
    def available(self) -> bool:
        return self._backend is not None

    def speak(self, text: str):
        """Speak text using the loaded backend (blocking for local TTS)."""
        if not self._backend:
            return

        with self._lock:
            if self._backend == "termux":
                self._speak_termux(text)
            elif self._backend == "pyttsx3":
                self._speak_pyttsx3(text)
            # "client" backend is handled via WebSocket (not here)

    def speak_async(self, text: str):
        """Speak text in a background thread."""
        if self._backend in ("termux", "pyttsx3"):
            threading.Thread(
                target=self.speak, args=(text,), daemon=True
            ).start()

    def _speak_termux(self, text: str):
        try:
            subprocess.run(
                ["termux-tts-speak", "-l", "ko", text],
                timeout=30,
                capture_output=True,
            )
        except Exception as e:
            logger.error("termux-tts-speak error: %s", e)

    def _speak_pyttsx3(self, text: str):
        try:
            self._engine.say(text)
            self._engine.runAndWait()
        except Exception as e:
            logger.error("pyttsx3 error: %s", e)


# Singleton
tts_engine = TTSEngine()
