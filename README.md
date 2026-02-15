# PhotoNest

**가족 사진을 안전하게 백업하고, AI로 정리하고, 함께 즐기는 셀프호스팅 포토 플랫폼**

## 프로젝트 개요

PhotoNest는 클라우드 서비스 없이 가정 내 안드로이드 셋톱박스(또는 로컬 서버)에서 동작하는 **가족 사진 백업 및 관리 시스템**입니다.

- 스마트폰 사진을 Wi-Fi로 자동 백업
- AI 기반 얼굴 인식, 장소/장면 분류로 자동 정리
- 음성 명령으로 사진 검색 및 TV 슬라이드쇼
- 가족 구성원 간 사진 공유 및 추억 되돌아보기
- 웹 브라우저에서도 사진 관리 가능

## 시스템 구성

```
┌─────────────┐     REST/WS      ┌──────────────────┐     Web UI
│  Flutter App │ ◄──────────────► │  FastAPI Server   │ ◄──────────► Browser
│  (iOS/Andrd) │    Wi-Fi         │  (Python/SQLite)  │   localhost
└─────────────┘                   ├──────────────────┤
                                  │  AI Engine        │  ONNX Runtime
                                  │  Voice Assistant  │  Vosk STT + TTS
                                  │  Photo Storage    │  파일시스템
                                  └──────────────────┘
```

## 기술 스택

| 영역 | 기술 |
|------|------|
| **서버** | Python 3.12, FastAPI, SQLModel, SQLite (WAL) |
| **모바일 앱** | Flutter (Dart), Riverpod, Go Router, Dio |
| **웹 프론트엔드** | Vanilla JS (ES Modules), SPA, CSS3 |
| **AI** | ONNX Runtime (얼굴 감지/임베딩), DBSCAN 클러스터링, 장면 분류 |
| **음성** | OpenWakeWord, Vosk STT, 정규식 NLU (16개 인텐트), TTS |
| **인증** | JWT (Access 24h + Refresh 30d), PIN 기반 기기 페어링 |
| **통신** | REST API (70+ 엔드포인트) + WebSocket (동기화, 음성) |

## 주요 기능

### 사진 백업
- Wi-Fi 연결 시 자동 백업 (앨범 선택 가능)
- 중복 감지 (SHA-256 해시), 오프라인 모드 지원
- 백업 진행률 및 앨범별 통계 확인

### AI 자동 정리
- **얼굴 인식**: 가족 구성원별 자동 그룹핑
- **장면 분류**: 해변, 산, 음식, 야경 등 자동 태그
- **위치 정보**: EXIF GPS 기반 지도 뷰 + 역지오코딩

### 검색
- 자연어 날짜 검색: "작년 여름", "2024년 6월"
- 인물별, 장면별, 위치별 검색
- 음성 명령 검색: "바다 사진 보여줘"

### 추억 & 하이라이트
- "N년 전 오늘" 추억 자동 생성
- 날짜/앨범 기반 하이라이트 영상 생성 (FFmpeg)

### TV 슬라이드쇼
- 실시간 WebSocket 동기화
- 앱에서 원격 제어 (재생/일시정지/다음/이전)

### 음성 비서
- 웨이크워드 감지 → 음성 인식 → 명령 실행
- 16개 인텐트: 사진 검색, 앨범 열기, 슬라이드쇼, 날씨 등
- 멀티턴 대화 지원

### 기기 페어링
- mDNS 자동 서버 발견
- 6자리 PIN 인증 (웹 UI에 표시)
- 가족 구성원별 역할 관리 (관리자/구성원)

## 프로젝트 구조

