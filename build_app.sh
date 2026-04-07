#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

echo "Building release binary..."
swift build -c release

echo "Done. Binary is at: $ROOT_DIR/.build/release/BADDADApp"
