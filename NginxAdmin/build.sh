#!/bin/bash
# Builds "Nginx Admin.app" (Apple silicon + Intel) with the server files (compose.yaml,
# nginx.conf, admin/) inside it.
#
#   ./build.sh             build/Nginx Admin.app
#   ./build.sh --install   also copy it to /Applications and open it
#   ./build.sh --release   also make dist/Nginx-Admin-<version>.dmg and .zip for a GitHub release
#
# Signing: by default the app is signed ad hoc, so people who download it must allow it once in
# System Settings → Privacy & Security. To sign and notarize with an Apple Developer ID instead:
#   export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   export NOTARY_PROFILE="nginx-admin"   # made once with: xcrun notarytool store-credentials nginx-admin
#
# Needs: Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Nginx Admin"
APP="build/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

sign() {
    if [[ -n "$SIGN_IDENTITY" ]]; then
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$1"
    else
        codesign --force --sign - "$1"
    fi
}

notarize() {
    [[ -n "$SIGN_IDENTITY" && -n "$NOTARY_PROFILE" ]] || return 0
    echo "Notarizing $(basename "$1") (takes a few minutes)..."
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

echo "Building the app $VERSION (Apple silicon + Intel)..."
swift build -c release --arch arm64 --arch x86_64

echo "Packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/stack"
cp ".build/apple/Products/Release/NginxAdmin" "$APP/Contents/MacOS/NginxAdmin"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/"

# Server files, used to set up the server folder on a Mac that doesn't have it yet.
cp ../compose.yaml ../nginx.conf ../stat.xsl "$APP/Contents/Resources/stack/"
mkdir -p "$APP/Contents/Resources/stack/admin/static"
cp ../admin/app.py "$APP/Contents/Resources/stack/admin/"
cp ../admin/static/index.html "$APP/Contents/Resources/stack/admin/static/"

sign "$APP"

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

if [[ "${1:-}" == "--release" ]]; then
    BASE="Nginx-Admin-$VERSION"
    mkdir -p dist
    rm -f "dist/$BASE.dmg" "dist/$BASE.zip"

    # Notarize the app itself first, so both the zip and the DMG carry a stapled app.
    if [[ -n "$SIGN_IDENTITY" && -n "$NOTARY_PROFILE" ]]; then
        ditto -c -k --keepParent "$APP" "build/notarize.zip"
        notarize "build/notarize.zip"
        xcrun stapler staple "$APP"
        rm -f "build/notarize.zip"
    fi

    echo "Making dist/$BASE.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$BASE.zip"

    echo "Making dist/$BASE.dmg"
    STAGE="build/dmg"
    rm -rf "$STAGE"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -quiet -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "dist/$BASE.dmg"
    rm -rf "$STAGE"
    if [[ -n "$SIGN_IDENTITY" ]]; then
        sign "dist/$BASE.dmg"
        notarize "dist/$BASE.dmg"
        [[ -n "$NOTARY_PROFILE" ]] && xcrun stapler staple "dist/$BASE.dmg"
    fi

    (cd dist && shasum -a 256 "$BASE.dmg" "$BASE.zip" > "$BASE.sha256")
    echo "Release files:"
    ls -lh dist/"$BASE".*
fi
echo "Done."
