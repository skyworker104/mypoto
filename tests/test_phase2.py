"""Phase 2 Integration Tests - Face recognition, search, memories, voice."""

import sys
import os
import json
import tempfile
from pathlib import Path
from datetime import datetime, timedelta, timezone

# Setup environment for testing
os.environ["PHOTONEST_DATA_DIR"] = tempfile.mkdtemp()
os.environ["PHOTONEST_STORAGE_DIR"] = tempfile.mkdtemp()
os.environ["PHOTONEST_THUMBNAIL_DIR"] = tempfile.mkdtemp()
os.environ["PHOTONEST_AI_DIR"] = tempfile.mkdtemp()
os.environ["PHOTONEST_AI_MODELS_DIR"] = tempfile.mkdtemp()
os.environ["PHOTONEST_DB_PATH"] = os.path.join(os.environ["PHOTONEST_DATA_DIR"], "test.db")

from fastapi.testclient import TestClient

passed = 0
failed = 0
errors = []


def test(name):
    def decorator(func):
        global passed, failed
        try:
            func()
            passed += 1
            print(f"  ✓ {name}")
        except Exception as e:
            failed += 1
            import traceback
            tb = traceback.format_exc().strip().split("\n")[-1]
            errors.append((name, tb))
            print(f"  ✗ {name}: {tb}")
    return decorator


# --- Setup ---
print("\n=== Phase 2 Integration Tests ===\n")

from server.main import app

