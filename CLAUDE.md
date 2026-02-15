# PhotoNest - Claude Code Rules

## Code Size Rules
- **All source files MUST NOT exceed 1500 lines.** If a file approaches this limit, split it into smaller modules.
- Prefer small, focused modules (under 300-500 lines ideally).
- When splitting, group by responsibility: one module = one concern.

## Project Structure
```
server/          # Python + FastAPI backend (Termux)
  api/           # API routers (REST endpoints)
  services/      # Business logic services
  models/        # SQLite data models (Pydantic)
  schemas/       # Request/Response schemas
  ai/            # ONNX face detection/embedding, scene classifier
  voice/         # Wake word, STT, TTS, NLU, command executor
  ws/            # WebSocket handlers (sync, voice)
  web/           # Web frontend (Vanilla JS SPA)
    js/views/    # Page-level view modules
    js/components/ # Reusable UI components
    css/         # Stylesheets (one per domain)
app/             # Flutter mobile app (Dart)
  lib/screens/   # Screen widgets
  lib/services/  # API client, backup service
tests/           # Python test files
docs/            # Design documents
```

## Tech Stack
- **Backend**: Python 3, FastAPI, SQLite (WAL mode), ONNX Runtime
- **Web Frontend**: Vanilla JS (ES Modules), CSS Grid, hash-based SPA router
- **Mobile App**: Flutter (Dart), Riverpod
- **Auth**: JWT (24h access + 30d refresh), PIN-based pairing
- **Communication**: REST API + WebSocket

## Coding Conventions

### Python (server/)
- Use type hints on all function signatures.
- Models use Pydantic BaseModel.
- API routers go in `server/api/`, business logic in `server/services/`.
- Test with `PYTHONPATH=. python3 tests/test_phase2.py && python3 tests/test_phase3.py`.
- Total expected: 92 tests (48 Phase 2 + 44 Phase 3).

### JavaScript (server/web/)
- ES Modules (`import`/`export`), no bundler.
- Each view exports `init(container)`, `onActivate(params?)`, `onDeactivate()`.
- Use `el()` helper from `utils.js` for DOM creation.
- Authenticated image loading: `fetchImageUrl()` → Blob URL with LRU cache.
- Toast notifications via `showToast()` from `components/toast.js`.

### CSS (server/web/css/)
- CSS custom properties defined in `variables.css`.
- One CSS file per domain: `timeline.css`, `viewer.css`, `tv.css`, `components.css`, etc.
- Responsive breakpoints: 480px (mobile), 768px (tablet), 1200px (desktop), 1800px (TV/4K).
- Dark mode via `prefers-color-scheme: dark` media query.

### Dart (app/)
- Riverpod for state management.
- Screens in `lib/screens/`, services in `lib/services/`.

## API Patterns
- Base path: `/api/v1/`
- Auth endpoints: `/pair/init`, `/pair`, `/auth/refresh` (note: no `/auth/` prefix on pair)
- Photos: `/photos`, `/photos/{id}`, `/photos/{id}/thumb`, `/photos/{id}/file`, `/photos/upload`, `/photos/batch`
- Albums: `/albums`, `/albums/{id}`, `/albums/{id}/photos`
- Search: `/search?q=`, `/search/faces`, `/search/scenes`
- All authenticated endpoints require `Authorization: Bearer <token>` header.

## Important Notes
- PIN is not returned in API responses; it's printed to server console only.
- `_photo_to_response()` in `server/api/photos.py` maps model → schema.
- NLU pattern order matters: specific intents BEFORE generic `SEARCH_PLACE`.
- Scene classifier uses EXIF weights + pixel color heuristics (no heavy ML).
- Web SPA served at `/web`, static files at `/static`.

## Language
- UI text is in Korean (한국어).
- Code comments and variable names in English.
