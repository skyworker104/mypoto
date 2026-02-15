# PhotoNest - 구현 워크플로우

> 설계 문서를 기반으로 한 단계별 구현 계획
> MVP → Phase 2 → Phase 3 순차 구현

---

## 전체 구현 로드맵

```
        Sprint 1-2          Sprint 3-4          Sprint 5-6          Sprint 7-8
       (서버 기반)          (앱 기반)           (연동 완성)         (품질 완성)
    ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
    │              │   │              │   │              │   │              │
MVP │ 서버 코어    │──►│ 모바일 앱    │──►│ TV + 음성    │──►│ 테스트 +     │
    │ + DB + API   │   │ 백업 + 조회  │   │ + 가족공유   │   │ 배포 자동화  │
    │              │   │              │   │              │   │              │
    └──────────────┘   └──────────────┘   └──────────────┘   └──────────────┘
                                                                     │
    ┌──────────────┐   ┌──────────────┐   ┌──────────────┐          │
    │              │   │              │   │              │          │
P2  │ AI 얼굴인식  │──►│ 검색 + 추억  │──►│ 음성 다이렉트 │◄─────────┘
    │              │   │   알림       │   │   모드       │
    │              │   │              │   │              │
    └──────────────┘   └──────────────┘   └──────────────┘

    ┌──────────────┐   ┌──────────────┐
    │              │   │              │
P3  │ 장면 분류    │──►│ 지도 뷰 +    │
    │ (클라우드)   │   │ 하이라이트   │
    │              │   │              │
    └──────────────┘   └──────────────┘
```

---

## MVP 구현 계획 (Sprint 1~8)

---

### Sprint 1: 서버 프로젝트 기반 구축

**목표**: FastAPI 서버 뼈대 + DB + 인증 시스템

#### 태스크

```
S1-1  프로젝트 초기화
├── Python 프로젝트 구조 생성 (server/)
├── pyproject.toml / requirements.txt 설정
├── FastAPI 앱 엔트리포인트 (main.py)
├── 설정 관리 (config.py - Pydantic Settings)
└── .gitignore, README.md

S1-2  데이터베이스 구축
├── SQLite 연결 관리 (database.py)
├── SQLModel 모델 정의 (models/*.py)
│   ├── Family, User, Device
│   ├── Photo, Album, PhotoAlbum
│   └── Face, PhotoFace, Comment, Invite
├── DB 초기화 + 마이그레이션 스크립트
└── WAL 모드 활성화

S1-3  인증 시스템
├── JWT 토큰 생성/검증 (utils/security.py)
├── 비밀번호 해싱 (bcrypt)
├── 인증 미들웨어 (의존성 주입)
├── API: POST /pair/init (PIN 생성)
├── API: POST /pair (PIN 검증 + 토큰 발급)
├── API: POST /auth/refresh (토큰 갱신)
└── API: POST /auth/logout

S1-4  사용자 & 가족 API
├── API: POST /users/setup (초기 계정 생성)
├── API: GET /users/me
├── API: PATCH /users/me
├── API: GET /family
├── API: POST /family/invite
├── API: POST /family/join
└── API: DELETE /family/members/{id}

S1-5  기기 관리 API
├── API: GET /devices
├── API: PATCH /devices/{id}
└── API: DELETE /devices/{id}
```

#### 완료 기준
- [x] `uvicorn main:app` 으로 서버 시작 가능
- [x] POST /pair → PIN 검증 → JWT 토큰 발급 작동
- [x] 인증된 상태로 /users/me, /family API 호출 가능
- [x] SQLite DB에 테이블 생성 확인

#### 의존성: 없음 (첫 스프린트)

---

### Sprint 2: 사진 업로드 & 저장 시스템

**목표**: 사진 업로드 → 저장 → 썸네일 생성 → 조회 API 완성

#### 태스크

