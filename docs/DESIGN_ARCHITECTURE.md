# PhotoNest - 시스템 아키텍처 설계서

> 전체 시스템 구조, DB 스키마, API 명세, 프로젝트 구조, 배포 구성

---

## 1. 시스템 전체 아키텍처

### 1.1 고수준 시스템 구조도

```
┌─────────────────────────────────────── 가정 내 네트워크 ───────────────────────────────────────┐
│                                                                                                │
│   ┌─ 클라이언트 ──────────────────────────────────┐     ┌─ 서버 (셋탑박스/태블릿) ────────────┐│
│   │                                                │     │                                    ││
│   │  ┌───────────┐  ┌───────────┐  ┌───────────┐ │     │  ┌──────────────────────────────┐  ││
│   │  │  Flutter   │  │  Flutter   │  │   Web     │ │     │  │     PhotoNest Server         │  ││
│   │  │  Mobile    │  │  TV App    │  │  Browser  │ │     │  │     (Termux + Python)        │  ││
│   │  │  App       │  │  (Display) │  │  (React)  │ │     │  │                              │  ││
│   │  │           │  │           │  │           │ │     │  │  ┌────────────────────────┐  │  ││
│   │  │  iOS/AOS  │  │  셋탑/태블릿│  │  PC/Mac  │ │     │  │  │   FastAPI Application  │  │  ││
│   │  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘ │     │  │  │                        │  │  ││
│   │        │              │              │        │     │  │  │  REST API + WebSocket   │  │  ││
│   └────────┼──────────────┼──────────────┼────────┘     │  │  └───────────┬────────────┘  │  ││
│            │              │              │              │  │              │               │  ││
│            └──────────────┴──────────────┘              │  │  ┌───────────┴────────────┐  │  ││
│                           │                             │  │  │    Service Layer        │  │  ││
│                    ┌──────┴───────┐                     │  │  │                        │  │  ││
│                    │   Wi-Fi LAN  │                     │  │  │  Auth │ Photo │ Album  │  │  ││
│                    │   (mDNS)     │                     │  │  │  AI   │ Voice │ Memory │  │  ││
│                    └──────┬───────┘                     │  │  │  TV   │ Family│ Backup │  │  ││
│                           │                             │  │  └───────────┬────────────┘  │  ││
│                           └─────────────────────────────│──│              │               │  ││
│                                                         │  │  ┌───────────┴────────────┐  │  ││
│                                                         │  │  │    Data Layer           │  │  ││
│                                                         │  │  │                        │  │  ││
│                                                         │  │  │  SQLite │ FileSystem   │  │  ││
│                                                         │  │  │  (DB)   │ (SD Card)    │  │  ││
│                                                         │  │  └────────────────────────┘  │  ││
│                                                         │  └──────────────────────────────┘  ││
│                                                         │                                    ││
│                                                         │  ┌──── 부가 서비스 ──────────────┐  ││
│                                                         │  │  OpenWakeWord │ Vosk/Whisper  │  ││
│                                                         │  │  (Wake Word)  │ (STT)         │  ││
│                                                         │  │  Android TTS  │ FCM Push      │  ││
│                                                         │  └──────────────────────────────┘  ││
│                                                         └────────────────────────────────────┘│
│                                                                                                │
└──────────────────────────────────────────────────────────────────────────────────────┬─────────┘
                                                                                       │
                                                                              (VPN/Tailscale)
                                                                                       │
                                                                            ┌──────────┴──────┐
                                                                            │  외부 서비스     │
                                                                            │  (선택적)       │
                                                                            │                 │
                                                                            │ Google Vision   │
                                                                            │ Google STT      │
                                                                            │ FCM Server      │
                                                                            │ Geocoding API   │
                                                                            └─────────────────┘
```

### 1.2 서버 레이어드 아키텍처

```
┌──────────────────────────────────────────────────────────────────┐
│                        Presentation Layer                        │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌───────────┐ │
│  │ REST API   │  │ WebSocket  │  │ Static     │  │ mDNS      │ │
│  │ Endpoints  │  │ Handlers   │  │ File       │  │ Broadcast │ │
│  │            │  │            │  │ Server     │  │           │ │
│  │ /api/v1/*  │  │ /ws/*      │  │ /web/*     │  │ _photonest│ │
│  └────────────┘  └────────────┘  └────────────┘  └───────────┘ │
├──────────────────────────────────────────────────────────────────┤
│                        Service Layer                             │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │  Auth    │ │  Photo   │ │  Album   │ │  Family  │           │
│  │  Service │ │  Service │ │  Service │ │  Service │           │
│  ├──────────┤ ├──────────┤ ├──────────┤ ├──────────┤           │
│  │  Backup  │ │  Search  │ │  Voice   │ │  Memory  │           │
│  │  Service │ │  Service │ │  Service │ │  Service │           │
│  ├──────────┤ ├──────────┤ ├──────────┤ ├──────────┤           │
│  │  TV      │ │  AI      │ │  Device  │ │  Storage │           │
│  │  Service │ │  Service │ │  Service │ │  Service │           │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │
├──────────────────────────────────────────────────────────────────┤
│                        Data Access Layer                         │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────────┐ │
│  │  SQLite DAL    │  │  FileSystem    │  │  Cache Manager     │ │
│  │                │  │  Manager       │  │                    │ │
│  │  ORM: SQLModel │  │  원본/썸네일    │  │  썸네일 캐시       │ │
│  │  (Pydantic +   │  │  저장/조회     │  │  검색 결과 캐시    │ │
│  │   SQLAlchemy)  │  │               │  │  세션 캐시         │ │
│  └────────────────┘  └────────────────┘  └────────────────────┘ │
├──────────────────────────────────────────────────────────────────┤
│                        Infrastructure Layer                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │  SQLite  │ │  SD Card │ │  Termux  │ │  Android │           │
│  │  DB File │ │  Storage │ │  :Boot   │ │  TTS/Mic │           │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. 핵심 데이터 플로우

### 2.1 사진 백업 플로우

```
Flutter App                        FastAPI Server                    Storage
    │                                    │                              │
    │  1. GET /api/v1/sync/status        │                              │
    │───────────────────────────────────►│                              │
    │   (마지막 동기화 시간 조회)          │                              │
    │◄───────────────────────────────────│                              │
    │                                    │                              │
    │  2. POST /api/v1/photos/check      │                              │
    │   {hashes: ["abc123", ...]}        │                              │
    │───────────────────────────────────►│                              │
    │   (중복 체크 - 해시 비교)           │  SELECT hash FROM photos     │
    │◄───────────────────────────────────│                              │
    │   {new: ["abc123"], dup: [...]}    │                              │
    │                                    │                              │
    │  3. POST /api/v1/photos/upload     │                              │
    │   multipart: file + metadata       │                              │
    │───────────────────────────────────►│                              │
    │                                    │  4. 원본 저장 ───────────────►│
    │                                    │  5. 썸네일 생성 ─────────────►│
    │                                    │  6. EXIF 추출                │
    │                                    │  7. DB INSERT                │
    │◄───────────────────────────────────│                              │
    │   {photo_id, status: "ok"}         │                              │
    │                                    │                              │
    │         WebSocket: 진행률 업데이트   │                              │
    │◄══════════════════════════════════►│                              │
    │                                    │                              │
    │                                    │  8. AI 큐에 추가 (비동기)     │
    │                                    │─────► [AI Worker]            │
    │                                    │       얼굴 감지              │
    │                                    │       임베딩 생성            │
    │                                    │       분류 태깅              │
