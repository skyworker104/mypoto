"""Voice command executor: maps intents to actions and generates responses.

Enhanced in Phase 2 with:
- Face-based person search (SEARCH_PERSON)
- Favorites search (SEARCH_FAVORITE)
- Greeting handler
- Dialog session context

Enhanced in Phase 3 with:
- Scene search (SEARCH_SCENE)
- Map view (SHOW_MAP)
- Highlight creation (CREATE_HIGHLIGHT)
"""

from sqlmodel import Session, select, func, col

from server.models.photo import Photo
from server.models.album import Album
from server.services.tv_service import (
    control_slideshow,
    get_slideshow_status,
    start_slideshow,
    stop_slideshow,
)
from server.utils.storage import get_storage_info
from server.voice.dialog_session import dialog_manager
from server.voice.nlu_parser import ParseResult


def execute(parsed: ParseResult, session: Session, user_id: str) -> dict:
    """Execute a parsed voice command with dialog context."""
    intent = parsed.intent
    slots = parsed.slots

    # Apply dialog context for follow-up queries
    slots = dialog_manager.apply_context(user_id, intent, slots)

    handler = HANDLERS.get(intent, _handle_unknown)
    result = handler(slots, session, user_id)

    # Update dialog context
    photo_ids = [p["id"] for p in result.get("photos", [])]
    dialog_manager.update_context(user_id, intent, slots, photo_ids)

    return result


def _handle_show_photos(slots: dict, session: Session, user_id: str) -> dict:
    person = slots.get("person")
    query = select(Photo).where(Photo.status == "active")

    if person:
        from server.services.face_service import search_by_person
        photos = search_by_person(person, session, limit=20)
        if photos:
            return {
                "type": "photo_grid",
                "response": f"'{person}' 사진 {len(photos)}장을 찾았어요.",
                "photos": [{"id": p.id, "thumb": f"/api/v1/photos/{p.id}/thumb"} for p in photos],
            }
        query = query.order_by(col(Photo.taken_at).desc()).limit(20)
        photos = list(session.exec(query).all())
        return {
            "type": "photo_grid",
            "response": f"'{person}'(이)라는 이름의 인물을 찾지 못했어요. 최근 사진 {len(photos)}장을 보여드릴게요.",
            "photos": [{"id": p.id, "thumb": f"/api/v1/photos/{p.id}/thumb"} for p in photos],
        }
    else:
        count = session.exec(
            select(func.count()).select_from(Photo).where(Photo.status == "active")
        ).one()
        photos = list(session.exec(
            query.order_by(col(Photo.taken_at).desc()).limit(20)
        ).all())
        return {
            "type": "photo_grid",
            "response": f"전체 {count}장의 사진이 있어요.",
            "photos": [{"id": p.id, "thumb": f"/api/v1/photos/{p.id}/thumb"} for p in photos],
        }


def _handle_search_person(slots: dict, session: Session, user_id: str) -> dict:
    """Search photos by person name (face recognition)."""
    person = slots.get("person", "")
    from server.services.face_service import search_by_person
    photos = search_by_person(person, session, limit=20)

    if photos:
        return {
            "type": "photo_grid",
            "response": f"'{person}' 사진 {len(photos)}장을 찾았어요.",
            "photos": [{"id": p.id, "thumb": f"/api/v1/photos/{p.id}/thumb"} for p in photos],
        }
    return {
        "type": "text",
        "response": f"'{person}'(이)라는 인물을 찾지 못했어요. 검색 탭에서 인물에 이름을 태그해 보세요.",
    }


def _handle_play_slideshow(slots: dict, session: Session, user_id: str) -> dict:
    album_id = slots.get("album")
    result = start_slideshow(db=session, album_id=album_id)
    if result.get("active"):
        return {
            "type": "slideshow",
            "response": f"슬라이드쇼를 시작할게요. {result['total_photos']}장의 사진을 보여드릴게요.",
            "data": result,
        }
    return {
        "type": "text",
        "response": "표시할 사진이 없어요.",
    }


def _handle_control_slideshow(slots: dict, session: Session, user_id: str) -> dict:
    action = slots.get("action", "next")
    result = control_slideshow(action)

    messages = {
        "next": "다음 사진이에요.",
        "prev": "이전 사진이에요.",
        "pause": "잠시 멈출게요.",
        "resume": "다시 재생할게요.",
    }
    return {
        "type": "slideshow_control",
        "response": messages.get(action, "알겠어요."),
        "data": result,
    }


