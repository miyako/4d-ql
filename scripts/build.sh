#!/bin/bash
# Builds "4D Quick Look.app" with the embedded Quick Look preview extension.
#
#   scripts/build.sh                 universal release build, ad-hoc signed
#   scripts/build.sh --register      ...then register it with Launch Services / Quick Look
#
# Environment:
#   SIGN_IDENTITY   codesign identity (default "-" = ad-hoc, fine for local use;
#                   use "Developer ID Application: ..." for distribution + notarization)
#   BUNDLE_ID       base bundle identifier (default com.github.miyako.FourDQuickLook)
#   VERSION         marketing version (default 0.1.0)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
SIGN_IDENTITY=${SIGN_IDENTITY:--}
BUNDLE_ID=${BUNDLE_ID:-com.github.miyako.FourDQuickLook}
VERSION=${VERSION:-0.1.0}
BUILD=${BUILD:-$(date +%Y%m%d%H%M)}
ARCHS=(--arch arm64 --arch x86_64)

echo "==> swift build (release, universal)"
swift build -c release "${ARCHS[@]}" --product fourdql
swift build -c release "${ARCHS[@]}" --product FourDQuickLookExtension
swift build -c release "${ARCHS[@]}" --product FourDQuickLookHost
BIN=$(swift build -c release "${ARCHS[@]}" --show-bin-path)

APP="$ROOT/build/4D Quick Look.app"
APPEX="$APP/Contents/PlugIns/4D Preview.appex"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"

cp "$BIN/FourDQuickLookHost" "$APP/Contents/MacOS/"
cp "$BIN/FourDQuickLookExtension" "$APPEX/Contents/MacOS/"
cp "$BIN/fourdql" "$ROOT/build/fourdql"

# QLSupportedContentTypes comes from the analyzer registry (single source of truth).
TYPES_FILE="$ROOT/build/content-types.xml"
"$BIN/fourdql" --content-types | sed 's|.*|				<string>&</string>|' > "$TYPES_FILE"

fill() { # template output
    sed -e "/__CONTENT_TYPES__/r $TYPES_FILE" -e "/__CONTENT_TYPES__/d" \
        -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" -e "s|__VERSION__|$VERSION|g" -e "s|__BUILD__|$BUILD|g" "$1" > "$2"
    plutil -lint -s "$2"
}
fill Support/Host-Info.plist "$APP/Contents/Info.plist"
fill Support/Extension-Info.plist "$APPEX/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> codesign ($SIGN_IDENTITY)"
RUNTIME=()
[ "$SIGN_IDENTITY" != "-" ] && RUNTIME=(--options runtime --timestamp)
codesign --force --sign "$SIGN_IDENTITY" ${RUNTIME[@]+"${RUNTIME[@]}"} --entitlements Support/Extension.entitlements "$APPEX"
codesign --force --sign "$SIGN_IDENTITY" ${RUNTIME[@]+"${RUNTIME[@]}"} "$APP"
codesign --verify --deep --strict "$APP"

echo "==> built $APP"

if [ "${1:-}" = "--register" ]; then
    echo "==> registering"
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    "$LSREGISTER" -f -R "$APP"
    pluginkit -a "$APPEX"
    pluginkit -e use -i "$BUNDLE_ID.Preview" || true
    qlmanage -r >/dev/null 2>&1 || true
    qlmanage -r cache >/dev/null 2>&1 || true
    pluginkit -m -v -i "$BUNDLE_ID.Preview"
fi
