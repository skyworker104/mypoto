r"""Natural Language Understanding: intent classification + slot extraction.

Uses regex pattern matching for Korean voice commands.
Enhanced in Phase 2 with more natural language variations.

IMPORTANT: Pattern order matters! More specific patterns MUST come before generic ones.
The generic SEARCH_PLACE pattern (\S{2,}\s+사진$) is especially greedy.
"""

import re
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class ParseResult:
    intent: str
    slots: dict = field(default_factory=dict)
    confidence: float = 1.0
    raw_text: str = ""


# Intent patterns: (intent_name, regex_pattern, slot_extractors)
INTENT_PATTERNS = [
    # PLAY_SLIDESHOW - 슬라이드쇼 틀어줘
    ("PLAY_SLIDESHOW", [
        r"슬라이드쇼\s*(틀어|시작|보여|재생|켜)",
        r"사진\s*(틀어|재생)",
        r"(?P<album>\S+?)\s*앨범\s*(틀어|재생|슬라이드)",
        r"(이거|이\s*사진)\s*(틀어|재생)",
        r"TV\s*에?\s*(보여|틀어|켜)",
    ]),

    # CONTROL_SLIDESHOW - 다음/이전/멈춰
    ("CONTROL_SLIDESHOW", [
        r"^(다음|넘겨|넘어가|스킵)$",
        r"^(이전|뒤로|전에꺼)$",
        r"^(멈춰|일시정지|정지|스톱|중지|꺼)$",
        r"(계속|재개|이어서|다시\s*재생)",
        r"(빨리|느리게|천천히)\s*(넘겨|해)",
    ]),

    # GREETING - 인사 (before STOP to prevent "안녕" matching STOP)
    ("GREETING", [
        r"^(안녕|하이|헬로|네스티)$",
        r"(안녕하세요|반가워)",
    ]),

    # SEARCH_PERSON - 엄마/아빠/이름 사진
    ("SEARCH_PERSON", [
        r"(?P<person>엄마|아빠|할머니|할아버지|언니|오빠|누나|형|동생)\s*(사진|얼굴|찍은\s*거)",
        r"(?P<person>\S{2,4})(?:이|가|의|랑|하고)?\s*(찍은|나온|있는)\s*사진",
    ]),

    # SEARCH_DATE - 작년/어제/지난달 사진
    ("SEARCH_DATE", [
        r"(?P<date_expr>오늘|어제|그제|이번\s*주|지난\s*주|이번\s*달|지난\s*달|올해|작년|재작년)\s*사진",
        r"(?P<date_expr>\d{4}년)\s*사진",
        r"(?P<date_expr>\d{1,2}월)\s*사진",
        r"(?P<date_expr>오늘|어제|그제|이번\s*주|지난\s*주|이번\s*달|지난\s*달|올해|작년|재작년)\s*거",
        r"(?P<date_expr>\d+)년\s*전\s*(오늘\s*)?사진",
    ]),

    # SHOW_MEMORIES - 추억/옛날 사진 (before SEARCH_PLACE!)
    ("SHOW_MEMORIES", [
        r"(추억|옛날|예전)\s*사진",
        r"(\d+)년\s*전\s*(오늘|사진)",
        r"(오늘의?\s*)?추억",
        r"그때\s*사진",
    ]),

    # SEARCH_FAVORITE - 좋아하는/즐겨찾기 사진 (before SEARCH_PLACE!)
    ("SEARCH_FAVORITE", [
        r"(좋아하는|즐겨찾기|하트|좋아요)\s*사진",
        r"(즐겨찾기|하트)\s*(보여|열어)",
    ]),

    # SEARCH_SCENE - 음식/해변/야경 사진 (before SEARCH_PLACE!)
    ("SEARCH_SCENE", [
        r"(?P<scene>음식|해변|산|건물|실내|야외|자연|도시|야경|인물|풍경)\s*사진",
        r"(?P<scene>음식|해변|산|건물|실내|야외|자연|도시|야경|인물|풍경)\s*(보여|찾아)",
    ]),

    # SHOW_MAP - 지도 보기 (before SEARCH_PLACE!)
    ("SHOW_MAP", [
        r"지도\s*(보여|열어|보여줘)",
        r"(위치|장소)\s*(지도|보여|열어)",
        r"어디서\s*찍었",
    ]),

    # CREATE_HIGHLIGHT - 하이라이트 만들기 (before SEARCH_PLACE!)
    ("CREATE_HIGHLIGHT", [
        r"하이라이트\s*(만들|생성|만들어)",
        r"(영상|동영상|비디오)\s*(만들|생성|만들어)",
        r"하이라이트\s*(보여|열어)",
    ]),

    # SHOW_PHOTOS - 사진 보여줘 / 최근 사진 / 새 사진 (before SEARCH_PLACE!)
    ("SHOW_PHOTOS", [
        r"(최근|새)\s*사진",
        r"(?P<person>\S+?)[\s의]*사진\s*(보여|보여줘|보여주세요|열어)",
        r"사진\s*(보여|보여줘|보여주세요)",
        r"(?P<person>\S+?)\s*(사진|얼굴)\s*(보여|보여줘)",
    ]),

    # SEARCH_PLACE - 제주도 사진 (generic - after specific intents!)
    ("SEARCH_PLACE", [
        r"(?P<place>\S{2,})\s*(에서|에서의)\s*(찍은\s*)?사진",
        r"(?P<place>\S{2,})\s*여행\s*사진",
        r"(?P<place>\S{2,})\s+사진$",
        r"(?P<place>\S{2,})\s*(에서|에서의)\s*(찍은|놀았던)\s*거",
    ]),

    # SHOW_ALBUM - 앨범 보여줘
    ("SHOW_ALBUM", [
        r"(?P<album>\S+?)\s*앨범\s*(보여|열어|보여줘)",
        r"앨범\s*(목록|리스트|보여|열어)",
    ]),

    # SYSTEM_STATUS - 상태/저장공간
    ("SYSTEM_STATUS", [
        r"(상태|저장\s*공간|용량|시스템)",
        r"(사진\s*몇\s*장|몇\s*장)",
        r"(남은\s*)?공간",
    ]),

    # STOP - 종료/그만 (removed 안녕 - conflicts with GREETING)
    ("STOP", [
        r"(종료|그만|닫아|끝|나가)",
    ]),

    # HELP - 도움말
    ("HELP", [
        r"(도움|도와줘|뭐\s*할\s*수\s*있|명령어|help)",
        r"(어떤|무슨)\s*(명령|기능)",
    ]),
]


def parse(text: str) -> ParseResult:
    """Parse user text into intent + slots."""
    text = text.strip()
    if not text:
        return ParseResult(intent="UNKNOWN", raw_text=text, confidence=0.0)

    for intent_name, patterns in INTENT_PATTERNS:
        for pattern in patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                slots = {k: v for k, v in match.groupdict().items() if v is not None}

                # Special handling for CONTROL_SLIDESHOW sub-actions
                if intent_name == "CONTROL_SLIDESHOW":
                    action = _detect_control_action(text)
                    slots["action"] = action

                return ParseResult(
                    intent=intent_name,
                    slots=slots,
                    confidence=0.9,
                    raw_text=text,
                )

    return ParseResult(intent="UNKNOWN", raw_text=text, confidence=0.0)


def _detect_control_action(text: str) -> str:
    if re.search(r"(다음|넘겨|넘어가|스킵)", text):
        return "next"
    if re.search(r"(이전|뒤로|전에꺼)", text):
        return "prev"
    if re.search(r"(멈춰|일시정지|정지|스톱|중지|꺼)", text):
        return "pause"
    if re.search(r"(계속|재개|이어서|다시\s*재생)", text):
        return "resume"
    return "next"