```
S2-1  파일 저장소 관리
├── 저장 경로 구조 생성 (originals/YYYY/MM/DD/)
├── 썸네일 디렉토리 (thumbnails/small/, medium/)
├── 파일 저장 서비스 (services/storage_service.py)
└── 저장 공간 모니터링 (utils/storage.py)

S2-2  이미지 처리
├── 썸네일 생성 (utils/image.py)
│   ├── small: 200x200 WebP
│   └── medium: 800x800 WebP
├── HEIC → JPEG 변환 (pillow-heif)
├── EXIF 메타데이터 추출 (ai/exif_extractor.py)
│   ├── 촬영일시, GPS, 카메라 정보
│   └── JSON 변환 + DB 저장
└── 파일 해시 계산 (SHA-256)

S2-3  사진 API (핵심)
├── API: POST /photos/check (중복 체크)
├── API: POST /photos/upload (멀티파트 업로드)
│   ├── 파일 수신 → 해시 검증
│   ├── 원본 저장 → 썸네일 생성
│   ├── EXIF 추출 → DB INSERT
│   └── 응답 반환
├── API: GET /photos (타임라인 - 커서 페이지네이션)
├── API: GET /photos/{id} (상세 정보)
├── API: GET /photos/{id}/file (원본 다운로드)
├── API: GET /photos/{id}/thumb (썸네일 다운로드)
├── API: PATCH /photos/{id} (즐겨찾기 등)
├── API: DELETE /photos/{id} (soft delete)
└── API: POST /photos/batch (다중 작업)

S2-4  시스템 상태 API
├── API: GET /system/status (저장공간, 사진 수)
├── API: GET /system/storage (상세 저장소 정보)
└── API: GET /sync/status (동기화 상태)
```

#### 완료 기준
- [x] 사진 파일을 업로드하면 원본 + 썸네일이 생성됨
- [x] 동일 해시 사진은 중복 방지됨
- [x] GET /photos 로 날짜순 타임라인 조회 가능
- [x] HEIC 파일 업로드 시 자동 변환
- [x] EXIF 데이터 (날짜, GPS, 카메라) 추출됨

#### 의존성: Sprint 1 완료

---

### Sprint 3: Flutter 모바일 앱 기반

**목표**: Flutter 프로젝트 + 서버 연결 + 페어링 + 사진 조회

#### 태스크

```
S3-1  Flutter 프로젝트 초기화
├── Flutter 프로젝트 생성 (app/)
├── 폴더 구조 설정 (config, models, services, providers, screens, widgets)
├── pubspec.yaml 의존성 설정
│   ├── riverpod (상태관리)
│   ├── dio (HTTP)
│   ├── web_socket_channel (WebSocket)
│   ├── photo_manager (갤러리 접근)
│   ├── flutter_secure_storage (토큰 저장)
│   ├── connectivity_plus (네트워크 감지)
│   └── nsd_android / bonsoir (mDNS)
├── 테마 설정 (Material 3, 다크모드)
└── 라우팅 설정 (go_router)

S3-2  API 클라이언트
├── HTTP 클라이언트 (services/api_client.dart)
│   ├── Base URL 설정
│   ├── JWT 토큰 자동 첨부 (interceptor)
│   ├── 토큰 만료 시 자동 갱신
│   └── 에러 핸들링
└── WebSocket 클라이언트 (services/ws_client.dart)

S3-3  온보딩 + 페어링 화면
├── 온보딩 화면 (3페이지 소개)
├── 서버 탐색 화면 (mDNS 스캔)
│   ├── 서버 발견 → 목록 표시
│   └── 수동 IP 입력 폴백
├── PIN 입력 화면 (6자리)
├── 계정 설정 화면 (닉네임 + 비밀번호)
└── 페어링 완료 → 메인 화면 이동

S3-4  메인 화면 - 사진 탭 (타임라인)
├── 하단 탭 바 (사진/검색/앨범/가족/TV)
├── 사진 그리드 위젯 (photo_grid.dart)
│   ├── 날짜별 그룹 헤더
│   ├── 썸네일 지연 로딩
│   ├── 무한 스크롤 (커서 페이지네이션)
│   └── 핀치 줌 (3열 ↔ 5열 ↔ 7열)
├── 빠른 날짜 스크롤바 (우측)
└── 사진 선택 모드 (길게 누르기)

S3-5  사진 뷰어 화면
├── 전체화면 사진 표시
├── 스와이프 탐색 (이전/다음)
├── 핀치 줌 + 더블탭 줌
├── 하단 메타정보 (날짜, 위치, 카메라)
├── 액션 바 (좋아요, 댓글, 앨범추가, 삭제)
└── 동영상 재생 (video_player)
```

