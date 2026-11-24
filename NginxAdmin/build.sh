#!/bin/bash
# Builds "Nginx Admin.app" with the server files (compose.yaml, nginx.conf, admin/) inside it.
#
#   ./build.sh             build/Nginx Admin.app
#   ./build.sh --install   also copy it to /Applications and open it
#
# Needs: Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Nginx Admin"
APP="build/$APP_NAME.app"

echo "Building the app..."
swift build -c release --arch arm64

echo "Packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/stack"
cp ".build/arm64-apple-macosx/release/NginxAdmin" "$APP/Contents/MacOS/NginxAdmin"
cp Support/Info.plist "$APP/Contents/Info.plist"
if [[ -f Support/AppIcon.icns ]]; then cp Support/AppIcon.icns "$APP/Contents/Resources/"; fi

# Server files, used to set up the server folder on a Mac that doesn't have it yet.
cp ../compose.yaml ../nginx.conf ../stat.xsl "$APP/Contents/Resources/stack/"
mkdir -p "$APP/Contents/Resources/stack/admin/static"
cp ../admin/app.py "$APP/Contents/Resources/stack/admin/"
cp ../admin/static/index.html "$APP/Contents/Resources/stack/admin/static/"

codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "Installing to /Applications"
    pkill -x NginxAdmin 2>/dev/null || true
    pkill -x RTMPControl 2>/dev/null || true
    sleep 1
    # The app used to be called "RTMP Control": carry its settings over once, then remove it.
    OLD_ID="io.github.bigdumbrobot.RTMPControl"
    NEW_ID="io.github.bigdumbrobot.NginxAdmin"
    if defaults read "$OLD_ID" >/dev/null 2>&1 && ! defaults read "$NEW_ID" >/dev/null 2>&1; then
        defaults export "$OLD_ID" - | defaults import "$NEW_ID" -
    fi
    rm -rf "/Applications/RTMP Control.app"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
fi
echo "Done."
