"""WebSocket handler for voice commands (remote + direct mode).

Remote mode: Client sends text commands via WebSocket.
Direct mode: Client streams audio, server does STT + NLU + execute + TTS.
"""

import json
import logging

from fastapi import WebSocket, WebSocketDisconnect
from sqlmodel import Session

from server.database import get_session
from server.utils.security import decode_token
from server.voice.nlu_parser import parse
from server.voice.command_executor import execute
from server.ws.sync import manager

logger = logging.getLogger(__name__)


async def websocket_voice(ws: WebSocket, token: str | None = None):
    """WebSocket endpoint for voice command processing.

    Client sends:
      {"type": "text_command", "text": "엄마 사진 보여줘"}  (remote mode)
      {"type": "audio_start"}                                (direct mode - begin)
      {"type": "audio_chunk", "data": "<base64 PCM>"}       (direct mode - stream)
      {"type": "audio_end"}                                  (direct mode - finish)

    Server responds:
      {"type": "command_result", ...}
      {"type": "partial_transcript", "text": "..."}          (during audio streaming)
      {"type": "tts", "text": "..."}                         (for client-side TTS)
    """
    if not token:
        await ws.close(code=4001, reason="Missing token")
        return

    try:
        payload = decode_token(token)
    except Exception:
        await ws.close(code=4001, reason="Invalid token")
        return

    user_id = payload.get("sub", "")
    family_id = payload.get("fam", "")

    await ws.accept()

    # STT stream for direct mode
    stt_stream = None

    try:
        while True:
            data = await ws.receive_text()
            try:
                msg = json.loads(data)
            except json.JSONDecodeError:
                await ws.send_json({"type": "error", "message": "Invalid JSON"})
                continue

            msg_type = msg.get("type", "")

            if msg_type == "text_command":
                # Remote mode: receive text, parse, execute
                text = msg.get("text", "")
                if not text:
                    await ws.send_json({"type": "error", "message": "Empty command"})
                    continue

                result = await _process_text_command(text, user_id, family_id, ws)

                # Send TTS text for client-side speech
                if result:
                    await ws.send_json({
                        "type": "tts",
                        "text": result.get("response", ""),
                    })

                    # Also try server-side TTS (async, non-blocking)
                    _try_server_tts(result.get("response", ""))

            elif msg_type == "audio_start":
                # Direct mode: start STT streaming
                stt_stream = _start_stt_stream()
                if stt_stream:
                    await ws.send_json({"type": "listening"})
                else:
                    await ws.send_json({
                        "type": "error",
                        "message": "STT not available. Use text commands.",
                    })

            elif msg_type == "audio_chunk":
                # Direct mode: feed audio to STT
                if stt_stream:
                    import base64
                    audio_bytes = base64.b64decode(msg.get("data", ""))
                    partial = stt_stream.feed(audio_bytes)
                    if partial:
                        await ws.send_json({
                            "type": "partial_transcript",
                            "text": partial,
                        })

            elif msg_type == "audio_end":
                # Direct mode: finalize STT and process command
                if stt_stream:
                    final_text = stt_stream.finalize()
                    stt_stream = None

                    if final_text:
                        await ws.send_json({
                            "type": "transcript",
                            "text": final_text,
                        })
                        result = await _process_text_command(
                            final_text, user_id, family_id, ws
                        )
                        if result:
                            await ws.send_json({
                                "type": "tts",
                                "text": result.get("response", ""),
                            })
                            _try_server_tts(result.get("response", ""))
                    else:
                        await ws.send_json({
                            "type": "error",
                            "message": "음성을 인식하지 못했어요.",
                        })

            elif msg_type == "ping":
                await ws.send_json({"type": "pong"})
            else:
                await ws.send_json({"type": "error", "message": f"Unknown type: {msg_type}"})

    except WebSocketDisconnect:
        pass


async def _process_text_command(
    text: str, user_id: str, family_id: str, ws: WebSocket
) -> dict | None:
    """Parse and execute a text command, broadcast results."""
    parsed = parse(text)

    session_gen = get_session()
    db_session: Session = next(session_gen)
    try:
        result = execute(parsed, db_session, user_id)
    finally:
        try:
            next(session_gen)
        except StopIteration:
            pass

    # Send result to commanding client
    await ws.send_json({
        "type": "command_result",
        "intent": parsed.intent,
        "confidence": parsed.confidence,
        **result,
    })

    # Broadcast display sync to family
    await manager.broadcast(family_id, {
        "type": "display_sync",
        "screen": result.get("type", "text"),
        "user_id": user_id,
        **result,
    })

    return result


def _start_stt_stream():
    """Try to create an STT streaming session."""
    try:
        from server.voice.stt_engine import STTEngine
        engine = STTEngine()
        if engine.load():
            return engine.start_stream()
    except Exception as e:
        logger.warning("Failed to start STT stream: %s", e)
    return None


def _try_server_tts(text: str):
    """Try server-side TTS (non-blocking)."""
    try:
        from server.voice.tts_engine import tts_engine
        if tts_engine.available:
            tts_engine.speak_async(text)
    except Exception:
        pass
