#!/usr/bin/env bash
# Builds a local DIY disk image without publishing or opening the app.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_BUDDY=/usr/libexec/PlistBuddy
APP_NAME="Status Trio DIY"
BUNDLE_ID=local.statustrio.diy.status-strip
VERSION="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$ROOT/Support/Info.plist")"
BASE_BUILD="$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$ROOT/Support/Info.plist")"
BUILD="${1:-}"
OUT_DIR="${2:-}"

if [[ $# -ne 2 || ! "$BUILD" =~ ^[1-9][0-9]{0,8}$ || -z "$OUT_DIR" ]]; then
    echo "Usage: bash scripts/package-diy.sh <build-number> <output-directory>" >&2
    exit 2
fi
if (( BUILD <= BASE_BUILD )); then
    echo "Error: DIY build must be greater than base build $BASE_BUILD." >&2
    exit 2
fi

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
ARCH="$(uname -m)"
DMG="$OUT_DIR/Status-Trio-DIY-$VERSION-$BUILD-$ARCH.dmg"
if [[ -e "$DMG" || -L "$DMG" ]]; then
    echo "Error: refusing to replace $DMG." >&2
    exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioDIY.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/staging"
APP="$WORK/staging/$APP_NAME.app"
env -u SU_FEED_URL -u DEVELOPMENT_CODENAME \
    APP_NAME="$APP_NAME" BUNDLE_ID="$BUNDLE_ID" \
    APP_VERSION="$VERSION" BUILD_NUMBER="$BUILD" APP_OUTPUT_PATH="$APP" \
    UNIVERSAL_BUILD=0 TELEMETRY_PRODUCTION=0 DISABLE_PRODUCTION_UPDATES=1 \
    PRIVILEGED_HELPER=1 CODE_SIGN_IDENTITY=- \
    bash "$ROOT/scripts/build-app.sh" release no-open

PLIST="$APP/Contents/Info.plist"
if [[ "$("$PLIST_BUDDY" -c 'Print :CFBundleIdentifier' "$PLIST")" != "$BUNDLE_ID" ||
      "$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$PLIST")" != "$VERSION" ||
      "$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$PLIST")" != "$BUILD" ]]; then
    echo 'Error: DIY package identity or version does not match the requested build.' >&2
    exit 1
fi
for key in SUFeedURL SUPublicEDKey SUEnableInstallerLauncherService; do
    if "$PLIST_BUDDY" -c "Print :$key" "$PLIST" >/dev/null 2>&1; then
        echo "Error: DIY package still contains production update key $key." >&2
        exit 1
    fi
done
for binary in Contents/MacOS/StatusTrio Contents/Frameworks/libStatusTrioCore.dylib; do
    if [[ "$(lipo -archs "$APP/$binary")" != "$ARCH" ]]; then
        echo "Error: expected $ARCH for $binary." >&2
        exit 1
    fi
done
helper_archs="$(lipo -archs "$APP/Contents/Helpers/StatusTrioMobileBatteryHelper")"
if [[ " $helper_archs " != *" $ARCH "* ]]; then
    echo "Error: the MobileBattery helper cannot run on $ARCH." >&2
    exit 1
fi

ln -s /Applications "$WORK/staging/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$WORK/staging" -format UDZO "$WORK/image.dmg"
hdiutil verify "$WORK/image.dmg"
# Do not clobber an image created during the build.
mv -n "$WORK/image.dmg" "$DMG"
if [[ -e "$WORK/image.dmg" ]]; then
    echo "Error: refusing to replace $DMG." >&2
    exit 1
fi
shasum -a 256 "$DMG"