```
mypoto/
├── server/                 # Python FastAPI 서버
│   ├── api/                #   REST API 라우터 (13개)
│   ├── services/           #   비즈니스 로직 (10개 서비스)
│   ├── models/             #   SQLModel 데이터베이스 모델
│   ├── schemas/            #   Pydantic 요청/응답 스키마
│   ├── ai/                 #   AI 엔진 (얼굴, 장면 분류)
│   ├── voice/              #   음성 비서 (NLU, STT, TTS)
│   ├── ws/                 #   WebSocket (동기화, 음성)
│   ├── web/                #   웹 프론트엔드 (HTML/CSS/JS)
│   └── utils/              #   유틸리티 (보안, EXIF, 이미지)
├── app/                    # Flutter 모바일 앱
│   └── lib/
│       ├── screens/        #   화면 (온보딩, 홈, 검색, 앨범 등)
│       ├── providers/      #   Riverpod 상태 관리
│       ├── services/       #   API 클라이언트, 백업, 연결
│       ├── models/         #   데이터 모델
│       ├── widgets/        #   공통 위젯
│       └── config/         #   라우터, 테마, 설정
├── tests/                  # 서버 테스트 (92개)
├── docs/                   # 설계 문서
└── scripts/                # 설치 및 실행 스크립트
```

## 설계 문서

| 문서 | 내용 |
|------|------|
| [요구사항 정의서](docs/REQUIREMENTS.md) | 프로젝트 비전, 대상 사용자, 기능 요구사항, 비기능 요구사항 |
| [시스템 아키텍처](docs/DESIGN_ARCHITECTURE.md) | DB 스키마, API 명세, 파일 저장 구조, 보안, 성능 최적화 |
| [페어링 & 앱 설계](docs/DESIGN_PAIRING_AND_APP.md) | mDNS 발견, PIN 인증, 모바일 앱 화면 설계, 백업 메커니즘 |
| [음성 비서 설계](docs/DESIGN_VOICE_ASSISTANT.md) | 음성 파이프라인, NLU 인텐트, 대화 관리, 처리 흐름 |
| [구현 워크플로우](docs/WORKFLOW_IMPLEMENTATION.md) | 스프린트별 구현 계획 (MVP 8 + Phase 2 14 + Phase 3 4) |

## 빠른 시작

### 서버 실행 (PC / Mac / Linux)

```bash
# 의존성 설치
pip install -r server/requirements.txt

# 서버 시작 (기본 포트 8080)
python -m server.main
```

서버 실행 후 `http://localhost:8080` 에서 웹 UI에 접근할 수 있습니다.

### 모바일 앱 빌드

```bash
cd app

# 의존성 설치
flutter pub get

# iOS 시뮬레이터
flutter run -d ios

# Android 에뮬레이터
flutter run -d emulator-5554
```

### 테스트

```bash
# 서버 테스트 (92개)
PYTHONPATH=. python3 tests/test_phase2.py   # 48 tests
PYTHONPATH=. python3 tests/test_phase3.py   # 44 tests
```

---

## Android Termux 서버 배포

안드로이드 셋톱박스 또는 안드로이드 기기에서 Termux를 이용해 PhotoNest 서버를 운영할 수 있습니다.

### 사전 준비

