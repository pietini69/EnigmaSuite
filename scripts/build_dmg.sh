#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION=$(grep '^version =' Cargo.toml | head -n1 | cut -d '"' -f 2)
DIST_DIR="$PROJECT_DIR/dist"
mkdir -p "$DIST_DIR"

export PATH="$HOME/.cargo/bin:$PATH"

package_target() {
    local target_name="$1"
    local bin_source="$2"
    local vol_name="EnigmaSuite ${VERSION}"
    local app_dir="$DIST_DIR/EnigmaSuite.app"
    local dmg_root="$DIST_DIR/dmg_${target_name}_root"
    local dmg_path="$DIST_DIR/EnigmaSuite-${VERSION}-${target_name}.dmg"
    local zip_path="$DIST_DIR/EnigmaSuite-${VERSION}-macos-${target_name}.zip"

    echo "==> Constructing ${target_name} EnigmaSuite.app bundle..."
    rm -rf "$app_dir" "$dmg_root"
    mkdir -p "$app_dir/Contents/MacOS"
    mkdir -p "$app_dir/Contents/Resources"

    cp "$bin_source" "$app_dir/Contents/MacOS/enigma_suite"
    chmod +x "$app_dir/Contents/MacOS/enigma_suite"
    cp "$PROJECT_DIR/Info.plist" "$app_dir/Contents/Info.plist"
    cp "$PROJECT_DIR/assets/enigma_suite.icns" "$app_dir/Contents/Resources/enigma_suite.icns"

    echo "==> Code signing bundle (ad-hoc)..."
    codesign --force --deep --sign - "$app_dir"

    echo "==> Packaging DMG: $dmg_path..."
    mkdir -p "$dmg_root"
    cp -R "$app_dir" "$dmg_root/EnigmaSuite.app"
    ln -s /Applications "$dmg_root/Applications"
    rm -f "$dmg_path"
    hdiutil create -volname "$vol_name" -srcfolder "$dmg_root" -ov -format UDZO "$dmg_path"

    echo "==> Packaging ZIP: $zip_path..."
    rm -f "$zip_path"
    (cd "$DIST_DIR" && zip -r "$zip_path" "EnigmaSuite.app")

    rm -rf "$dmg_root" "$app_dir"
    echo "==> Done: $dmg_path"
}

build_arm64() {
    echo "==> Building arm64 release binary..."
    cargo build --release --bin enigma_suite --target aarch64-apple-darwin
}

build_intel() {
    echo "==> Building x86_64 (Intel) release binary..."
    cargo build --release --bin enigma_suite --target x86_64-apple-darwin
}

build_arm64
build_intel
UNIV_BIN="$DIST_DIR/enigma_suite_universal_tmp"
echo "==> Creating Universal 2 binary with lipo..."
lipo -create -output "$UNIV_BIN" \
    "$PROJECT_DIR/target/aarch64-apple-darwin/release/enigma_suite" \
    "$PROJECT_DIR/target/x86_64-apple-darwin/release/enigma_suite"
package_target "universal" "$UNIV_BIN"
rm -f "$UNIV_BIN"

echo "=========================================="
echo " EnigmaSuite macOS Packaging Complete!"
echo "=========================================="
