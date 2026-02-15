#!/bin/bash
# Download AI models for PhotoNest face detection & embedding.
#
# Models:
#   - UltraFace-slim: ~300KB face detection
#   - MobileFaceNet: ~4MB face embedding (512-dim)
#
# Usage: bash scripts/download_models.sh

set -e

MODEL_DIR="${PHOTONEST_AI_DIR:-$HOME/photonest/ai}/models"
mkdir -p "$MODEL_DIR"

echo "=== PhotoNest AI Model Downloader ==="
echo "Target: $MODEL_DIR"

# UltraFace-slim-320 (face detection)
DETECT_URL="https://github.com/Linzaer/Ultra-Light-Fast-Generic-Face-Detector-1MB/raw/master/models/onnx/version-slim-320.onnx"
DETECT_FILE="$MODEL_DIR/face_detection.onnx"
if [ ! -f "$DETECT_FILE" ]; then
    echo "Downloading face detection model (UltraFace-slim)..."
    curl -L -o "$DETECT_FILE" "$DETECT_URL"
    echo "  -> Saved: $DETECT_FILE"
else
    echo "Face detection model already exists, skipping."
fi

# MobileFaceNet (face embedding)
EMBED_URL="https://github.com/nicehuster/mobilefacenet-onnx/raw/main/mobilefacenet.onnx"
EMBED_FILE="$MODEL_DIR/face_embedding.onnx"
if [ ! -f "$EMBED_FILE" ]; then
    echo "Downloading face embedding model (MobileFaceNet)..."
    curl -L -o "$EMBED_FILE" "$EMBED_URL"
    echo "  -> Saved: $EMBED_FILE"
else
    echo "Face embedding model already exists, skipping."
fi

echo ""
echo "=== Done ==="
ls -lh "$MODEL_DIR"
