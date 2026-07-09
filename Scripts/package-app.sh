#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Wisper Clone"
BUILD_APP_DIR="$ROOT_DIR/.build/app/$APP_NAME.app"
LEGACY_DIST_DIR="$ROOT_DIR/dist"
LEGACY_DIST_APP_DIR="$LEGACY_DIST_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALL_APP_DIR="$INSTALL_DIR/$APP_NAME.app"
EXECUTABLE="$ROOT_DIR/.build/release/WisperClone"
SIGNING_IDENTITY="$("$ROOT_DIR/Scripts/ensure-local-signing-identity.sh")"
INSTALL=false
OPEN_APP=false

usage() {
    cat <<EOF
Usage: Scripts/package-app.sh [--install] [--open]

Builds a signed staging app bundle at:
  $BUILD_APP_DIR

Options:
  --install  Copy the app to ~/Applications so Spotlight can find it.
  --open     Launch the packaged or installed app after building.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            INSTALL=true
            shift
            ;;
        --open)
            OPEN_APP=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

swift build -c release --product WisperClone

rm -rf "$BUILD_APP_DIR"
mkdir -p "$BUILD_APP_DIR/Contents/MacOS" "$BUILD_APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$BUILD_APP_DIR/Contents/MacOS/WisperClone"
cp "$ROOT_DIR/Sources/wisper-clone/Resources/AppInfo.plist" "$BUILD_APP_DIR/Contents/Info.plist"

codesign --force --deep --sign "$SIGNING_IDENTITY" "$BUILD_APP_DIR"

APP_TO_OPEN="$BUILD_APP_DIR"

if [[ "$INSTALL" == true ]]; then
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_APP_DIR"
    cp -R "$BUILD_APP_DIR" "$INSTALL_APP_DIR"
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$INSTALL_APP_DIR"

    if [[ -x "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" ]]; then
        if [[ -d "$LEGACY_DIST_APP_DIR" ]]; then
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -u "$LEGACY_DIST_APP_DIR" || true
        fi
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -f "$INSTALL_APP_DIR"
    fi

    if [[ -d "$LEGACY_DIST_APP_DIR" ]]; then
        rm -rf "$LEGACY_DIST_APP_DIR"
        rmdir "$LEGACY_DIST_DIR" 2>/dev/null || true
    fi

    APP_TO_OPEN="$INSTALL_APP_DIR"
fi

if [[ "$OPEN_APP" == true ]]; then
    open "$APP_TO_OPEN"
fi

echo "$APP_TO_OPEN"