def _handle_search_place(slots: dict, session: Session, user_id: str) -> dict:
    place = slots.get("place", "")
    photos = list(session.exec(
        select(Photo).where(
            Photo.status == "active",
            col(Photo.location_name).contains(place),
        ).order_by(col(Photo.taken_at).desc()).limit(20)
    ).all())

    if photos:
        return {
            "type": "photo_grid",
            "response": f"'{place}'에서 찍은 사진 {len(photos)}장을 찾았어요.",
            "photos": [{"id": p.id, "thumb": f"/api/v1/photos/{p.id}/thumb"} for p in photos],
        }
    return {
        "type": "text",
        "response": f"'{place}' 관련 사진을 찾지 못했어요.",
    }


def _handle_search_date(slots: dict, session: Session, user_id: str) -> dict:
    date_expr = slots.get("date_expr", "")
    from server.services.search_service import _search_by_date_expr
    photos = _search_by_date_expr(date_expr, session)

    if photos:
        return {
            "type": "photo_grid",
            "response": f"'{date_expr}' 사진 {len(photos)}장을 찾았어요.",
            "photos": [{"id": p.id, "thumb": f"/api/v1/photos/{p.id}/thumb"} for p in photos],
        }
    return {
        "type": "text",
        "response": f"'{date_expr}'에 해당하는 사진을 찾지 못했어요.",
    }


def _handle_search_favorite(slots: dict, session: Session, user_id: str) -> dict:
    """Search favorite photos."""
    photos = list(session.exec(
        select(Photo).where(
            Photo.status == "active",
            Photo.is_favorite == True,  # noqa: E712
        ).order_by(col(Photo.taken_at).desc()).limit(20)
    ).all())

    if photos:
        return {
            "type": "photo_grid",
            "response": f"즐겨찾기 사진 {len(photos)}장이에요.",
            "photos": [{"id": p.id, "thumb": f"/api/v1/photos/{p.id}/thumb"} for p in photos],
        }
    return {
        "type": "text",
        "response": "아직 즐겨찾기 사진이 없어요.",
    }


def _handle_show_album(slots: dict, session: Session, user_id: str) -> dict:
    album_name = slots.get("album")
    if album_name:
        album = session.exec(
            select(Album).where(col(Album.name).contains(album_name))
        ).first()
        if album:
            return {
                "type": "album",
                "response": f"'{album.name}' 앨범을 열게요.",
                "album_id": album.id,
            }
    albums = list(session.exec(select(Album)).all())
    return {
        "type": "album_list",
        "response": f"{len(albums)}개의 앨범이 있어요.",
        "albums": [{"id": a.id, "name": a.name} for a in albums],
    }


def _handle_show_memories(slots: dict, session: Session, user_id: str) -> dict:
    from server.services.memory_service import get_memories_today
    memories = get_memories_today(session, limit=5)

    if memories:
        all_photos = []
        response_parts = []
        for m in memories:
            all_photos.extend(m["photos"])
            response_parts.append(f"{m['years_ago']}년 전 {m['photo_count']}장")

        return {
            "type": "photo_grid",
            "response": f"오늘의 추억이에요! {', '.join(response_parts)}",
            "photos": [{"id": p["id"], "thumb": p["thumb_url"]} for p in all_photos[:20]],
        }
    return {
        "type": "text",
        "response": "아직 오늘 날짜에 해당하는 추억 사진이 없어요.",
    }


def _handle_system_status(slots: dict, session: Session, user_id: str) -> dict:
    storage = get_storage_info()
    count = session.exec(
        select(func.count()).select_from(Photo).where(Photo.status == "active")
    ).one()

    free_gb = storage["free_bytes"] / (1024 ** 3)
    return {
        "type": "system_info",
        "response": f"현재 {count}장의 사진이 저장되어 있고, 남은 공간은 {free_gb:.1f}GB에요.",
        "data": {
            "photo_count": count,
            **storage,
        },
    }


def _handle_stop(slots: dict, session: Session, user_id: str) -> dict:
    stop_slideshow()
    dialog_manager.clear(user_id)
    return {
        "type": "text",
        "response": "알겠어요. 종료할게요.",
    }