#### 완료 기준
- [x] 앱에서 mDNS로 서버 자동 발견
- [x] PIN 입력으로 페어링 성공
- [x] 서버의 사진을 타임라인 그리드로 표시
- [x] 사진 탭 → 전체화면 뷰어 전환 작동
- [x] 무한 스크롤 + 썸네일 로딩 부드러움

#### 의존성: Sprint 1, 2 완료

---

### Sprint 4: 자동 백업 시스템

**목표**: Wi-Fi 감지 → 새 사진 탐지 → 자동 업로드

#### 태스크

```
S4-1  사진 라이브러리 접근
├── photo_manager 초기화 + 권한 요청
├── 기기 전체 사진/동영상 스캔
├── 새 사진 감지 (마지막 동기화 이후)
└── 사진 메타데이터 읽기 (날짜, 위치, 해시)

S4-2  백업 엔진
├── 백업 서비스 (services/backup_service.dart)
│   ├── Wi-Fi 연결 감지 (connectivity_plus)
│   ├── 중복 체크 (POST /photos/check)
│   ├── 순차 업로드 (POST /photos/upload)
│   ├── 재시도 로직 (최대 3회)
│   └── 업로드 이어받기 (중단 복구)
├── 백업 상태 관리 (provider)
│   ├── 대기 / 백업중 / 완료 / 일시정지
│   ├── 진행률 (N/M, 속도)
│   └── 에러 목록
└── 백업 설정 저장 (SharedPreferences)
    ├── Wi-Fi만 / 충전 중만
    └── 선택 폴더

S4-3  백그라운드 백업
├── workmanager 설정 (Android)
│   ├── Wi-Fi + 충전 제약 조건
│   └── 주기적 백업 체크 (15분 간격)
├── iOS Background Fetch 설정
│   └── 30초 윈도우 내 최대 업로드
└── 백업 알림 표시 (진행 중 / 완료)

S4-4  WebSocket 실시간 동기화
├── 서버: ws/sync.py (백업 진행률 브로드캐스트)
├── 앱: 진행률 실시간 수신 + UI 업데이트
└── 하단 떠있는 백업 상태 바
```

#### 완료 기준
- [x] 홈 Wi-Fi 연결 시 새 사진 자동 감지
- [x] 중복 건너뛰기 후 새 사진만 업로드
- [x] 실시간 진행률 표시
- [x] 앱 백그라운드에서도 업로드 계속 (Android)
- [x] 업로드 중 네트워크 끊김 → 재연결 시 이어받기

#### 의존성: Sprint 2, 3 완료

---

### Sprint 5: 앨범 + 가족 공유

**목표**: 앨범 CRUD + 가족 초대 + 공유 앨범

#### 태스크

```
S5-1  서버: 앨범 API 구현
├── API: GET /albums
├── API: POST /albums (생성)
├── API: GET /albums/{id} (상세)
├── API: PATCH /albums/{id} (수정)
├── API: DELETE /albums/{id}
├── API: POST /albums/{id}/photos (사진 추가)
├── API: DELETE /albums/{id}/photos (사진 제거)
└── API: POST /albums/{id}/share (공유 설정)

S5-2  앱: 앨범 탭 화면
├── 앨범 목록 (공유/개인/자동 구분)
├── 앨범 생성 화면 (이름 + 사진 선택 + 공유 여부)
├── 앨범 상세 (사진 그리드 + 멤버 표시)
├── 앨범에 사진 추가 (선택 모드 → "앨범에 추가")
└── 앨범 커버 사진 설정

S5-3  서버: 가족 초대 시스템
├── 초대 코드 생성 (8자리)
├── 초대 토큰 + QR 데이터 생성
├── 초대 링크 생성 (딥링크)
├── 초대 코드 사용 → 계정 생성 + 가족 합류
└── 초대 만료 / 1회 사용 제한

S5-4  앱: 가족 탭 화면
├── 가족 구성원 목록 + 온라인 상태
├── 초대하기 (PIN / QR / 링크)
├── 가족 활동 피드 (최근 백업, 앨범 추가)
├── 저장 공간 현황
└── 관리자: 구성원 관리 (제거)

S5-5  서버: WebSocket 활동 피드
├── ws/activity.py (가족 활동 브로드캐스트)
├── 이벤트: 사진 업로드, 앨범 생성, 초대 수락
└── 앱: 실시간 활동 피드 수신
```

