"""WebSocket handler for real-time sync (backup progress, activity feed)."""

import json
from typing import Dict

from fastapi import WebSocket, WebSocketDisconnect
from server.utils.security import decode_token


class ConnectionManager:
    """Manages active WebSocket connections per family."""

    def __init__(self):
        self._connections: Dict[str, list[WebSocket]] = {}  # family_id -> [ws]

    async def connect(self, ws: WebSocket, family_id: str):
        await ws.accept()
        self._connections.setdefault(family_id, []).append(ws)

    def disconnect(self, ws: WebSocket, family_id: str):
        conns = self._connections.get(family_id, [])
        if ws in conns:
            conns.remove(ws)

    async def broadcast(self, family_id: str, message: dict, exclude: WebSocket | None = None):
        """Broadcast a message to all connections in a family."""
        conns = self._connections.get(family_id, [])
        dead = []
        for ws in conns:
            if ws == exclude:
                continue
            try:
                await ws.send_json(message)
            except Exception:
                dead.append(ws)
        for ws in dead:
            conns.remove(ws)

    @property
    def connection_count(self) -> int:
        return sum(len(v) for v in self._connections.values())


manager = ConnectionManager()


async def websocket_sync(ws: WebSocket, token: str | None = None):
    """WebSocket endpoint for real-time sync."""
    # Authenticate
    if not token:
        await ws.close(code=4001, reason="Missing token")
        return

    try:
        payload = decode_token(token)
    except Exception:
        await ws.close(code=4001, reason="Invalid token")
        return

    family_id = payload.get("fam", "")
    user_id = payload.get("sub", "")

    await manager.connect(ws, family_id)

    try:
        while True:
            data = await ws.receive_text()
            try:
                msg = json.loads(data)
                msg_type = msg.get("type", "")

                if msg_type == "ping":
                    await ws.send_json({"type": "pong"})
                elif msg_type == "backup_progress":
                    # Broadcast backup progress to family
                    await manager.broadcast(family_id, {
                        "type": "backup_progress",
                        "user_id": user_id,
                        "data": msg.get("data", {}),
                    }, exclude=ws)
                else:
                    await ws.send_json({"type": "error", "message": f"Unknown type: {msg_type}"})
            except json.JSONDecodeError:
                await ws.send_json({"type": "error", "message": "Invalid JSON"})
    except WebSocketDisconnect:
        manager.disconnect(ws, family_id)