1. **Termux** 설치 — [F-Droid](https://f-droid.org/packages/com.termux/)에서 다운로드 (Play Store 버전은 업데이트 중단됨)
2. (선택) **Termux:Boot** 설치 — 기기 부팅 시 서버 자동 시작용

### 1단계: 소스 코드 받기

```bash
pkg install -y git
git clone https://github.com/skyworker104/mypoto.git ~/mypoto
cd ~/mypoto
```

### 2단계: 원클릭 설치

설치 스크립트가 **Termux pkg(미리 빌드된 바이너리)를 우선 사용**하여 C/C++ 컴파일 오류 없이 설치합니다.

```bash
bash scripts/setup_termux.sh
```

스크립트가 수행하는 작업:
| 단계 | 내용 |
|------|------|
| 1 | Termux 패키지 업데이트 (`pkg update`) |
| 2 | 시스템 의존성 설치 (`python`, `build-essential`, `openssl`, `libffi`, `libjpeg-turbo` 등) |
| 3 | **pkg로 C 확장 Python 패키지 설치** (`python-numpy`, `python-pillow`, `python-bcrypt`, `python-cryptography`, `python-scikit-learn`) |
| 4 | Python 가상환경 생성 (`--system-site-packages`로 pkg 패키지 연동) |
| 5 | pip으로 나머지 순수 Python 패키지 설치 (FastAPI, uvicorn, SQLModel 등) |
| 6 | 데이터 디렉토리 생성 (`~/photonest/data`, `originals`, `thumbnails`, `ai`) |
| 7 | Termux:Boot 자동 시작 스크립트 설정 |

> `pillow-heif`(HEIC 지원)와 `onnxruntime`(AI 얼굴 인식)은 선택적이며, 설치 실패 시 자동으로 건너뜁니다.

### 3단계: AI 모델 다운로드 (선택)

얼굴 인식 기능을 사용하려면 ONNX 모델을 다운로드합니다.

```bash
bash scripts/download_models.sh
```

- **UltraFace-slim** (~300KB) — 얼굴 감지
- **MobileFaceNet** (~4MB) — 얼굴 임베딩 (512차원)

모델은 `~/photonest/ai/models/`에 저장됩니다.

### 서버 시작

```bash
# 포그라운드 실행 (로그 실시간 확인)
bash scripts/start_server.sh

# 또는 백그라운드 실행
source ~/photonest-venv/bin/activate
cd ~/mypoto
nohup python3 -m uvicorn server.main:app --host 0.0.0.0 --port 8080 > ~/photonest/data/server.log 2>&1 &
```

서버가 시작되면:
- **웹 UI**: `http://<기기IP>:8080`
- **API 문서**: `http://<기기IP>:8080/docs`
- 같은 Wi-Fi 네트워크의 모바일 앱에서 자동 발견됩니다

### 서버 종료

```bash
# 실행 중인 서버 프로세스 확인
ps aux | grep uvicorn

# 서버 종료
pkill -f "uvicorn server.main:app"
```

### 로그 확인

```bash
# 백그라운드 실행 시 로그 확인
cat ~/photonest/data/server.log

# 실시간 로그 모니터링
tail -f ~/photonest/data/server.log
```

### 서버 상태 확인

```bash
curl http://localhost:8080/api/v1/system/status
```

### 부팅 시 자동 시작

`setup_termux.sh`를 실행하면 Termux:Boot 자동 시작이 자동으로 설정됩니다.
수동으로 설정하려면:

```bash
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/photonest-server << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
source $HOME/photonest-venv/bin/activate
cd $HOME/mypoto
nohup python -m uvicorn server.main:app --host 0.0.0.0 --port 8080 > $HOME/photonest/data/server.log 2>&1 &
EOF
chmod +x ~/.termux/boot/photonest-server
```

> Termux:Boot 앱이 설치되어 있어야 하며, 최초 1회 Termux:Boot 앱을 실행해야 활성화됩니다.

### 데이터 디렉토리 구조

```
~/photonest/
├── data/              # SQLite DB, 서버 로그
├── originals/         # 원본 사진 저장
├── thumbnails/
│   ├── small/         # 작은 썸네일 (200px)
│   └── medium/        # 중간 썸네일 (800px)
└── ai/
    └── models/        # ONNX AI 모델 파일
```

## 앱 화면 구성

| 탭 | 기능 |
|----|------|
| **사진** | 타임라인 그리드, 카메라 촬영, 오프라인 모드 |
| **검색** | 인물, 장면, 날짜 검색 |
| **앨범** | 서버 앨범 관리 |
| **TV** | 슬라이드쇼 + 음성 채팅 |
| **설정** | 백업 앨범 선택, 서버 정보, 통계 |

## 개발 현황

- **MVP (Sprint 1-8)**: 핵심 서버, DB, 인증, 사진 업로드/조회, 웹 UI
- **Phase 2 (Sprint 9-14)**: AI (얼굴, 장면), 검색, 추억, 지도, 하이라이트
- **Phase 3 (Sprint 15-18)**: 음성 비서, NLU, 대화 관리, STT/TTS
- **앱 강화**: 오프라인 모드, 동기화 상태 추적, 카메라, WiFi 자동 백업

## 라이선스

이 프로젝트는 개인 사용 목적으로 개발되었습니다.