def _handle_help(slots: dict, session: Session, user_id: str) -> dict:
    return {
        "type": "text",
        "response": (
            "이런 것들을 할 수 있어요:\n"
            "- '사진 보여줘' - 사진 타임라인\n"
            "- '엄마 사진' - 인물 검색\n"
            "- '슬라이드쇼 틀어줘' - TV 슬라이드쇼\n"
            "- '다음 / 이전 / 멈춰' - 슬라이드쇼 제어\n"
            "- '제주도 사진' - 장소 검색\n"
            "- '작년 사진' - 날짜 검색\n"
            "- '추억 사진' - 오늘의 추억\n"
            "- '즐겨찾기 사진' - 좋아요 사진\n"
            "- '음식 사진' - 장면별 검색\n"
            "- '지도 보여줘' - 위치 지도\n"
            "- '하이라이트 만들어' - 하이라이트 영상\n"
            "- '저장 공간' - 시스템 상태\n"
        ),
    }


def _handle_greeting(slots: dict, session: Session, user_id: str) -> dict:
    count = session.exec(
        select(func.count()).select_from(Photo).where(Photo.status == "active")
    ).one()
    return {
        "type": "text",
        "response": f"안녕하세요! 네스티예요. 현재 {count}장의 사진이 있어요. 무엇을 도와드릴까요?",
    }


def _handle_search_scene(slots: dict, session: Session, user_id: str) -> dict:
    """Search photos by scene category."""
    scene = slots.get("scene", "")
    from server.ai.scene_classifier import SCENE_KO_TO_EN
    scene_en = SCENE_KO_TO_EN.get(scene, scene)
    from server.services.scene_service import search_by_scene
    photos = search_by_scene(scene_en, session, limit=20)

    if photos:
        return {
            "type": "photo_grid",
            "response": f"'{scene}' 사진 {len(photos)}장을 찾았어요.",
            "photos": [{"id": p.id, "thumb": f"/api/v1/photos/{p.id}/thumb"} for p in photos],
        }
    return {
        "type": "text",
        "response": f"'{scene}' 카테고리 사진을 찾지 못했어요.",
    }


def _handle_show_map(slots: dict, session: Session, user_id: str) -> dict:
    """Open map view."""
    from server.services.map_service import get_location_clusters
    clusters = get_location_clusters(session, precision=1)

    if clusters:
        locations = [c["location_name"] for c in clusters[:5] if c.get("location_name")]
        loc_text = ", ".join(locations) if locations else ""
        return {
            "type": "map",
            "response": f"{len(clusters)}개 장소에서 찍은 사진이 있어요. {loc_text}",
            "clusters": clusters[:20],
        }
    return {
        "type": "text",
        "response": "위치 정보가 있는 사진이 아직 없어요.",
    }


def _handle_create_highlight(slots: dict, session: Session, user_id: str) -> dict:
    """Create a highlight video."""
    return {
        "type": "highlight",
        "response": "하이라이트 영상을 만들어 드릴게요. 앱에서 제목과 기간을 선택해 주세요.",
        "action": "open_highlight_creator",
    }


def _handle_unknown(slots: dict, session: Session, user_id: str) -> dict:
    return {
        "type": "text",
        "response": "잘 이해하지 못했어요. '도움말'이라고 말해보세요.",
    }


HANDLERS = {
    "SHOW_PHOTOS": _handle_show_photos,
    "SEARCH_PERSON": _handle_search_person,
    "PLAY_SLIDESHOW": _handle_play_slideshow,
    "CONTROL_SLIDESHOW": _handle_control_slideshow,
    "SEARCH_PLACE": _handle_search_place,
    "SEARCH_DATE": _handle_search_date,
    "SEARCH_FAVORITE": _handle_search_favorite,
    "SEARCH_SCENE": _handle_search_scene,
    "SHOW_MAP": _handle_show_map,
    "CREATE_HIGHLIGHT": _handle_create_highlight,
    "SHOW_ALBUM": _handle_show_album,
    "SHOW_MEMORIES": _handle_show_memories,
    "SYSTEM_STATUS": _handle_system_status,
    "STOP": _handle_stop,
    "HELP": _handle_help,
    "GREETING": _handle_greeting,
    "UNKNOWN": _handle_unknown,
}
