#!/usr/bin/env bash
# Fetch the dev CoreML model used by DetectionScreen as a fallback when no
# Octomil-paired model is available.
#
# Production builds DO NOT bundle a model — DetectionScreen loads from
# `model.compiledModelURL` populated by the Octomil SDK's pairing flow.
# This script is for local development only.
#
# Model: Apple's pre-trained YOLOv3Tiny (35 MB, MIT-comparable Apple sample
# license, hosted at Apple's ml-assets CDN). 80-class COCO object detection.
#
# Usage:
#   bash scripts/fetch_dev_model.sh
#
# After running, regenerate the xcodeproj so the model is picked up:
#   xcodegen generate

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES_DIR="${SCRIPT_DIR}/../OctomilApp/Resources"
MODEL_PATH="${RESOURCES_DIR}/YOLOv3Tiny.mlmodel"
MODEL_URL="https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3Tiny.mlmodel"
EXPECTED_SIZE_BYTES=35527626

mkdir -p "$RESOURCES_DIR"

if [[ -f "$MODEL_PATH" ]]; then
    actual_size=$(stat -f%z "$MODEL_PATH" 2>/dev/null || stat -c%s "$MODEL_PATH")
    if [[ "$actual_size" == "$EXPECTED_SIZE_BYTES" ]]; then
        echo "✓ YOLOv3Tiny.mlmodel already present and correct size."
        exit 0
    fi
    echo "⚠ Existing YOLOv3Tiny.mlmodel has unexpected size ($actual_size bytes); re-fetching."
    rm -f "$MODEL_PATH"
fi

echo "→ Downloading YOLOv3Tiny.mlmodel (35 MB) from Apple..."
curl -fL --progress-bar -o "$MODEL_PATH" "$MODEL_URL"

actual_size=$(stat -f%z "$MODEL_PATH" 2>/dev/null || stat -c%s "$MODEL_PATH")
if [[ "$actual_size" != "$EXPECTED_SIZE_BYTES" ]]; then
    echo "✗ Downloaded file has unexpected size ($actual_size bytes, expected $EXPECTED_SIZE_BYTES)."
    rm -f "$MODEL_PATH"
    exit 1
fi

echo "✓ YOLOv3Tiny.mlmodel saved to $MODEL_PATH"
echo "→ Run 'xcodegen generate' to add it to the Xcode project."
