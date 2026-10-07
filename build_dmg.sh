#!/bin/bash
# Rakentaa EnigmaSuiten Universal-julkaisun, asentaa sen Ohjelmat-kansioon ja tekee DMG:n.
set -e

DIR="/Volumes/Dataa/Ohjelmointi/ProjektitSwift/EnigmaSuite"
APP_NAME="EnigmaSuite"
BUILD_DIR="$HOME/Library/Developer/Xcode/DerivedData/EnigmaSuite-Release"
APP_SRC="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
APP_DEST="/Applications/$APP_NAME.app"
FINAL_DMG="$DIR/$APP_NAME.dmg"
TEMP_DMG="/tmp/${APP_NAME}_temp.dmg"
MOUNT_DIR="/Volumes/$APP_NAME"

echo "=== 0. Universal-julkaisu (Apple Silicon + Intel) ==="
if ! xcode-select -p | grep -q "\.app/"; then
    export DEVELOPER_DIR="$(ls -d /Applications/Xcode*.app | head -1)/Contents/Developer"
fi
xcodebuild -project "$DIR/$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$BUILD_DIR" -quiet build

ARCHS_BUILT=$(lipo -archs "$APP_SRC/Contents/MacOS/$APP_NAME")
echo "Architectures: $ARCHS_BUILT"
if [[ "$ARCHS_BUILT" != *arm64* || "$ARCHS_BUILT" != *x86_64* ]]; then
    echo "ERROR: Expected a universal binary (arm64 + x86_64)."
    exit 1
fi

echo "=== 1. Suljetaan käynnissä oleva sovellus ==="
killall "$APP_NAME" 2>/dev/null || true
sleep 1

echo "=== 2. Asennetaan: $APP_DEST ==="
rm -rf "$APP_DEST"
cp -R "$APP_SRC" "$APP_DEST"
if [ -d "$DIR/EnigmaSuite/Resources/bin" ]; then
    mkdir -p "$APP_DEST/Contents/Resources/bin"
    cp -f "$DIR/EnigmaSuite/Resources/bin/"* "$APP_DEST/Contents/Resources/bin/"
    cp -f "$DIR/EnigmaSuite/Resources/bin/"* "$APP_DEST/Contents/Resources/"
fi
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$APP_DEST" || true

echo "=== 3. Tehdään DMG ==="
if [ -d "$MOUNT_DIR" ]; then
    hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
fi
rm -f "$TEMP_DMG" "$FINAL_DMG"
hdiutil create -size 200m -fs HFS+ -volname "$APP_NAME" "$TEMP_DMG"
hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_DIR" -nobrowse
cp -R "$APP_DEST" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"
sync
hdiutil detach "$MOUNT_DIR" -force
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG"
rm -f "$TEMP_DMG"

echo "=== Valmis! ==="
ls -lh "$FINAL_DMG"