#### 완료 기준
- [x] 앨범 생성 → 사진 추가 → 조회 작동
- [x] 공유 앨범에 가족 구성원 모두 접근 가능
- [x] QR/PIN/링크로 가족 초대 + 새 구성원 페어링 성공
- [x] 가족 활동 피드 실시간 표시

#### 의존성: Sprint 3, 4 완료

---

### Sprint 6: TV 슬라이드쇼 + 서버 디스플레이

**목표**: 서버 디스플레이 앱 + TV 슬라이드쇼 + 폰 리모컨

#### 태스크

```
S6-1  서버 디스플레이 앱 (Flutter)
├── Flutter 프로젝트 생성 (display/)
├── 대기 화면 (시계 + 추억사진 + 가족현황 + 저장소)
├── PIN 표시 화면 (페어링 시)
├── 초기 설정 화면 (최초 실행)
├── WebSocket으로 서버와 실시간 연결
│   └── ws/display.py → display 앱 연동
└── 화면 모드 전환 (대기 → 대화 → 슬라이드쇼 → 결과)

S6-2  서버: TV 슬라이드쇼 API
├── API: POST /tv/slideshow/start
├── API: POST /tv/slideshow/stop
├── API: POST /tv/slideshow/control (다음/이전/일시정지)
├── API: GET /tv/slideshow/status
├── 슬라이드쇼 세션 관리 (services/tv_service.py)
│   ├── 사진 큐 생성 (필터 적용)
│   ├── 순서 (랜덤/날짜순)
│   └── 간격 타이머
└── WebSocket: ws/tv.py (실시간 동기화)

S6-3  디스플레이 앱: 슬라이드쇼 화면
├── 전체화면 사진 표시
├── 전환 효과 (페이드)
├── 자동 진행 (타이머)
├── 사진 정보 오버레이 (날짜, 위치)
└── 서버에서 WebSocket으로 제어 수신

S6-4  앱: TV 탭 (리모컨)
├── 서버 연결 상태 표시
├── 슬라이드쇼 설정 (앨범/기간/인물/간격/순서)
├── 시작 버튼
├── 리모컨 UI (이전/일시정지/다음/좋아요/종료)
└── 현재 표시 사진 정보
```

#### 완료 기준
- [x] 디스플레이 앱이 서버 화면에서 실행됨
- [x] 폰 앱에서 슬라이드쇼 시작 → TV에 사진 표시
- [x] 리모컨으로 다음/이전/정지 제어 작동
- [x] 대기 모드에서 추억 사진 + 시계 표시

#### 의존성: Sprint 2, 5 완료

---

### Sprint 7: 음성 명령 (리모트 모드)

**목표**: 폰 앱에서 음성으로 서버에 명령 → 결과 표시

#### 태스크

