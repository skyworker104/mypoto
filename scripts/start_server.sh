#!/bin/bash
# PhotoNest Server Start Script
# Works on both Termux and standard Linux/macOS

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Activate venv if exists
if [ -d "$HOME/photonest-venv" ]; then
    source "$HOME/photonest-venv/bin/activate"
fi

cd "$PROJECT_DIR"

echo "Starting PhotoNest Server..."
echo "  Project: $PROJECT_DIR"
echo "  Port:    8080"
echo ""

python3 -m uvicorn server.main:app \
    --host 0.0.0.0 \
    --port 8080 \
    --log-level info
