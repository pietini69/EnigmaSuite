#!/usr/bin/env bash
set -euo pipefail

# EnigmaSuite All-Platforms Packaging Script (macOS, Windows, Linux)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION=$(grep '^version =' Cargo.toml | head -n1 | cut -d '"' -f 2)
DIST_DIR="$PROJECT_DIR/dist"
mkdir -p "$DIST_DIR"

echo "=========================================="
echo " Building EnigmaSuite v${VERSION} for all platforms"
echo "=========================================="

# 1. macOS Universal
echo "==> 1/3 Building macOS Universal DMG..."
chmod +x ./scripts/build_dmg.sh
./scripts/build_dmg.sh

# 2. Windows x86_64
echo "==> 2/3 Building Windows x86_64..."
if command -v cargo-xwin &>/dev/null; then
    cargo xwin build --release --target x86_64-pc-windows-msvc
    mkdir -p "$DIST_DIR/win_tmp"
    cp "$PROJECT_DIR/target/x86_64-pc-windows-msvc/release/enigma_suite.exe" "$DIST_DIR/win_tmp/EnigmaSuite.exe"
    (cd "$DIST_DIR/win_tmp" && zip -r "../EnigmaSuite-${VERSION}-windows-x64.zip" EnigmaSuite.exe)
    rm -rf "$DIST_DIR/win_tmp"
    echo "    Windows binary built: $DIST_DIR/EnigmaSuite-${VERSION}-windows-x64.zip"
else
    echo "    (cargo-xwin not installed, skipping Windows cross-build; run cargo install cargo-xwin)"
fi

# 3. Linux x86_64
echo "==> 3/3 Building Linux x86_64..."
if command -v cargo-zigbuild &>/dev/null; then
    cargo zigbuild --release --target x86_64-unknown-linux-gnu.2.17
    mkdir -p "$DIST_DIR/linux_tmp"
    cp "$PROJECT_DIR/target/x86_64-unknown-linux-gnu/release/enigma_suite" "$DIST_DIR/linux_tmp/enigma_suite"
    chmod +x "$DIST_DIR/linux_tmp/enigma_suite"
    (cd "$DIST_DIR/linux_tmp" && tar -czvf "../EnigmaSuite-${VERSION}-linux-x64.tar.gz" enigma_suite)
    rm -rf "$DIST_DIR/linux_tmp"
    echo "    Linux binary built: $DIST_DIR/EnigmaSuite-${VERSION}-linux-x64.tar.gz"
else
    echo "    (cargo-zigbuild not installed, skipping Linux cross-build)"
fi

echo "=========================================="
echo " All-Platforms Build Completed!"
echo " Outputs in: $DIST_DIR"
ls -lh "$DIST_DIR"
echo "=========================================="