```
S7-1  서버: 음성 명령 처리 엔진
├── NLU 파서 (voice/nlu_parser.py)
│   ├── 인텐트 분류 (Regex 패턴 매칭)
│   │   ├── SHOW_PHOTOS, PLAY_SLIDESHOW
│   │   ├── CONTROL_SLIDESHOW, SEARCH_PERSON
│   │   ├── SEARCH_PLACE, SEARCH_DATE
│   │   ├── SHOW_ALBUM, SHOW_MEMORIES
│   │   ├── SYSTEM_STATUS, STOP, HELP
│   │   └── 한국어 패턴 정의
│   └── 슬롯 추출 (person, place, date_range, album)
├── 명령 실행기 (voice/command_executor.py)
│   ├── 인텐트별 실행 핸들러
│   ├── DB 쿼리 변환 + 실행
│   └── 응답 텍스트 생성
├── API: GET/PATCH /voice/settings
└── API: GET /voice/history

S7-2  서버: 음성 WebSocket
├── ws/voice.py
│   ├── 인증 처리
│   ├── text_command 수신 → NLU → 실행 → 결과 반환
│   ├── command_result 전송 (결과 + 응답텍스트)
│   └── display_sync 전송 (서버 화면 동기화)
└── 대화 세션 관리 (세션 ID, 30초 타임아웃)

S7-3  앱: 음성 명령 UI
├── 플로팅 음성 버튼 (하단 탭 위)
├── 음성 명령 화면
│   ├── Push-to-Talk (길게 누르기)
│   ├── speech_to_text 패키지 통합
│   ├── 인식 텍스트 → WebSocket으로 서버 전송
│   ├── 대화 내역 (채팅 형태)
│   ├── 결과 인라인 표시 (사진 썸네일)
│   └── 텍스트 입력 폴백
└── TTS 재생 (flutter_tts)

S7-4  디스플레이 앱: 대화 모드
├── 대화 모드 화면 (상단 대화내역 + 하단 결과)
├── 어떤 기기에서 명령했는지 표시
├── WebSocket에서 display_sync 수신
├── 결과에 따라 화면 전환
│   ├── photo_grid → 사진 그리드 표시
│   ├── slideshow → 슬라이드쇼 시작
│   └── system_info → 시스템 정보 표시
└── 후속 명령 가이드 표시
```

#### 완료 기준
- [x] 폰 앱에서 "엄마 사진 보여줘" → 서버에서 사진 검색 → 결과 표시
- [x] "슬라이드쇼 틀어줘" → TV에서 슬라이드쇼 시작
- [x] 서버 디스플레이에 대화 내역 + 결과 실시간 표시
- [x] 10가지 기본 인텐트 작동

#### 의존성: Sprint 5, 6 완료

---

### Sprint 8: 통합 테스트 + 배포

**목표**: 전체 기능 통합 테스트 + Termux 배포 자동화

#### 태스크

```
S8-1  서버 테스트
├── 단위 테스트 (pytest)
│   ├── 서비스 레이어 테스트
│   ├── API 엔드포인트 테스트 (httpx)
│   └── WebSocket 테스트
├── 통합 테스트
│   ├── 업로드 → 썸네일 → DB 저장 E2E
│   ├── 페어링 → 인증 → API 호출 E2E
│   └── 음성명령 → 실행 → 결과 E2E
└── 성능 테스트
    ├── 1,000장 일괄 업로드
    ├── 10,000장 타임라인 스크롤
    └── 동시 2기기 접속

S8-2  앱 테스트
├── 위젯 테스트 (핵심 화면)
├── 통합 테스트 (서버 연동)
└── 실기기 테스트 (iOS + Android)

S8-3  Termux 배포 자동화
├── scripts/setup_termux.sh (원클릭 설치)
│   ├── 패키지 설치 (python, ffmpeg, openssl)
│   ├── Python 가상환경 + pip install
│   ├── HTTPS 인증서 생성
│   ├── DB 초기화
│   └── 부팅 스크립트 설정
├── scripts/start_server.sh (서버 시작)
├── scripts/generate_cert.sh (인증서)
├── Termux:Boot 자동 시작 설정
└── 서버 상태 모니터링 스크립트

S8-4  문서화
├── README.md (설치 가이드)
├── 사용자 가이드 (기본 사용법)
└── 문제 해결 FAQ
```

#### 완료 기준
- [x] 모든 MVP 기능이 E2E로 작동
- [x] Termux에서 setup 스크립트 실행 → 서버 자동 시작
- [x] 실기기 (Android/iOS)에서 앱 테스트 통과
- [x] 2명 이상 가족 구성원 동시 사용 가능

