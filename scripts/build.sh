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
#   PROJECT_GROUP   shared app group (signed builds default to
#                   <Team ID>.<BUNDLE_ID>.ProjectContext; disabled for ad-hoc builds)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
SIGN_IDENTITY=${SIGN_IDENTITY:--}
BUNDLE_ID=${BUNDLE_ID:-com.github.miyako.FourDQuickLook}
VERSION=${VERSION:-0.1.0}
PROJECT_GROUP=${PROJECT_GROUP:-}
BUILD=${BUILD:-$(date +%Y%m%d%H%M)}
ARCHS=(--arch arm64 --arch x86_64)

echo "==> swift build (release, universal)"
swift build -c release "${ARCHS[@]}" --product fourdql
swift build -c release "${ARCHS[@]}" --product FourDQuickLookExtension
swift build -c release "${ARCHS[@]}" --product FourDQuickLookHost
swift build -c release "${ARCHS[@]}" --product FourDProjectPreviewService
BIN=$(swift build -c release "${ARCHS[@]}" --show-bin-path)

APP="$ROOT/build/4D Quick Look.app"
APPEX="$APP/Contents/PlugIns/4D Preview.appex"
SERVICE="$APP/Contents/XPCServices/4D Project Preview.xpc"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"
mkdir -p "$SERVICE/Contents/MacOS"

cp "$BIN/FourDQuickLookHost" "$APP/Contents/MacOS/"
cp "$BIN/FourDQuickLookExtension" "$APPEX/Contents/MacOS/"
cp "$BIN/fourdql" "$ROOT/build/fourdql"
cp "$BIN/FourDProjectPreviewService" "$SERVICE/Contents/MacOS/"

TEAM_ID=""
if [ "$SIGN_IDENTITY" != "-" ]; then
    PROBE="$ROOT/build/ProjectSigningProbe"
    cp "$BIN/FourDQuickLookHost" "$PROBE"
    codesign --force --sign "$SIGN_IDENTITY" "$PROBE"
    TEAM_ID=$(codesign -dv --verbose=4 "$PROBE" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    rm -f "$PROBE"
    if [ -z "$TEAM_ID" ] || [ "$TEAM_ID" = "not set" ]; then
        echo "Cannot determine the signing team for project-context access." >&2
        exit 1
    fi
    PROJECT_GROUP=${PROJECT_GROUP:-$TEAM_ID.$BUNDLE_ID.ProjectContext}
fi
if [ "$SIGN_IDENTITY" = "-" ] && [ -n "$PROJECT_GROUP" ]; then
    echo "Project-context sharing requires a team-signed build; do not grant broad access to other apps' data." >&2
    exit 1
fi

# QLSupportedContentTypes comes from the analyzer registry (single source of truth).
TYPES_FILE="$ROOT/build/content-types.xml"
"$BIN/fourdql" --content-types | sed 's|.*|				<string>&</string>|' > "$TYPES_FILE"

fill() { # template output
    sed -e "/__CONTENT_TYPES__/r $TYPES_FILE" -e "/__CONTENT_TYPES__/d" \
        -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" -e "s|__PROJECT_GROUP__|$PROJECT_GROUP|g" \
        -e "s|__VERSION__|$VERSION|g" -e "s|__BUILD__|$BUILD|g" "$1" > "$2"
    plutil -lint -s "$2"
}
fill Support/Host-Info.plist "$APP/Contents/Info.plist"
fill Support/Extension-Info.plist "$APPEX/Contents/Info.plist"
fill Support/ProjectService-Info.plist "$SERVICE/Contents/Info.plist"
fill Support/Host.entitlements "$ROOT/build/Host.entitlements"
fill Support/Extension.entitlements "$ROOT/build/Extension.entitlements"
fill Support/ProjectService.entitlements "$ROOT/build/ProjectService.entitlements"
if [ -z "$PROJECT_GROUP" ]; then
    /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.application-groups' "$ROOT/build/Host.entitlements"
    /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.application-groups' "$ROOT/build/Extension.entitlements"
    /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.application-groups' "$ROOT/build/ProjectService.entitlements"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> codesign ($SIGN_IDENTITY)"
RUNTIME=()
[ "$SIGN_IDENTITY" != "-" ] && RUNTIME=(--options runtime --timestamp)
codesign --force --sign "$SIGN_IDENTITY" ${RUNTIME[@]+"${RUNTIME[@]}"} --entitlements "$ROOT/build/ProjectService.entitlements" "$SERVICE"
mkdir -p "$APPEX/Contents/XPCServices"
ditto "$SERVICE" "$APPEX/Contents/XPCServices/4D Project Preview.xpc"
codesign --force --sign "$SIGN_IDENTITY" ${RUNTIME[@]+"${RUNTIME[@]}"} --entitlements "$ROOT/build/Extension.entitlements" "$APPEX"
codesign --force --sign "$SIGN_IDENTITY" ${RUNTIME[@]+"${RUNTIME[@]}"} --entitlements "$ROOT/build/Host.entitlements" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> built $APP"

if [ "${1:-}" = "--register" ]; then
    echo "==> registering"
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

    # Unregister other copies with the same bundle ID (e.g. another checkout or
    # /Applications). Otherwise macOS may keep using one of them instead of this build.
    # pluginkit only lists the copy it elected, so read Launch Services' database.
    "$LSREGISTER" -dump 2>/dev/null | awk -v want="$BUNDLE_ID.Preview" '
        /^-----/       { if (id == want && p != "") print p; p = ""; id = "" }
        /^path:/       { sub(/^path: +/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); p = $0 }
        /^identifier:/ { sub(/^identifier: +/, ""); id = $0 }
        END            { if (id == want && p != "") print p }' | sort -u |
    while IFS= read -r other; do
        [ "$other" = "$APPEX" ] && continue
        echo "    unregistering $other"
        pluginkit -r "$other" >/dev/null 2>&1 || true
        "$LSREGISTER" -u "$other" >/dev/null 2>&1 || true
        "$LSREGISTER" -u "${other%/Contents/PlugIns/*}" >/dev/null 2>&1 || true
    done

    "$LSREGISTER" -f -R "$APP"
    pluginkit -a "$APPEX"
    pluginkit -e use -i "$BUNDLE_ID.Preview" || true
    qlmanage -r >/dev/null 2>&1 || true
    qlmanage -r cache >/dev/null 2>&1 || true
    pluginkit -m -v -i "$BUNDLE_ID.Preview"
fi
