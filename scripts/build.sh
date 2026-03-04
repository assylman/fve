#!/usr/bin/env bash
# Build fve native binaries for the current platform.
# Run this locally to produce a binary for testing.
# CI uses the GitHub Actions release workflow for cross-platform builds.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

mkdir -p "$BUILD_DIR"

# Detect platform + arch for the output name.
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64)        ARCH="x64"   ;;
esac

OUTPUT="$BUILD_DIR/fve-${OS}-${ARCH}"

echo "Building fve → $OUTPUT"
dart compile exe "$PROJECT_DIR/bin/fve.dart" -o "$OUTPUT"
echo "Done: $OUTPUT"
echo ""
echo "Install locally:"
echo "  cp $OUTPUT /usr/local/bin/fve"
