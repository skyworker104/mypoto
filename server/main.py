"""PhotoNest Server - FastAPI Application Entry Point."""

from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, WebSocket, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from server.config import settings
from server.database import init_db

WEB_DIR = Path(__file__).parent / "web"


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize database and AI worker on startup."""
    init_db()

    # Start AI worker (face detection pipeline)
    from server.ai.worker import ai_worker, process_existing_photos
    ai_started = ai_worker.start()
    if ai_started:
        process_existing_photos()

    yield

    # Shutdown AI worker
    ai_worker.stop()


app = FastAPI(
    title="PhotoNest",
    description="Self-hosted family photo backup & viewing system",
    version="0.1.0",
    lifespan=lifespan,
)

# CORS - allow all origins for local network usage
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Register API routers ---
from server.api.auth import router as auth_router
from server.api.family import router as family_router
from server.api.devices import router as devices_router
from server.api.photos import router as photos_router
from server.api.system import router as system_router
from server.api.albums import router as albums_router
from server.api.tv import router as tv_router
from server.api.faces import router as faces_router
from server.api.search import router as search_router
from server.api.memories import router as memories_router
from server.api.map import router as map_router
from server.api.highlights import router as highlights_router

API_PREFIX = "/api/v1"

app.include_router(auth_router, prefix=API_PREFIX)
app.include_router(family_router, prefix=API_PREFIX)
app.include_router(devices_router, prefix=API_PREFIX)
app.include_router(photos_router, prefix=API_PREFIX)
app.include_router(system_router, prefix=API_PREFIX)
app.include_router(albums_router, prefix=API_PREFIX)
app.include_router(tv_router, prefix=API_PREFIX)
app.include_router(faces_router, prefix=API_PREFIX)
app.include_router(search_router, prefix=API_PREFIX)
app.include_router(memories_router, prefix=API_PREFIX)
app.include_router(map_router, prefix=API_PREFIX)
app.include_router(highlights_router, prefix=API_PREFIX)


# --- WebSocket endpoints ---
from server.ws.sync import websocket_sync  # noqa: E402
from server.ws.voice import websocket_voice  # noqa: E402


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket, token: str = Query(default="")):
    await websocket_sync(ws, token or None)


@app.websocket("/ws/voice")
async def ws_voice_endpoint(ws: WebSocket, token: str = Query(default="")):
    await websocket_voice(ws, token or None)


@app.get("/")
def root():
    """Health check / server info."""
    return {
        "name": settings.server_name,
        "server_id": settings.server_id,
        "version": "0.1.0",
        "status": "running",
    }


@app.get("/api/v1/health")
def health():
    return {"status": "ok"}


# --- Web Frontend ---
app.mount("/static", StaticFiles(directory=str(WEB_DIR)), name="static")


@app.get("/web{path:path}")
def web_spa(path: str = ""):
    """Serve the SPA index.html for all /web routes."""
    return FileResponse(str(WEB_DIR / "index.html"))


@app.get("/local{path:path}")
def local_spa(path: str = ""):
    """Serve the SPA for local access (auto-login, no PIN)."""
    return FileResponse(str(WEB_DIR / "index.html"))
