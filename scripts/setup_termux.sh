#!/data/data/com.termux/files/usr/bin/bash
# PhotoNest - Termux Setup Script
#
# Termux pkg(미리 빌드된 바이너리)를 우선 사용하여
# C/C++ 컴파일 오류 없이 설치합니다.
#
# Usage: bash scripts/setup_termux.sh

set -e

echo "========================================="
echo "  PhotoNest Server - Termux Setup"
echo "========================================="
echo ""

PROJECT_DIR="${PROJECT_DIR:-$HOME/mypoto}"
VENV_DIR="$HOME/photonest-venv"
DATA_DIR="$HOME/photonest"

# ─────────────────────────────────────────────
# 1. Termux 패키지 업데이트
# ─────────────────────────────────────────────
echo "[1/7] Termux 패키지 업데이트..."
pkg update -y && pkg upgrade -y

# ─────────────────────────────────────────────
# 2. 시스템 의존성 설치
# ─────────────────────────────────────────────
echo "[2/7] 시스템 의존성 설치..."
# rust: pydantic-core, watchfiles 등 Rust(maturin) 기반 패키지 빌드에 필수
pkg install -y \
    python \
    rust \
    build-essential \
    binutils \
    openssl \
    libffi \
    libjpeg-turbo \
    libpng \
    libxml2 \
    libxslt \
    curl

# ─────────────────────────────────────────────
# 3. C 확장 Python 패키지를 pkg로 설치 (컴파일 불필요)
# ─────────────────────────────────────────────
echo "[3/7] 미리 빌드된 Python 패키지 설치 (pkg)..."

# 핵심 패키지 (필수)
pkg install -y python-numpy python-pillow python-bcrypt python-cryptography

# scikit-learn (AI 클러스터링용, 없으면 건너뜀)
if ! pkg install -y python-scikit-learn 2>/dev/null; then
    echo "  [INFO] python-scikit-learn pkg 없음 — pip fallback 시도"
    _NEED_SKLEARN_PIP=1
fi

echo "  pkg Python 패키지 설치 완료"

# ─────────────────────────────────────────────
# 4. Python 가상환경 생성 (--system-site-packages)
# ─────────────────────────────────────────────
echo "[4/7] Python 가상환경 설정..."

if [ -d "$VENV_DIR" ]; then
    echo "  기존 venv 제거 후 재생성..."
    rm -rf "$VENV_DIR"
fi

# --system-site-packages: pkg로 설치한 numpy, pillow 등을 venv에서 사용
python -m venv --system-site-packages "$VENV_DIR"
source "$VENV_DIR/bin/activate"

echo "  venv 경로: $VENV_DIR"
echo "  Python: $(python --version)"

# ─────────────────────────────────────────────
# 5. 나머지 Python 패키지 pip 설치 (순수 Python 위주)
# ─────────────────────────────────────────────
echo "[5/7] pip으로 나머지 패키지 설치..."
pip install --upgrade pip setuptools wheel 2>/dev/null

# --- 웹 프레임워크 ---
# Rust가 설치되어 있으므로 pydantic-core, watchfiles 등 빌드 가능
pip install \
    "fastapi==0.115.6" \
    "uvicorn[standard]==0.34.0"

# --- 데이터베이스 ---
pip install \
    "sqlmodel==0.0.22" \
    "aiosqlite==0.20.0"

# --- 인증 ---
pip install \
    "PyJWT==2.10.1" \
    "python-jose[cryptography]==3.3.0"

# --- 설정 & 유틸리티 ---
pip install \
    "pydantic-settings==2.7.1" \
    "python-multipart==0.0.20"

# --- mDNS ---
pip install "zeroconf==0.136.2"

# --- scikit-learn pip fallback ---
if [ "${_NEED_SKLEARN_PIP:-0}" = "1" ]; then
    echo "  scikit-learn pip 설치 시도..."
    pip install "scikit-learn>=1.3.0" || echo "  [SKIP] scikit-learn 설치 실패 — AI 클러스터링 비활성화"
fi

# --- 선택적 패키지 (설치 실패해도 계속 진행) ---
echo "  선택적 패키지 설치..."

# HEIC 사진 지원
pip install "pillow-heif==0.21.0" 2>/dev/null \
    && echo "  [OK] pillow-heif (HEIC 지원)" \
    || echo "  [SKIP] pillow-heif — HEIC 사진 미지원"

# AI 얼굴 인식
pip install "onnxruntime>=1.16.0" 2>/dev/null \
    && echo "  [OK] onnxruntime (AI 얼굴 인식)" \
    || echo "  [SKIP] onnxruntime — AI 얼굴 인식 비활성화"

echo "  pip 패키지 설치 완료"

# ─────────────────────────────────────────────
# 6. 데이터 디렉토리 생성
# ─────────────────────────────────────────────
echo "[6/7] 데이터 디렉토리 생성..."
mkdir -p "$DATA_DIR/data"
mkdir -p "$DATA_DIR/originals"
mkdir -p "$DATA_DIR/thumbnails/small"
mkdir -p "$DATA_DIR/thumbnails/medium"
mkdir -p "$DATA_DIR/ai/models"

echo "  데이터 경로: $DATA_DIR"

# ─────────────────────────────────────────────
# 7. Termux:Boot 자동 시작 설정
# ─────────────────────────────────────────────
echo "[7/7] 자동 시작 스크립트 설정..."
BOOT_DIR="$HOME/.termux/boot"
mkdir -p "$BOOT_DIR"
cat > "$BOOT_DIR/photonest-server" << BOOTEOF
#!/data/data/com.termux/files/usr/bin/bash
source $VENV_DIR/bin/activate
cd $PROJECT_DIR
nohup python -m uvicorn server.main:app --host 0.0.0.0 --port 8080 > $DATA_DIR/data/server.log 2>&1 &
BOOTEOF
chmod +x "$BOOT_DIR/photonest-server"

# ─────────────────────────────────────────────
# 완료
# ─────────────────────────────────────────────
echo ""
echo "========================================="
echo "  Setup Complete!"
echo "========================================="
echo ""
echo "설치된 Python 패키지 확인:"
pip list --format=columns 2>/dev/null | grep -iE "fastapi|uvicorn|numpy|pillow|scikit|onnx|bcrypt|sqlmodel" || true
echo ""
echo "다음 단계:"
echo "  AI 모델 다운로드:  bash scripts/download_models.sh"
echo "  서버 시작:         bash scripts/start_server.sh"
echo "  서버 URL:          http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo '<기기IP>'):8080"
echo ""
