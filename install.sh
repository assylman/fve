#!/usr/bin/env sh
# fve installer — Flutter Version & Environment Manager
# Usage: curl -sSL https://assylman.github.io/fve/install.sh | sh
set -e

REPO="assylman/fve"           # ← update with your GitHub username
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="fve"

# ── Detect platform ────────────────────────────────────────────────────────

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Darwin)
    platform="macos"
    ;;
  Linux)
    platform="linux"
    ;;
  *)
    echo "Error: Unsupported operating system: $os"
    echo "fve currently supports macOS and Linux."
    exit 1
    ;;
esac

case "$arch" in
  arm64|aarch64)
    arch="arm64"
    ;;
  x86_64)
    arch="x64"
    ;;
  *)
    echo "Error: Unsupported architecture: $arch"
    exit 1
    ;;
esac

# Linux arm64 is not yet distributed — fall back to a helpful message.
if [ "$platform" = "linux" ] && [ "$arch" = "arm64" ]; then
  echo "Error: Linux arm64 binaries are not yet available."
  echo "Please build from source: https://github.com/$REPO"
  exit 1
fi

artifact="fve-${platform}-${arch}"

# ── Find the latest release ────────────────────────────────────────────────

echo "Detecting latest fve release..."

if command -v curl > /dev/null 2>&1; then
  latest=$(curl -sSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
elif command -v wget > /dev/null 2>&1; then
  latest=$(wget -qO- "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
else
  echo "Error: curl or wget is required to install fve."
  exit 1
fi

if [ -z "$latest" ]; then
  echo "Error: Could not determine the latest release."
  echo "Check https://github.com/$REPO/releases"
  exit 1
fi

echo "Latest release: $latest"

# ── Download binary ────────────────────────────────────────────────────────

url="https://github.com/$REPO/releases/download/$latest/$artifact"
tmp="$(mktemp)"

echo "Downloading $artifact..."

if command -v curl > /dev/null 2>&1; then
  curl -sSL "$url" -o "$tmp"
else
  wget -qO "$tmp" "$url"
fi

# ── Install ────────────────────────────────────────────────────────────────

chmod +x "$tmp"

if [ -w "$INSTALL_DIR" ]; then
  mv "$tmp" "$INSTALL_DIR/$BINARY_NAME"
else
  echo "Installing to $INSTALL_DIR (requires sudo)..."
  sudo mv "$tmp" "$INSTALL_DIR/$BINARY_NAME"
fi

echo ""
echo "✓ fve $latest installed to $INSTALL_DIR/$BINARY_NAME"
echo ""

# ── Shell PATH setup ──────────────────────────────────────────────────────

echo "Next steps:"
echo ""
echo "  1. Run: fve setup --write"
echo "     (Adds ~/.fve/current/bin to your PATH so 'flutter' and 'dart'"
echo "      automatically use fve-managed versions)"
echo ""
echo "  2. Install a Flutter version:"
echo "     fve install 3.22.2"
echo ""
echo "  3. Pin it to your project:"
echo "     cd your-project && fve use 3.22.2"
echo ""
echo "Docs: https://github.com/$REPO"