```

### 2.2 음성 명령 플로우

```
Phone App                          FastAPI Server                    TV Display
    │                                    │                              │
    │  1. WebSocket 연결                  │                              │
    │══════════════════════════════════►  │                              │
    │                                    │                              │
    │  2. {type: "text_command",         │                              │
    │      text: "엄마 사진 보여줘"}      │                              │
    │───────────────────────────────────►│                              │
    │                                    │  3. NLU 파싱                  │
    │                                    │     intent: SHOW_PHOTOS      │
    │                                    │     slot: person="엄마"       │
    │                                    │                              │
    │                                    │  4. DB 쿼리 실행              │
    │                                    │     SELECT photos             │
    │                                    │     WHERE face = "엄마"       │
    │                                    │                              │
    │  5. {type: "command_result",       │  6. {type: "display_sync",   │
    │      photos: [...],                │      screen: "photo_grid",   │
    │      response: "1,234장 찾았어요"} │      photos: [...]}          │
    │◄───────────────────────────────────│──────────────────────────────►│
    │                                    │                              │
    │   앱에 결과 표시                    │            TV에 사진 그리드 표시│
```

### 2.3 서버-폰 페어링 플로우

```
Phone App                     FastAPI Server                   TV/Tablet Screen
    │                              │                                │
    │  1. mDNS 스캔                │  서버: mDNS 서비스 등록          │
    │  _photonest._tcp.local      │  _photonest._tcp.local:8080    │
    │─────── 발견! ───────────────►│                                │
    │                              │                                │
    │  2. POST /api/v1/pair/init   │                                │
    │───────────────────────────►  │  3. PIN 생성 (6자리, 5분 유효)  │
    │                              │─────────────────────────────►  │
    │                              │     화면에 PIN 표시: "472918"   │
    │                              │                                │
    │  4. POST /api/v1/pair        │                                │
    │  {pin: "472918",             │                                │
    │   device_name: "엄마 iPhone"}│                                │
    │───────────────────────────►  │  5. PIN 검증                   │
    │                              │  6. 계정 생성/연결              │
    │  {device_id, tokens}         │  7. JWT 토큰 발급              │
    │◄─────────────────────────────│                                │
    │                              │  화면: "엄마 iPhone 연결됨!"    │
    │  8. 페어링 완료!              │──────────────────────────────►│
    │     자동 백업 시작            │                                │
```

---

## 3. 데이터베이스 스키마

### 3.1 ER 다이어그램

```
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│    users     │       │   devices    │       │   families   │
├──────────────┤       ├──────────────┤       ├──────────────┤
│ id (PK)      │◄──┐   │ id (PK)      │       │ id (PK)      │
│ family_id(FK)│───┼──►│ user_id (FK) │   ┌──►│ name         │
│ nickname     │   │   │ device_name  │   │   │ created_at   │
│ password_hash│   │   │ device_type  │   │   └──────────────┘
│ role         │   │   │ token_hash   │   │
│ avatar_url   │   │   │ last_seen    │   │
│ created_at   │   │   │ status       │   │
└──────┬───────┘   │   └──────────────┘   │
       │           │                       │
       │           └───────────────────────┘
       │
       │ 1:N
       ▼
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│    photos    │       │  photo_faces │       │    faces     │
├──────────────┤       ├──────────────┤       ├──────────────┤
│ id (PK)      │◄─────►│ photo_id(FK) │   ┌──►│ id (PK)      │
│ user_id (FK) │       │ face_id (FK) │───┘   │ user_id (FK) │
│ file_hash    │       │ bbox_x       │       │ name         │
│ file_path    │       │ bbox_y       │       │ embedding    │
│ thumb_path   │       │ bbox_w       │       │ photo_count  │
│ file_size    │       │ bbox_h       │       │ created_at   │
│ mime_type    │       │ confidence   │       └──────────────┘
│ width        │       └──────────────┘
│ height       │
│ taken_at     │       ┌──────────────┐       ┌──────────────┐
│ latitude     │       │ photo_albums │       │    albums    │
│ longitude    │       ├──────────────┤       ├──────────────┤
│ location_name│       │ photo_id(FK) │   ┌──►│ id (PK)      │
│ camera_make  │◄─────►│ album_id(FK) │───┘   │ user_id (FK) │
│ camera_model │       │ added_at     │       │ name         │
│ exif_data    │       └──────────────┘       │ type         │
│ ai_tags      │                              │ cover_photo  │
│ ai_scene     │       ┌──────────────┐       │ is_shared    │
│ is_favorite  │       │album_members │       │ created_at   │
│ is_video     │       ├──────────────┤       └──────┬───────┘
│ duration     │       │ album_id(FK) │──────────────┘
│ status       │       │ user_id (FK) │
│ created_at   │       │ role         │
│ updated_at   │       └──────────────┘
└──────┬───────┘
       │
       │ 1:N
       ▼
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│   comments   │       │   invites    │       │  memories    │
├──────────────┤       ├──────────────┤       ├──────────────┤
│ id (PK)      │       │ id (PK)      │       │ id (PK)      │
│ photo_id(FK) │       │ family_id(FK)│       │ user_id (FK) │
│ user_id (FK) │       │ created_by   │       │ type         │
│ content      │       │ invite_code  │       │ title        │
│ emoji        │       │ invite_token │       │ photo_ids    │
│ created_at   │       │ role         │       │ trigger_date │
└──────────────┘       │ expires_at   │       │ sent_at      │
                       │ used_at      │       │ status       │
                       └──────────────┘       └──────────────┘

