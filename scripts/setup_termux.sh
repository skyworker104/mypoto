#!/data/data/com.termux/files/usr/bin/bash
# PhotoNest - Termux One-Click Setup Script
# Usage: bash setup_termux.sh

set -e

echo "========================================="
echo "  PhotoNest Server - Termux Setup"
echo "========================================="

# 1. Update packages
echo "[1/6] Updating packages..."
pkg update -y && pkg upgrade -y

# 2. Install dependencies
echo "[2/6] Installing system dependencies..."
pkg install -y python openssl libffi libjpeg-turbo libpng

# 3. Create virtual environment
echo "[3/6] Setting up Python environment..."
VENV_DIR="$HOME/photonest-venv"
if [ ! -d "$VENV_DIR" ]; then
    python -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"

# 4. Install Python dependencies
echo "[4/6] Installing Python packages..."
pip install --upgrade pip
pip install -r "$HOME/mypoto/server/requirements.txt"

# 5. Create data directories
echo "[5/6] Creating data directories..."
mkdir -p "$HOME/photonest/data"
mkdir -p "$HOME/photonest/originals"
mkdir -p "$HOME/photonest/thumbnails/small"
mkdir -p "$HOME/photonest/thumbnails/medium"
mkdir -p "$HOME/photonest/ai"

# 6. Setup auto-start (Termux:Boot)
echo "[6/6] Setting up auto-start..."
BOOT_DIR="$HOME/.termux/boot"
mkdir -p "$BOOT_DIR"
cat > "$BOOT_DIR/photonest-server" << 'BOOTEOF'
#!/data/data/com.termux/files/usr/bin/bash
source $HOME/photonest-venv/bin/activate
cd $HOME/mypoto
nohup python -m uvicorn server.main:app --host 0.0.0.0 --port 8080 > $HOME/photonest/data/server.log 2>&1 &
BOOTEOF
chmod +x "$BOOT_DIR/photonest-server"

echo ""
echo "========================================="
echo "  Setup Complete!"
echo "========================================="
echo ""
echo "Start server:  bash scripts/start_server.sh"
echo "Server URL:    http://$(hostname -I | awk '{print $1}'):8080"
echo "API Docs:      http://$(hostname -I | awk '{print $1}'):8080/docs"
echo ""