#### 의존성: Sprint 1~7 전체

---

## Phase 2 구현 계획 (Sprint 9~14)

### Sprint 9-10: AI 얼굴 인식

```
S9  AI 파이프라인 구축
├── AI 워커 (ai/worker.py) - 백그라운드 큐 처리
├── 얼굴 감지 (TFLite + MobileFaceNet)
├── 얼굴 임베딩 생성 (512차원 벡터)
├── 얼굴 클러스터링 (DBSCAN/Chinese Whispers)
├── DB 저장 (faces, photo_faces 테이블)
└── 기존 사진 일괄 처리 (마이그레이션)

S10 얼굴 API + 앱 UI
├── API: GET /faces (인물 목록)
├── API: PATCH /faces/{id} (이름 태깅)
├── API: POST /faces/merge (클러스터 병합)
├── 앱: 검색 탭 - 인물 섹션
├── 앱: 인물별 사진 목록
└── 앱: 인물 이름 태깅 UI
```

### Sprint 11-12: 검색 + 추억 알림

```
S11 검색 시스템
├── GPS → 주소 역지오코딩 (Nominatim + 캐시)
├── API: GET /search (통합 검색)
├── API: GET /search/places (장소 목록)
├── 앱: 검색 탭 완성 (인물/장소/카테고리)
└── 앱: 검색 결과 화면

S12 추억 알림
├── 추억 생성 서비스 (services/memory_service.py)
│   ├── "N년 전 오늘" 사진 탐색
│   ├── 주간/월간 베스트 선정
│   └── 스케줄러 (매일 아침 실행)
├── FCM 푸시 알림 연동
│   ├── Firebase 프로젝트 설정
│   ├── 서버 → FCM → 앱 푸시
│   └── 앱: 알림 탭 + 푸시 수신
├── API: GET /memories
├── API: GET/PATCH /memories/settings
└── 앱: 사진 탭 상단 추억 카드 (가로 스크롤)
```

### Sprint 13-14: 음성 다이렉트 모드

```
S13 Wake Word + STT
├── OpenWakeWord 설치 + 기본 모델 설정
├── Vosk STT 설치 (한국어 모델)
├── 마이크 입력 → Wake Word 감지 → STT 변환 파이프라인
├── voice/wake_word.py
├── voice/stt_engine.py
└── 디스플레이 앱: 음성 파형 애니메이션

S14 TTS + 멀티턴 대화
├── Android TTS 연동 (termux-tts-speak)
├── voice/tts_engine.py
├── 대화 세션 컨텍스트 관리
│   ├── 이전 명령 기억
│   ├── 필터 누적
│   └── 30초 타임아웃
└── NLU 고도화 (더 많은 패턴 + 자연어 변형)
```

---

## Phase 3 구현 계획 (Sprint 15~18)

### Sprint 15-16: AI 장면 분류

```
S15 장면 분류 (클라우드)
├── Google Vision API 연동
├── 장면/물체 태깅 → DB 저장 (ai_tags, ai_scene)
├── 야간 배치 처리 (스케줄러)
├── API: GET /search/tags (카테고리 목록)
└── 앱: 검색 탭 - 카테고리 섹션

S16 로컬 분류 대안
├── CLIP 경량 모델 테스트 (RK3588 NPU)
├── 클라우드 ↔ 로컬 자동 전환
└── 분류 결과 캐싱
```

### Sprint 17-18: 지도 뷰 + 하이라이트

```
S17 지도 뷰
├── 앱: 지도 화면 (OpenStreetMap / Google Maps)
├── GPS 클러스터링 (가까운 사진 그룹)
├── 지도 마커 탭 → 해당 위치 사진 보기
└── API: GET /photos/locations (위치별 그룹)

S18 하이라이트 영상
├── FFmpeg로 사진 → 슬라이드쇼 영상 생성
├── 배경음악 합성
├── 자동 생성 (이벤트/기간별)
├── API: POST /highlights/generate
└── 앱: 하이라이트 재생
```