┌──────────────┐       ┌──────────────┐
│ voice_sessions│      │  ai_tasks    │
├──────────────┤       ├──────────────┤
│ id (PK)      │       │ id (PK)      │
│ user_id (FK) │       │ photo_id(FK) │
│ device_name  │       │ task_type    │
│ context_json │       │ status       │
│ last_active  │       │ result_json  │
│ created_at   │       │ created_at   │
└──────────────┘       │ completed_at │
                       └──────────────┘
```

### 3.2 테이블 상세 명세

#### users (사용자)
```sql
CREATE TABLE users (
    id            TEXT PRIMARY KEY,        -- "usr_" + 8자리 랜덤
    family_id     TEXT NOT NULL REFERENCES families(id),
    nickname      TEXT NOT NULL,           -- 표시 이름 ("엄마", "아빠")
    password_hash TEXT NOT NULL,           -- bcrypt 해시
    role          TEXT NOT NULL DEFAULT 'member',  -- 'admin' | 'member'
    avatar_url    TEXT,                    -- 프로필 사진 경로
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### photos (사진/동영상)
```sql
CREATE TABLE photos (
    id            TEXT PRIMARY KEY,        -- "pho_" + 8자리 랜덤
    user_id       TEXT NOT NULL REFERENCES users(id),
    file_hash     TEXT NOT NULL UNIQUE,    -- SHA-256 (중복 방지)
    file_path     TEXT NOT NULL,           -- 원본 파일 경로
    thumb_path    TEXT,                    -- 썸네일 파일 경로
    file_size     INTEGER NOT NULL,        -- 바이트
    mime_type     TEXT NOT NULL,           -- "image/jpeg", "video/mp4"
    width         INTEGER,
    height        INTEGER,
    taken_at      TEXT,                    -- EXIF 촬영일시
    latitude      REAL,                   -- GPS 위도
    longitude     REAL,                   -- GPS 경도
    location_name TEXT,                   -- 역지오코딩 결과 ("제주도")
    camera_make   TEXT,                   -- "Apple"
    camera_model  TEXT,                   -- "iPhone 15 Pro"
    exif_data     TEXT,                   -- JSON: 전체 EXIF
    ai_tags       TEXT,                   -- JSON: ["음식", "실내"]
    ai_scene      TEXT,                   -- "restaurant"
    is_favorite   INTEGER DEFAULT 0,
    is_video      INTEGER DEFAULT 0,
    duration      REAL,                   -- 동영상 길이 (초)
    status        TEXT DEFAULT 'active',  -- 'active' | 'deleted'
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 성능 인덱스
CREATE INDEX idx_photos_user_taken ON photos(user_id, taken_at DESC);
CREATE INDEX idx_photos_hash ON photos(file_hash);
CREATE INDEX idx_photos_location ON photos(location_name);
CREATE INDEX idx_photos_taken ON photos(taken_at DESC);
```

#### faces (인물)
```sql
CREATE TABLE faces (
    id            TEXT PRIMARY KEY,        -- "fac_" + 8자리 랜덤
    user_id       TEXT REFERENCES users(id), -- 누가 이름 태깅했나
    name          TEXT,                    -- "엄마" (태깅 전엔 NULL)
    embedding     BLOB,                   -- 얼굴 임베딩 벡터 (512차원 float)
    photo_count   INTEGER DEFAULT 0,
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### albums (앨범)
```sql
CREATE TABLE albums (
    id            TEXT PRIMARY KEY,        -- "alb_" + 8자리 랜덤
    user_id       TEXT NOT NULL REFERENCES users(id),  -- 생성자
    name          TEXT NOT NULL,
    type          TEXT NOT NULL DEFAULT 'manual',  -- 'manual'|'shared'|'auto'
    cover_photo   TEXT REFERENCES photos(id),
    is_shared     INTEGER DEFAULT 0,
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### families (가족 그룹)
```sql
CREATE TABLE families (
    id            TEXT PRIMARY KEY,        -- "fam_" + 8자리 랜덤
    name          TEXT NOT NULL DEFAULT '우리 가족',
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### devices (등록 기기)
```sql
CREATE TABLE devices (
    id            TEXT PRIMARY KEY,        -- "dev_" + 8자리 랜덤
    user_id       TEXT NOT NULL REFERENCES users(id),
    device_name   TEXT NOT NULL,           -- "엄마 iPhone"
    device_type   TEXT NOT NULL,           -- "ios" | "android"
    device_model  TEXT,                    -- "iPhone 15"
    token_hash    TEXT,                    -- refresh token 해시
    last_seen     TEXT,
    status        TEXT DEFAULT 'paired'    -- 'paired'|'revoked'
);
```

---

## 4. REST API 전체 명세

### 4.1 API 개요

| 항목 | 값 |
|------|---|
| Base URL | `https://{server_ip}:8080/api/v1` |
| 인증 | `Authorization: Bearer {access_token}` |
| 형식 | JSON (Content-Type: application/json) |
| 파일 업로드 | multipart/form-data |

### 4.2 인증 & 페어링 API

```
POST   /pair/init              서버에 PIN 생성 요청 (TV/태블릿 화면에 표시)
POST   /pair                   PIN 입력 → 기기 등록 + 토큰 발급
POST   /auth/refresh           Access Token 갱신
POST   /auth/logout            로그아웃 (토큰 무효화)
```

#### POST /pair/init
```json
요청: (인증 불필요)
{}

응답 200:
{
  "pin_displayed": true,
  "expires_in": 300,
  "message": "서버 화면에 표시된 PIN을 입력하세요"
}
```

#### POST /pair
```json
요청: (인증 불필요)
{
  "pin": "472918",
  "device_name": "엄마 iPhone",
  "device_type": "ios",
  "device_model": "iPhone 15",
  "app_version": "1.0.0"
}

응답 200:
{
  "device_id": "dev_f7e8d9c0",
  "user_id": "usr_a1b2c3d4",
  "access_token": "eyJhbG...",
  "refresh_token": "eyJhbG...",
  "server_name": "거실 셋탑",
  "is_new_user": true
}

응답 401:
{
  "error": "invalid_pin",
  "remaining_attempts": 3
}
```

### 4.3 사용자 API

```
GET    /users/me               내 프로필 조회
PATCH  /users/me               내 프로필 수정 (닉네임, 아바타)
POST   /users/setup            최초 계정 설정 (닉네임 + 비밀번호)
```

### 4.4 가족 API

```
GET    /family                 가족 정보 + 구성원 목록
POST   /family/invite          초대 코드 생성
POST   /family/join            초대 코드로 가족 합류
DELETE /family/members/{id}    구성원 제거 (관리자만)
```

#### POST /family/invite
```json
요청:
{
  "role": "member",
  "nickname_hint": "아빠",
  "expires_in": 86400
}

응답 200:
{
  "invite_code": "47291835",
  "invite_token": "inv_x9y8z7...",
  "invite_url": "photonest://invite?token=inv_x9y8z7&host=192.168.1.100:8080",
  "qr_data": "photonest://invite?token=inv_x9y8z7&host=192.168.1.100:8080",
  "expires_at": "2026-02-11T15:30:00Z"
}
```

### 4.5 기기 관리 API

```
GET    /devices                등록된 기기 목록
PATCH  /devices/{id}           기기 이름 변경
DELETE /devices/{id}           기기 페어링 해제
```

### 4.6 사진 API (핵심)

```
POST   /photos/check           중복 체크 (해시 배열 전송)
POST   /photos/upload          사진 업로드 (multipart)
GET    /photos                 사진 목록 (타임라인, 페이지네이션)
GET    /photos/{id}            사진 상세 정보
GET    /photos/{id}/file       원본 파일 다운로드
GET    /photos/{id}/thumb      썸네일 다운로드
PATCH  /photos/{id}            사진 수정 (즐겨찾기 등)
DELETE /photos/{id}            사진 삭제 (soft delete)
POST   /photos/batch           다중 작업 (삭제, 앨범추가 등)
```

#### POST /photos/check
```json
요청:
{
  "hashes": ["sha256_abc123...", "sha256_def456..."]
}

응답 200:
{
  "existing": ["sha256_abc123..."],
  "new": ["sha256_def456..."]
}
```

#### POST /photos/upload
```
Content-Type: multipart/form-data

Fields:
  file: (binary)            원본 파일
  hash: "sha256_def456..."  사전 계산된 해시
  taken_at: "2026-02-10T15:42:00"  (선택)
  latitude: 33.4507         (선택)
  longitude: 126.5706       (선택)

응답 200:
{
  "photo_id": "pho_x1y2z3",
  "thumb_url": "/api/v1/photos/pho_x1y2z3/thumb",
  "status": "uploaded",
  "ai_status": "queued"
}
```

#### GET /photos
```
쿼리 파라미터:
  cursor       커서 기반 페이지네이션 (taken_at ISO 문자열)
  limit        한 페이지 사진 수 (기본 50, 최대 200)
  user_id      특정 사용자 사진만 (선택)
  date_from    시작 날짜 (YYYY-MM-DD)
  date_to      종료 날짜
  face_id      특정 인물 사진만
  album_id     특정 앨범 사진만
  is_favorite  즐겨찾기만 (true/false)
  is_video     동영상만 (true/false)
  q            텍스트 검색 (위치, 태그)

응답 200:
{
  "photos": [
    {
      "id": "pho_x1y2z3",
      "thumb_url": "/api/v1/photos/pho_x1y2z3/thumb",
      "taken_at": "2026-02-10T15:42:00",
      "is_video": false,
      "is_favorite": false,
      "width": 4032,
      "height": 3024,
      "duration": null
    }
  ],
  "next_cursor": "2026-02-09T23:59:59",
  "has_more": true,
  "total_count": 15234
}
```

### 4.7 앨범 API

```
GET    /albums                 앨범 목록 (내 앨범 + 공유 앨범)
POST   /albums                 앨범 생성
GET    /albums/{id}            앨범 상세 (사진 목록 포함)
PATCH  /albums/{id}            앨범 수정 (이름, 커버)
DELETE /albums/{id}            앨범 삭제
POST   /albums/{id}/photos     앨범에 사진 추가
DELETE /albums/{id}/photos     앨범에서 사진 제거
POST   /albums/{id}/share      앨범 공유 설정
```

#### POST /albums
```json
요청:
{
  "name": "2025 제주여행",
  "type": "shared",
  "photo_ids": ["pho_x1y2z3", "pho_a4b5c6"],
  "shared_with": ["usr_d7e8f9"]
}

응답 201:
{
  "id": "alb_m1n2o3",
  "name": "2025 제주여행",
  "type": "shared",
  "photo_count": 2,
  "members": [
    {"user_id": "usr_a1b2c3", "role": "owner"},
    {"user_id": "usr_d7e8f9", "role": "member"}
  ]
}
```

### 4.8 검색 API

```
GET    /search                 통합 검색
GET    /search/faces           인물 목록 (얼굴 클러스터)
GET    /search/places          장소 목록
GET    /search/tags            태그/카테고리 목록
```

#### GET /search
```
쿼리 파라미터:
  q              검색어 ("엄마 제주도 2024")
  face_id        인물 ID
  place          장소명
  date_from      시작 날짜
  date_to        종료 날짜
  tag            AI 태그
  limit          결과 수

응답 200:
{
  "photos": [...],
  "total_count": 87,
  "parsed_query": {
    "person": "엄마",
    "place": "제주도",
    "date_range": "2024"
  }
}
```

### 4.9 인물(얼굴) API

```
GET    /faces                  인물 목록 (클러스터)
PATCH  /faces/{id}             인물 이름 태깅
POST   /faces/merge            인물 클러스터 병합
DELETE /faces/{id}             인물 삭제
```

### 4.10 TV 슬라이드쇼 API

```
POST   /tv/slideshow/start     슬라이드쇼 시작
POST   /tv/slideshow/stop      슬라이드쇼 정지
POST   /tv/slideshow/control   제어 (다음/이전/일시정지)
GET    /tv/slideshow/status    현재 상태
```

#### POST /tv/slideshow/start
```json
요청:
{
  "source": {
    "type": "album",           -- "album" | "face" | "date_range" | "all"
    "album_id": "alb_m1n2o3"  -- type에 따라 다른 필드
  },
  "interval": 5,              -- 초
  "order": "random",          -- "random" | "date_asc" | "date_desc"
  "transition": "fade"        -- "fade" | "slide" | "zoom"
}

응답 200:
{
  "session_id": "ss_p1q2r3",
  "total_photos": 48,
  "status": "playing"
}
```

### 4.11 추억 알림 API

```
GET    /memories               오늘의 추억 목록
GET    /memories/settings      알림 설정 조회
PATCH  /memories/settings      알림 설정 변경
```

### 4.12 음성 비서 API

```
GET    /voice/settings         음성 비서 설정
PATCH  /voice/settings         설정 변경
GET    /voice/history          대화 내역
DELETE /voice/history          대화 내역 삭제
```

### 4.13 시스템 API

```
GET    /system/status          서버 상태 (저장공간, 사진 수 등)
GET    /system/storage         저장소 상세 정보
POST   /system/backup-db       DB 수동 백업
GET    /sync/status            동기화 상태
```

#### GET /system/status
```json
응답 200:
{
  "server_name": "거실 셋탑",
  "version": "1.0.0",
  "uptime": 86400,
  "storage": {
    "total_bytes": 274877906944,
    "used_bytes": 48318382080,
    "photo_count": 15234,
    "video_count": 342
  },
  "family": {
    "name": "우리 가족",
    "member_count": 4,
    "online_count": 2
  },
  "ai": {
    "queue_size": 12,
    "faces_count": 25,
    "processing": false
  }
}
```

### 4.14 WebSocket 엔드포인트

```
ws://{server}:8080/ws/sync         백업 진행률 + 실시간 동기화
ws://{server}:8080/ws/tv           TV 슬라이드쇼 제어 + 상태
ws://{server}:8080/ws/voice        음성 명령 + 대화
ws://{server}:8080/ws/activity     가족 활동 피드
ws://{server}:8080/ws/display      서버 화면 동기화 (TV/태블릿)
```

---

## 5. 파일 저장소 구조

```
{STORAGE_ROOT}/                          ← SD 카드 루트
├── photonest/
│   ├── data/
│   │   ├── photonest.db                 ← SQLite 메인 DB
│   │   ├── photonest.db-wal             ← WAL 로그
│   │   └── backups/                     ← DB 자동 백업
│   │       ├── photonest_20260210.db
│   │       └── photonest_20260209.db
│   │
│   ├── originals/                       ← 원본 사진/동영상
│   │   ├── 2026/
│   │   │   ├── 02/
│   │   │   │   ├── 10/
│   │   │   │   │   ├── pho_x1y2z3.jpg
│   │   │   │   │   ├── pho_a4b5c6.heic
│   │   │   │   │   └── pho_m7n8o9.mp4
│   │   │   │   └── 09/
│   │   │   │       └── ...
│   │   │   └── 01/
│   │   └── 2025/
│   │       └── ...
│   │
│   ├── thumbnails/                      ← 썸네일 (자동 생성)
│   │   ├── small/                       ← 200x200 (그리드용)
│   │   │   ├── pho_x1y2z3.webp
│   │   │   └── ...
│   │   └── medium/                      ← 800x800 (미리보기용)
│   │       ├── pho_x1y2z3.webp
│   │       └── ...
│   │
│   ├── ai/                              ← AI 모델 + 데이터
│   │   ├── models/
│   │   │   ├── face_detect.tflite       ← 얼굴 감지 모델
│   │   │   ├── face_embed.tflite        ← 얼굴 임베딩 모델
│   │   │   └── vosk-model-ko/           ← Vosk 한국어 모델
│   │   └── cache/
│   │       └── geocode_cache.json       ← 역지오코딩 캐시
│   │
│   ├── certs/                           ← HTTPS 인증서
│   │   ├── server.crt
│   │   └── server.key
│   │
│   └── logs/                            ← 로그 파일
│       ├── server.log
│       └── ai_worker.log
```

---

## 6. 프로젝트 소스 코드 구조

```
photonest/
├── server/                              ← 백엔드 (Python + FastAPI)
│   ├── main.py                          ← FastAPI 앱 엔트리포인트
│   ├── config.py                        ← 설정 관리
│   ├── database.py                      ← SQLite 연결 + 초기화
│   │
│   ├── api/                             ← API 라우터
│   │   ├── __init__.py
│   │   ├── auth.py                      ← 인증 + 페어링
│   │   ├── photos.py                    ← 사진 CRUD
│   │   ├── albums.py                    ← 앨범 관리
│   │   ├── family.py                    ← 가족 + 초대
│   │   ├── devices.py                   ← 기기 관리
│   │   ├── search.py                    ← 검색
│   │   ├── faces.py                     ← 인물(얼굴)
│   │   ├── tv.py                        ← TV 슬라이드쇼
│   │   ├── voice.py                     ← 음성 비서
│   │   ├── memories.py                  ← 추억 알림
│   │   └── system.py                    ← 시스템 상태
│   │
│   ├── ws/                              ← WebSocket 핸들러
│   │   ├── __init__.py
│   │   ├── sync.py                      ← 백업 동기화
│   │   ├── tv.py                        ← TV 제어
│   │   ├── voice.py                     ← 음성 명령
│   │   ├── activity.py                  ← 활동 피드
│   │   └── display.py                   ← 서버 화면 동기화
│   │
│   ├── services/                        ← 비즈니스 로직
│   │   ├── __init__.py
│   │   ├── auth_service.py
│   │   ├── photo_service.py
│   │   ├── album_service.py
│   │   ├── backup_service.py
│   │   ├── search_service.py
│   │   ├── family_service.py
│   │   ├── tv_service.py
│   │   ├── voice_service.py
│   │   ├── memory_service.py
│   │   └── storage_service.py
│   │
│   ├── ai/                              ← AI 처리
│   │   ├── __init__.py
│   │   ├── worker.py                    ← 백그라운드 AI 워커
│   │   ├── face_detector.py             ← 얼굴 감지
│   │   ├── face_embedder.py             ← 얼굴 임베딩 + 클러스터링
│   │   ├── scene_classifier.py          ← 장면 분류
│   │   ├── exif_extractor.py            ← EXIF 메타데이터 추출
│   │   └── geocoder.py                  ← GPS → 주소 변환
│   │
│   ├── voice/                           ← 음성 비서 엔진
│   │   ├── __init__.py
│   │   ├── wake_word.py                 ← OpenWakeWord 통합
│   │   ├── stt_engine.py                ← Vosk/Whisper STT
│   │   ├── nlu_parser.py                ← 자연어 명령 파싱
│   │   ├── command_executor.py          ← 명령 실행기
│   │   └── tts_engine.py                ← TTS 출력
│   │
│   ├── models/                          ← 데이터 모델 (SQLModel)
│   │   ├── __init__.py
│   │   ├── user.py
│   │   ├── photo.py
│   │   ├── album.py
│   │   ├── face.py
│   │   ├── device.py
│   │   ├── family.py
│   │   └── memory.py
│   │
│   ├── schemas/                         ← Pydantic 스키마 (API 요청/응답)
│   │   ├── __init__.py
│   │   ├── auth.py
│   │   ├── photo.py
│   │   ├── album.py
│   │   └── ...
│   │
│   ├── utils/                           ← 유틸리티
│   │   ├── __init__.py
│   │   ├── hash.py                      ← 파일 해시 계산
│   │   ├── image.py                     ← 이미지 처리 (썸네일, HEIC 변환)
│   │   ├── mdns.py                      ← mDNS 서비스 등록
│   │   └── security.py                  ← JWT, 암호화
│   │
│   ├── requirements.txt
│   └── Dockerfile                       ← (선택) 컨테이너화
│
├── app/                                 ← Flutter 모바일 앱
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart
│   │   │
│   │   ├── config/                      ← 앱 설정
│   │   │   ├── routes.dart
│   │   │   └── theme.dart
│   │   │
│   │   ├── models/                      ← 데이터 모델
│   │   │   ├── photo.dart
│   │   │   ├── album.dart
│   │   │   ├── user.dart
│   │   │   └── ...
│   │   │
│   │   ├── services/                    ← API 통신 + 비즈니스 로직
│   │   │   ├── api_client.dart          ← HTTP + WebSocket 클라이언트
│   │   │   ├── auth_service.dart
│   │   │   ├── photo_service.dart
│   │   │   ├── backup_service.dart
│   │   │   ├── discovery_service.dart   ← mDNS 서버 탐색
│   │   │   └── voice_service.dart
│   │   │
│   │   ├── providers/                   ← 상태 관리 (Riverpod)
│   │   │   ├── auth_provider.dart
│   │   │   ├── photo_provider.dart
│   │   │   └── ...
│   │   │
│   │   ├── screens/                     ← 화면
│   │   │   ├── onboarding/
│   │   │   ├── pairing/
│   │   │   ├── home/                    ← 사진 탭 (타임라인)
│   │   │   ├── search/
│   │   │   ├── album/
│   │   │   ├── family/
│   │   │   ├── tv/
│   │   │   ├── voice/                   ← 음성 명령
│   │   │   ├── viewer/                  ← 사진 뷰어
│   │   │   └── settings/
│   │   │
│   │   └── widgets/                     ← 공통 위젯
│   │       ├── photo_grid.dart
│   │       ├── photo_tile.dart
│   │       ├── memory_card.dart
│   │       └── ...
│   │
│   ├── pubspec.yaml
│   └── ...
│
├── display/                             ← 서버 디스플레이 앱 (Flutter)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   │   ├── idle_screen.dart         ← 대기 화면 (시계 + 추억)
│   │   │   ├── voice_screen.dart        ← 음성 대화 화면
│   │   │   ├── slideshow_screen.dart    ← 슬라이드쇼
│   │   │   ├── result_screen.dart       ← 명령 결과 표시
│   │   │   └── setup_screen.dart        ← 초기 설정 + PIN 표시
│   │   └── ...
│   └── pubspec.yaml
│
├── web/                                 ← 웹 프론트엔드 (React 또는 Flutter Web)
│   └── (TBD - Phase 2)
│
├── docs/                                ← 문서
│   ├── REQUIREMENTS.md
│   ├── DESIGN_ARCHITECTURE.md           ← 이 문서
│   ├── DESIGN_PAIRING_AND_APP.md
│   └── DESIGN_VOICE_ASSISTANT.md
│
├── scripts/                             ← 배포/설정 스크립트
│   ├── setup_termux.sh                  ← Termux 초기 설정
│   ├── start_server.sh                  ← 서버 시작
│   └── generate_cert.sh                 ← HTTPS 인증서 생성
│
└── README.md
```

---

## 7. 배포 아키텍처

### 7.1 Termux 배포 구조

```
┌─── Android 디바이스 (셋탑박스/태블릿) ─────────────────────────────┐
│                                                                    │
│  ┌─── Termux ─────────────────────────────────────────────────┐   │
│  │                                                             │   │
│  │  ┌─ Termux:Boot ──────────────────────────────────┐        │   │
│  │  │  ~/.termux/boot/start_photonest.sh              │        │   │
│  │  │  → uvicorn main:app --host 0.0.0.0 --port 8080 │        │   │
│  │  │  → python ai/worker.py &                        │        │   │
│  │  └─────────────────────────────────────────────────┘        │   │
│  │                                                             │   │
│  │  ┌─ Python 가상환경 ──────────────────────────────┐        │   │
│  │  │  ~/photonest-server/                            │        │   │
│  │  │  ├── .venv/                                     │        │   │
│  │  │  ├── main.py  (FastAPI)                         │        │   │
│  │  │  └── ...                                        │        │   │
│  │  └─────────────────────────────────────────────────┘        │   │
│  │                                                             │   │
│  │  ┌─ Termux:API ──────────────────────────────────┐         │   │
│  │  │  termux-microphone-record  (마이크 입력)        │         │   │
│  │  │  termux-tts-speak          (TTS 출력)          │         │   │
│  │  │  termux-wake-lock          (슬립 방지)          │         │   │
│  │  └─────────────────────────────────────────────────┘        │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  ┌─── 네이티브 Android ──────────────────────────────────────┐    │
│  │                                                            │    │
│  │  ┌─ PhotoNest Display App (Flutter) ──────────────────┐   │    │
│  │  │  서버 화면: 대기모드 / 대화모드 / 슬라이드쇼 / PIN  │   │    │
│  │  │  HDMI 출력 → TV 연결                                │   │    │
│  │  └─────────────────────────────────────────────────────┘   │    │
│  │                                                            │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                    │
│  ┌─── 저장소 ──────────────────────────────────────────────┐      │
│  │  SD Card: /storage/emulated/0/photonest/                │      │
│  │  (또는 ADB 권한으로 외부 SD 접근)                        │      │
│  └──────────────────────────────────────────────────────────┘      │
└────────────────────────────────────────────────────────────────────┘
```

### 7.2 서버 시작 스크립트 (Termux:Boot)

```bash
#!/data/data/com.termux/files/usr/bin/bash
# ~/.termux/boot/start_photonest.sh

# 슬립 방지
termux-wake-lock

# 서버 디렉토리 이동
cd ~/photonest-server

# 가상환경 활성화
source .venv/bin/activate

# FastAPI 서버 시작
uvicorn main:app \
  --host 0.0.0.0 \
  --port 8080 \
  --ssl-keyfile certs/server.key \
  --ssl-certfile certs/server.crt &

# AI 워커 시작 (백그라운드)
python -m ai.worker &

# mDNS 등록
python -m utils.mdns &
```

### 7.3 설치 자동화 스크립트

```bash
#!/data/data/com.termux/files/usr/bin/bash
# scripts/setup_termux.sh

echo "=== PhotoNest 서버 설치 ==="

# 1. 패키지 설치
pkg update -y
pkg install -y python python-pip ffmpeg git openssl

# 2. Termux:API 확인
if ! command -v termux-tts-speak &> /dev/null; then
    echo "Termux:API 앱을 설치해주세요"
    exit 1
fi

# 3. 저장소 권한
termux-setup-storage

# 4. Python 의존성 설치
cd ~/photonest-server
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 5. HTTPS 인증서 생성
bash scripts/generate_cert.sh

# 6. DB 초기화
python -c "from database import init_db; init_db()"

# 7. AI 모델 다운로드
python -m ai.download_models

# 8. 부팅 스크립트 설정
mkdir -p ~/.termux/boot
cp scripts/start_server.sh ~/.termux/boot/start_photonest.sh
chmod +x ~/.termux/boot/start_photonest.sh

echo "=== 설치 완료! ==="
echo "서버 시작: bash ~/.termux/boot/start_photonest.sh"
```

---

## 8. 보안 아키텍처

### 8.1 인증 흐름

```
┌──────────┐                              ┌──────────┐
│  Client  │                              │  Server  │
└────┬─────┘                              └────┬─────┘
     │                                         │
     │  1. POST /pair {pin, device_info}       │
     │────────────────────────────────────────►│
     │                                         │ PIN 검증
     │  2. {access_token, refresh_token}       │ JWT 생성
     │◄────────────────────────────────────────│
     │                                         │
     │  3. GET /photos                         │
     │  Authorization: Bearer {access_token}   │
     │────────────────────────────────────────►│
     │                                         │ JWT 검증
     │  4. {photos: [...]}                     │
     │◄────────────────────────────────────────│
     │                                         │
     │  ... access_token 만료 (24h) ...         │
     │                                         │
     │  5. POST /auth/refresh                  │
     │  {refresh_token, device_id}             │
     │────────────────────────────────────────►│
     │                                         │ refresh_token 검증
     │  6. {new_access_token}                  │ 새 access_token 발급
     │◄────────────────────────────────────────│
     │                                         │
```

### 8.2 JWT 토큰 구조

```json
Access Token (24시간):
{
  "sub": "usr_a1b2c3d4",
  "dev": "dev_f7e8d9c0",
  "fam": "fam_k1l2m3n4",
  "role": "admin",
  "exp": 1739318400
}

Refresh Token (30일):
{
  "sub": "usr_a1b2c3d4",
  "dev": "dev_f7e8d9c0",
  "type": "refresh",
  "exp": 1741824000
}
```

---

## 9. 주요 서비스 간 의존 관계

```
                         ┌─────────────┐
                         │ AuthService │
                         └──────┬──────┘
                                │ (인증 필요)
               ┌────────────────┼────────────────┐
               ▼                ▼                ▼
        ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
        │PhotoService │ │AlbumService │ │FamilyService│
        └──────┬──────┘ └──────┬──────┘ └──────┬──────┘
               │               │               │
               │         ┌─────┴─────┐         │
               ├────────►│SearchSvc  │◄────────┤
               │         └───────────┘         │
               │                               │
               ▼                               │
        ┌─────────────┐                        │
        │  AI Service │                        │
        │             │                        │
        │ FaceDetect  │                        │
        │ SceneClass  │                        │
        │ ExifExtract │                        │
        └──────┬──────┘                        │
               │                               │
               ▼                               ▼
        ┌─────────────┐                 ┌─────────────┐
        │ VoiceService│                 │MemoryService│
        │             │                 │             │
        │ NLU Parser  │────────────────►│ 추억 생성    │
        │ Cmd Executor│                 │ 푸시 알림    │
        └──────┬──────┘                 └─────────────┘
               │
               ▼
        ┌─────────────┐
        │ TV Service  │
        │             │
        │ 슬라이드쇼   │
        │ 화면 동기화  │
        └─────────────┘
```

---

## 10. 성능 최적화 전략

### 10.1 썸네일 전략

```
원본 사진 업로드 시 자동 생성:

  원본 (4032x3024, 5MB JPEG)
    ├─► small (200x200, ~15KB WebP)     ← 그리드 타임라인용
    └─► medium (800x800, ~80KB WebP)    ← 미리보기용

  WebP 포맷 사용: JPEG 대비 25-35% 용량 절감
  지연 생성 안함: 업로드 시 즉시 생성 (응답 시간 중요)
```

### 10.2 DB 쿼리 최적화

```
핵심 인덱스:
  photos(user_id, taken_at DESC)  ← 타임라인 조회
  photos(file_hash)               ← 중복 체크
  photos(taken_at DESC)           ← 전체 타임라인
  photos(location_name)           ← 장소 검색
  photo_faces(face_id)            ← 인물 검색

커서 기반 페이지네이션:
  WHERE taken_at < :cursor
  ORDER BY taken_at DESC
  LIMIT :limit

  (OFFSET 기반 대비 10만장+ 에서도 일정한 성능)
```

### 10.3 AI 백그라운드 처리

```
┌─── AI 처리 큐 ───────────────────────────────┐
│                                               │
│  업로드 → [큐 추가] → AI Worker (백그라운드)    │
│                         │                     │
│              ┌──────────┼──────────┐          │
│              ▼          ▼          ▼          │
│          EXIF 추출  얼굴 감지   역지오코딩    │
│          (즉시)     (TFLite)   (캐시 우선)    │
│                                               │
│  처리 완료 → DB 업데이트 → WebSocket 알림      │
│                                               │
│  야간 배치: 장면 분류 (리소스 많이 필요한 작업)  │
└───────────────────────────────────────────────┘

우선순위:
  1. EXIF 추출 (즉시, CPU 가벼움)
  2. 역지오코딩 (캐시 히트 시 즉시)
  3. 얼굴 감지 (TFLite, 사진당 ~3-5초)
  4. 장면 분류 (야간 배치 또는 클라우드)
```

---

## 11. 외부 서비스 의존성

| 서비스 | 용도 | 필수 여부 | 비용 |
|--------|------|----------|------|
| Firebase (FCM) | 푸시 알림 | 필수 (추억 알림) | 무료 |
| Nominatim (OpenStreetMap) | GPS → 주소 변환 | 필수 | 무료 (셀프호스팅 가능) |
| Google Vision API | 장면 인식 (고급) | 선택 | 월 1,000건 무료 |
| Google Cloud STT | 음성 인식 (폴백) | 선택 | 월 60분 무료 |
| Tailscale | 외부 접근 VPN | 선택 | 무료 (개인) |

---

*문서 버전: 1.0*
*작성일: 2026-02-10*
*프로젝트: PhotoNest*