with TestClient(app) as client:

    # --- 1. Pair and authenticate (reuse from MVP) ---
    print("[Auth Setup]")

    TOKEN = ""
    USER_ID = ""

    @test("Pairing flow")
    def _():
        global TOKEN, USER_ID
        r = client.post("/api/v1/pair/init")
        assert r.status_code == 200, f"pair/init failed: {r.status_code} {r.text}"
        from server.services.auth_service import get_current_pin
        pin = get_current_pin()
        assert pin is not None, "PIN not generated"

        r = client.post("/api/v1/pair", json={
            "pin": pin,
            "device_name": "Test Phone",
            "device_type": "phone",
        })
        assert r.status_code == 200, f"pair failed: {r.status_code} {r.text}"
        data = r.json()
        TOKEN = data["access_token"]
        USER_ID = data["user_id"]

    headers = {"Authorization": f"Bearer {TOKEN}"}

    # Setup user
    @test("User setup")
    def _():
        r = client.post("/api/v1/users/setup", json={
            "nickname": "테스터",
            "password": "test1234",
        }, headers=headers)
        assert r.status_code == 200

    # --- 2. Face API Tests ---
    print("\n[Face API]")

    @test("List faces (empty)")
    def _():
        r = client.get("/api/v1/faces", headers=headers)
        assert r.status_code == 200
        data = r.json()
        assert data["total"] == 0
        assert data["faces"] == []

    @test("AI status endpoint")
    def _():
        r = client.get("/api/v1/faces/status", headers=headers)
        assert r.status_code == 200
        data = r.json()
        assert "ai_available" in data
        assert "total_faces" in data
        assert "named_faces" in data
        assert "queue_size" in data
        assert "total_photo_faces" in data

    # Create a face manually for testing
    @test("Face tagging and retrieval")
    def _():
        from sqlmodel import Session
        from server.database import engine
        from server.models.photo import Face

        with Session(engine) as session:
            face = Face(name="엄마", photo_count=3)
            session.add(face)
            session.commit()
            session.refresh(face)
            global TEST_FACE_ID
            TEST_FACE_ID = face.id

        # List faces should now show our face
        r = client.get("/api/v1/faces?min_photos=1", headers=headers)
        assert r.status_code == 200
        faces = r.json()["faces"]
        assert len(faces) >= 1
        assert any(f["name"] == "엄마" for f in faces)

    @test("Tag face (rename)")
    def _():
        r = client.patch(f"/api/v1/faces/{TEST_FACE_ID}", json={"name": "어머니"}, headers=headers)
        assert r.status_code == 200
        assert r.json()["name"] == "어머니"

    @test("Face photos (empty)")
    def _():
        r = client.get(f"/api/v1/faces/{TEST_FACE_ID}/photos", headers=headers)
        assert r.status_code == 200
        assert r.json()["photos"] == []

    @test("Recluster faces")
    def _():
        r = client.post("/api/v1/faces/recluster", headers=headers)
        assert r.status_code == 200
        data = r.json()
        assert "clusters" in data
        assert "merged" in data

    # --- 3. Search API Tests ---
    print("\n[Search API]")

    @test("Unified search")
    def _():
        r = client.get("/api/v1/search?q=테스트", headers=headers)
        assert r.status_code == 200
        data = r.json()
        assert "query" in data
        assert "persons" in data
        assert "places" in data
        assert "dates" in data
        assert "total" in data

    @test("Search places (empty)")
    def _():
        r = client.get("/api/v1/search/places", headers=headers)
        assert r.status_code == 200
        assert "places" in r.json()

    # --- 4. Memory API Tests ---
    print("\n[Memory API]")

    @test("List memories (empty)")
    def _():
        r = client.get("/api/v1/memories", headers=headers)
        assert r.status_code == 200
        data = r.json()
        assert "memories" in data
        assert isinstance(data["memories"], list)

    @test("Weekly highlights")
    def _():
        r = client.get("/api/v1/memories/highlights", headers=headers)
        assert r.status_code == 200
        assert "highlights" in r.json()

    @test("Memory summary")
    def _():
        r = client.get("/api/v1/memories/summary", headers=headers)
        assert r.status_code == 200
        data = r.json()
        assert "total_photos" in data
        assert "memories_today" in data

    # --- 5. Enhanced NLU Tests ---
    print("\n[Enhanced NLU]")

    from server.voice.nlu_parser import parse

    @test("NLU: SEARCH_PERSON - 엄마 사진")
    def _():
        result = parse("엄마 사진")
        assert result.intent == "SEARCH_PERSON"
        assert result.slots.get("person") == "엄마"

    @test("NLU: SEARCH_PERSON - 아빠 얼굴")
    def _():
        result = parse("아빠 얼굴")
        assert result.intent == "SEARCH_PERSON"
        assert result.slots.get("person") == "아빠"

    @test("NLU: SEARCH_FAVORITE - 즐겨찾기 사진")
    def _():
        result = parse("즐겨찾기 사진")
        assert result.intent == "SEARCH_FAVORITE"

    @test("NLU: SEARCH_FAVORITE - 좋아하는 사진")
    def _():
        result = parse("좋아하는 사진")
        assert result.intent == "SEARCH_FAVORITE"

    @test("NLU: GREETING - 안녕")
    def _():
        result = parse("안녕")
        assert result.intent == "GREETING"

    @test("NLU: GREETING - 안녕하세요")
    def _():
        result = parse("안녕하세요")
        assert result.intent == "GREETING"

    @test("NLU: TV에 보여줘")
    def _():
        result = parse("TV에 보여줘")
        assert result.intent == "PLAY_SLIDESHOW"

    @test("NLU: 추억 사진")
    def _():
        result = parse("추억 사진")
        assert result.intent == "SHOW_MEMORIES"

    @test("NLU: 오늘의 추억")
    def _():
        result = parse("오늘의 추억")
        assert result.intent == "SHOW_MEMORIES"

    @test("NLU: 작년 거 (date with 거)")
    def _():
        result = parse("작년 거")
        assert result.intent == "SEARCH_DATE"
        assert result.slots.get("date_expr") == "작년"

    @test("NLU: 제주도에서 찍은 거")
    def _():
        result = parse("제주도에서 찍은 거")
        assert result.intent == "SEARCH_PLACE"
        assert result.slots.get("place") == "제주도"

    @test("NLU: 최근 사진")
    def _():
        result = parse("최근 사진")
        assert result.intent == "SHOW_PHOTOS"

    @test("NLU: 어떤 명령 (help variant)")
    def _():
        result = parse("어떤 명령")
        assert result.intent == "HELP"

    # MVP NLU backward compat
    @test("NLU: 슬라이드쇼 틀어 (backward compat)")
    def _():
        result = parse("슬라이드쇼 틀어")
        assert result.intent == "PLAY_SLIDESHOW"

    @test("NLU: 작년 사진 (backward compat)")
    def _():
        result = parse("작년 사진")
        assert result.intent == "SEARCH_DATE"

    @test("NLU: 제주도 사진 (backward compat)")
    def _():
        result = parse("제주도 사진")
        assert result.intent == "SEARCH_PLACE"

    # --- 6. Dialog Session Tests ---
    print("\n[Dialog Session]")

    from server.voice.dialog_session import DialogSessionManager

    @test("Dialog context persistence")
    def _():
        mgr = DialogSessionManager()
        ctx = mgr.get_context("user1")
        assert ctx.turn_count == 0

        mgr.update_context("user1", "SEARCH_PERSON", {"person": "엄마"}, ["p1", "p2"])
        ctx = mgr.get_context("user1")
        assert ctx.last_intent == "SEARCH_PERSON"
        assert ctx.last_photos == ["p1", "p2"]
        assert ctx.turn_count == 1

    @test("Dialog context enrichment")
    def _():
        mgr = DialogSessionManager()
        mgr.update_context("user2", "SEARCH_PERSON", {"person": "엄마"})

        # Follow-up "작년 거" should inherit person=엄마
        enriched = mgr.apply_context("user2", "SEARCH_DATE", {"date_expr": "작년"})
        assert enriched.get("person") == "엄마"
        assert enriched.get("date_expr") == "작년"

    @test("Dialog context expiry")
    def _():
        import time
        mgr = DialogSessionManager()
        mgr.update_context("user3", "SHOW_PHOTOS", {})
        ctx = mgr.get_context("user3")
        ctx.last_active_time = time.time() - 60  # expired

        # Should get fresh context
        enriched = mgr.apply_context("user3", "SEARCH_DATE", {"date_expr": "오늘"})
        assert "person" not in enriched  # no inherited context

    # --- 7. Voice Command Executor Tests ---
    print("\n[Command Executor]")

    from sqlmodel import Session as SqlSession
    from server.database import engine
    from server.voice.command_executor import execute

    @test("Execute SEARCH_PERSON handler")
    def _():
        parsed = parse("엄마 사진")
        with SqlSession(engine) as session:
            result = execute(parsed, session, USER_ID)
        assert result["type"] == "text"  # no face embeddings, so "not found"

    @test("Execute SEARCH_FAVORITE handler")
    def _():
        parsed = parse("즐겨찾기 사진")
        with SqlSession(engine) as session:
            result = execute(parsed, session, USER_ID)
        assert result["type"] == "text"  # no favorites yet

    @test("Execute GREETING handler")
    def _():
        parsed = parse("안녕하세요")
        with SqlSession(engine) as session:
            result = execute(parsed, session, USER_ID)
        assert result["type"] == "text"
        assert "네스티" in result["response"]

    @test("Execute SHOW_MEMORIES handler")
    def _():
        parsed = parse("추억 사진")
        with SqlSession(engine) as session:
            result = execute(parsed, session, USER_ID)
        assert result["type"] == "text"  # no old photos in test

    # --- 8. AI Worker Tests ---
    print("\n[AI Worker]")

    @test("AI worker singleton (models not available)")
    def _():
        from server.ai.worker import ai_worker
        assert not ai_worker.available  # no ONNX models in test

    @test("AI worker queue (graceful when unavailable)")
    def _():
        from server.ai.worker import ai_worker
        # Should not crash when models unavailable
        ai_worker.enqueue("fake_photo_id")
        assert ai_worker.queue_size == 0  # not queued because not available

    # --- 9. Face Clustering Tests ---
    print("\n[Face Clustering]")

    import numpy as np
    from server.ai.face_cluster import cluster_faces, find_nearest_face, compute_centroid

    @test("Cluster faces (basic)")
    def _():
        # Create 4 embeddings: 2 similar + 2 similar
        e1 = np.random.randn(512).astype(np.float32)
        e1 /= np.linalg.norm(e1)
        e2 = e1 + np.random.randn(512).astype(np.float32) * 0.01
        e2 /= np.linalg.norm(e2)
        e3 = np.random.randn(512).astype(np.float32)
        e3 /= np.linalg.norm(e3)
        e4 = e3 + np.random.randn(512).astype(np.float32) * 0.01
        e4 /= np.linalg.norm(e4)

        clusters = cluster_faces([e1, e2, e3, e4], ["f1", "f2", "f3", "f4"])
        # Should create at least 2 clusters
        assert len(clusters) >= 2

    @test("Find nearest face")
    def _():
        e1 = np.random.randn(512).astype(np.float32)
        e1 /= np.linalg.norm(e1)
        e2 = e1 + np.random.randn(512).astype(np.float32) * 0.01
        e2 /= np.linalg.norm(e2)
        e3 = np.random.randn(512).astype(np.float32)
        e3 /= np.linalg.norm(e3)

        best_id, dist = find_nearest_face(e2, [e1, e3], ["f1", "f3"], threshold=0.5)
        assert best_id == "f1"
        assert dist < 0.1

    @test("Compute centroid")
    def _():
        e1 = np.array([1.0, 0.0, 0.0], dtype=np.float32)
        e2 = np.array([0.0, 1.0, 0.0], dtype=np.float32)
        centroid = compute_centroid([e1, e2])
        assert abs(np.linalg.norm(centroid) - 1.0) < 0.01

    # --- 10. Face Embedding Utils ---
    print("\n[Embedding Utils]")

    from server.ai.face_embedder import embedding_to_bytes, bytes_to_embedding

    @test("Embedding serialization round-trip")
    def _():
        original = np.random.randn(512).astype(np.float32)
        serialized = embedding_to_bytes(original)
        restored = bytes_to_embedding(serialized)
        assert np.allclose(original, restored)

    # --- 11. Search Service Tests ---
    print("\n[Search Service]")

    from server.services.search_service import _search_by_date_expr

    @test("Date expression parsing: 오늘")
    def _():
        with SqlSession(engine) as session:
            results = _search_by_date_expr("오늘", session)
        # Should not crash, returns empty list
        assert isinstance(results, list)

    @test("Date expression parsing: 작년")
    def _():
        with SqlSession(engine) as session:
            results = _search_by_date_expr("작년", session)
        assert isinstance(results, list)

    @test("Date expression parsing: 2024년")
    def _():
        with SqlSession(engine) as session:
            results = _search_by_date_expr("2024년", session)
        assert isinstance(results, list)

    @test("Date expression parsing: 6월")
    def _():
        with SqlSession(engine) as session:
            results = _search_by_date_expr("6월", session)
        assert isinstance(results, list)

    # --- 12. API Endpoint Registration ---
    print("\n[API Registration]")

    @test("All Phase 2 routers registered")
    def _():
        routes = [r.path for r in app.routes]
        assert "/api/v1/faces" in routes or any("/faces" in r for r in routes)
        assert any("/search" in r for r in routes)
        assert any("/memories" in r for r in routes)

    @test("Endpoint count check")
    def _():
        from fastapi.routing import APIRoute
        api_routes = [r for r in app.routes if isinstance(r, APIRoute)]
        # MVP had 37, Phase 2 adds faces (6) + search (2) + memories (3) = 11 more
        assert len(api_routes) >= 45, f"Expected >=45 API routes, got {len(api_routes)}"
        print(f"    Total API routes: {len(api_routes)}")

# --- Summary ---
print(f"\n{'='*50}")
print(f"Phase 2 Tests: {passed} passed, {failed} failed")
if errors:
    print("\nFailed tests:")
    for name, err in errors:
        print(f"  - {name}: {err}")
print(f"{'='*50}\n")

sys.exit(1 if failed > 0 else 0)