---

## 의존성 그래프

```
Sprint 1 (서버 기반)
    │
    ├── Sprint 2 (사진 업로드)
    │       │
    │       ├── Sprint 3 (앱 기반 + 조회) ──► Sprint 4 (자동 백업)
    │       │       │                              │
    │       │       └─────────┬────────────────────┘
    │       │                 │
    │       │           Sprint 5 (앨범 + 가족)
    │       │                 │
    │       ├─────────────────┤
    │       │                 │
    │       │           Sprint 6 (TV 슬라이드쇼)
    │       │                 │
    │       │           Sprint 7 (음성 리모트)
    │       │                 │
    │       └── Sprint 8 (통합 테스트 + 배포)
    │                         │
    │                   ── MVP 완료 ──
    │                         │
    ├── Sprint 9-10 (AI 얼굴 인식)
    │       │
    ├── Sprint 11-12 (검색 + 추억)
    │       │
    └── Sprint 13-14 (음성 다이렉트)
                │
          ── Phase 2 완료 ──
                │
        Sprint 15-16 (장면 분류)
                │
        Sprint 17-18 (지도 + 하이라이트)
                │
          ── Phase 3 완료 ──
```

---

## 검증 체크포인트

### CP1: Sprint 2 완료 후 - 서버 단독 검증
```
□ 사진 업로드 API가 정상 작동하는가?
□ 썸네일이 올바르게 생성되는가?
□ 중복 방지가 작동하는가?
□ 타임라인 조회가 날짜순으로 정렬되는가?
→ 방법: curl 또는 Postman으로 API 직접 테스트
```

### CP2: Sprint 4 완료 후 - 백업 E2E 검증
```
□ 폰에서 서버로 사진 자동 백업이 되는가?
□ 백업 진행률이 실시간 표시되는가?
□ Wi-Fi 끊김 후 재연결 시 이어받기가 되는가?
□ 이미 백업된 사진은 건너뛰는가?
→ 방법: 실기기로 50장 이상 백업 테스트
```

### CP3: Sprint 6 완료 후 - TV 연동 검증
```
□ 디스플레이 앱이 TV에 정상 표시되는가?
□ 폰에서 슬라이드쇼 시작 → TV에 사진이 나오는가?
□ 리모컨으로 이전/다음 제어가 되는가?
→ 방법: 셋탑박스/태블릿 + HDMI TV 연결 테스트
```

### CP4: Sprint 8 완료 - MVP 전체 검증
```
□ 새 기기에서 setup 스크립트로 설치 가능한가?
□ 2명 이상 가족이 동시에 사용 가능한가?
□ 공유 앨범이 양쪽에서 보이는가?
□ 음성 명령으로 사진 검색이 되는가?
→ 방법: 클린 셋탑박스에서 처음부터 설치 → 가족 2명 테스트
```

---

## 기술 스택 요약 (Sprint별 도입)

| Sprint | 새로 도입되는 기술 |
|--------|-------------------|
| S1 | FastAPI, SQLModel, PyJWT, bcrypt, SQLite |
| S2 | Pillow, pillow-heif, FFmpeg (썸네일), hashlib |
| S3 | Flutter, Riverpod, Dio, go_router, bonsoir (mDNS) |
| S4 | photo_manager, workmanager, connectivity_plus |
| S5 | qr_flutter, share_plus |
| S6 | Flutter (display app), WebSocket 양방향 |
| S7 | speech_to_text, flutter_tts, Regex NLU |
| S8 | pytest, httpx (테스트), Termux:Boot |
| S9 | TFLite, MobileFaceNet, numpy, scikit-learn (클러스터링) |
| S11 | Nominatim (지오코딩), Firebase Admin SDK (FCM) |
| S13 | OpenWakeWord, Vosk, termux-api (마이크/TTS) |
| S15 | Google Vision API |
| S17 | flutter_map (OpenStreetMap) |
| S18 | FFmpeg (영상 생성) |

---

*문서 버전: 1.0*
*작성일: 2026-02-10*
*프로젝트: PhotoNest*
