"""Multi-turn dialog session management.

Maintains conversation context for follow-up commands:
- Remembers previous intent and slots
- Accumulates filters (e.g., "엄마 사진" → "작년 거")
- 30-second timeout between turns
"""

import logging
import time
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)

SESSION_TIMEOUT_SECONDS = 30


@dataclass
class DialogContext:
    """Persistent context across dialog turns."""
    last_intent: str = ""
    last_slots: dict = field(default_factory=dict)
    accumulated_filters: dict = field(default_factory=dict)
    last_photos: list = field(default_factory=list)  # photo IDs from last result
    last_active_time: float = 0.0
    turn_count: int = 0

    @property
    def is_expired(self) -> bool:
        if self.last_active_time == 0:
            return True
        return (time.time() - self.last_active_time) > SESSION_TIMEOUT_SECONDS

    def touch(self):
        self.last_active_time = time.time()
        self.turn_count += 1

    def reset(self):
        self.last_intent = ""
        self.last_slots = {}
        self.accumulated_filters = {}
        self.last_photos = []
        self.last_active_time = 0.0
        self.turn_count = 0


class DialogSessionManager:
    """Manages dialog sessions per user."""

    def __init__(self):
        self._sessions: dict[str, DialogContext] = {}

    def get_context(self, user_id: str) -> DialogContext:
        """Get or create a dialog context for a user."""
        ctx = self._sessions.get(user_id)
        if ctx is None or ctx.is_expired:
            ctx = DialogContext()
            self._sessions[user_id] = ctx
        return ctx

    def update_context(
        self,
        user_id: str,
        intent: str,
        slots: dict,
        photo_ids: list | None = None,
    ):
        """Update context after a successful command execution."""
        ctx = self.get_context(user_id)
        ctx.last_intent = intent
        ctx.last_slots = slots.copy()
        ctx.touch()

        # Accumulate filters for follow-up queries
        if intent.startswith("SEARCH_") or intent == "SHOW_PHOTOS":
            for key, val in slots.items():
                ctx.accumulated_filters[key] = val

        if photo_ids:
            ctx.last_photos = photo_ids

    def apply_context(self, user_id: str, intent: str, slots: dict) -> dict:
        """Apply context from previous turns to current slots.

        Handles follow-up queries like:
        - "엄마 사진" → "작년 거" (inherits person=엄마, adds date=작년)
        - "다음" after slideshow (inherits slideshow context)
        """
        ctx = self.get_context(user_id)

        if ctx.is_expired or ctx.turn_count == 0:
            return slots

        enriched = slots.copy()

        # Follow-up: if current query lacks context, inherit from previous
        if intent == "SEARCH_DATE" and "person" not in enriched:
            if "person" in ctx.accumulated_filters:
                enriched["person"] = ctx.accumulated_filters["person"]

        if intent == "SEARCH_PLACE" and "person" not in enriched:
            if "person" in ctx.accumulated_filters:
                enriched["person"] = ctx.accumulated_filters["person"]

        if intent == "SHOW_PHOTOS" and not enriched:
            enriched.update(ctx.accumulated_filters)

        # "이거 틀어줘" / "슬라이드쇼" after photo search → use last results
        if intent == "PLAY_SLIDESHOW" and ctx.last_photos:
            enriched["photo_ids"] = ctx.last_photos

        return enriched

    def clear(self, user_id: str):
        """Clear a user's dialog context."""
        if user_id in self._sessions:
            self._sessions[user_id].reset()


# Singleton
dialog_manager = DialogSessionManager()
