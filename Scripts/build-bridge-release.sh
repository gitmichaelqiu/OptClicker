#!/bin/bash
set -euo pipefail

LEGACY_BUNDLE_IDENTIFIER="michaelqiu.OptClicker"
DEFAULT_STAGING_PATH="/Applications/OptClicker-Migration.app"
SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_PATH="$SCRIPT_DIRECTORY/../OptClicker.xcodeproj"

usage() {
    cat <<'EOF'
Usage: build-bridge-release.sh --version VERSION --build-number BUILD \
    --release-tag TAG --feed-url URL --migration-package-url URL \
    --migration-package-sha256 SHA256 --migration-package-version BUILD \
    [--output-dir PATH] [--manual-approval]

Builds the legacy-bundle-ID bridge DMG. The bridge downloads the pinned
migration package and hands off to the current bundle ID.
EOF
}

die() { echo "error: $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }
absolute_path() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$PWD" "$1" ;; esac; }
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }

MARKETING_VERSION=""
BUILD_NUMBER=""
RELEASE_TAG=""
FEED_URL=""
MIGRATION_PACKAGE_URL=""
MIGRATION_PACKAGE_SHA256=""
MIGRATION_PACKAGE_VERSION=""
STAGING_PATH="$DEFAULT_STAGING_PATH"
OUTPUT_DIRECTORY="tmp/OptClicker-bridge-release"
MANUAL_APPROVAL=0

while (($# > 0)); do
    case "$1" in
        --version) MARKETING_VERSION="${2:?}"; shift 2 ;;
        --build-number) BUILD_NUMBER="${2:?}"; shift 2 ;;
        --release-tag) RELEASE_TAG="${2:?}"; shift 2 ;;
        --feed-url) FEED_URL="${2:?}"; shift 2 ;;
        --migration-package-url) MIGRATION_PACKAGE_URL="${2:?}"; shift 2 ;;
        --migration-package-sha256) MIGRATION_PACKAGE_SHA256="${2:?}"; shift 2 ;;
        --migration-package-version) MIGRATION_PACKAGE_VERSION="${2:?}"; shift 2 ;;
        --staging-path) STAGING_PATH="${2:?}"; shift 2 ;;
        --output-dir) OUTPUT_DIRECTORY="${2:?}"; shift 2 ;;
        --manual-approval) MANUAL_APPROVAL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[[ "$MARKETING_VERSION" =~ ^[0-9]+([.][0-9]+){1,3}$ ]] || die "invalid --version"
[[ "$BUILD_NUMBER" =~ ^[0-9]+([.][0-9]+){0,3}$ ]] || die "invalid --build-number"
[[ "$MIGRATION_PACKAGE_VERSION" =~ ^[0-9]+([.][0-9]+){0,3}$ ]] || die "invalid --migration-package-version"
[[ "$RELEASE_TAG" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid --release-tag"
[[ "$FEED_URL" =~ ^https://[^[:space:]]+$ ]] || die "--feed-url must be HTTPS"
[[ "$MIGRATION_PACKAGE_URL" =~ ^https://[^[:space:]]+$ ]] || die "--migration-package-url must be HTTPS"
[[ "$MIGRATION_PACKAGE_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || die "invalid migration package SHA256"
[[ "$STAGING_PATH" == /* && "$STAGING_PATH" == *.app ]] || die "invalid --staging-path"

for command_name in codesign ditto hdiutil mkdir shasum xcodebuild; do require_command "$command_name"; done
OUTPUT_DIRECTORY="$(absolute_path "$OUTPUT_DIRECTORY")"
mkdir -p "$OUTPUT_DIRECTORY"
BRIDGE_APP_PATH="$OUTPUT_DIRECTORY/OptClicker.app"
DMG_PATH="$OUTPUT_DIRECTORY/OptClicker-$MARKETING_VERSION-$RELEASE_TAG.dmg"
[[ ! -e "$BRIDGE_APP_PATH" && ! -e "$DMG_PATH" ]] || die "bridge output already exists"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/OptClickerBridgeRelease.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
ARCHIVE_PATH="$WORK_DIR/OptClickerBridge.xcarchive"
DERIVED_DATA_PATH="$WORK_DIR/DerivedData"

xcodebuild -quiet \
    -project "$PROJECT_PATH" \
    -scheme OptClickerBridge \
    -configuration Bridge \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    MARKETING_VERSION="$MARKETING_VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    OPTCLICKER_UPDATE_FEED_URL="$FEED_URL" \
    OPTCLICKER_MIGRATION_PACKAGE_URL="$MIGRATION_PACKAGE_URL" \
    OPTCLICKER_MIGRATION_PACKAGE_SHA256="$(printf '%s' "$MIGRATION_PACKAGE_SHA256" | tr '[:upper:]' '[:lower:]')" \
    OPTCLICKER_MIGRATION_PACKAGE_VERSION="$MIGRATION_PACKAGE_VERSION" \
    OPTCLICKER_MIGRATION_ALLOW_MANUAL_APPROVAL="$MANUAL_APPROVAL" \
    OPTCLICKER_MIGRATION_STAGING_PATH="$STAGING_PATH" \
    OPTCLICKER_RELEASE_TAG="$RELEASE_TAG"

ARCHIVED_APP_PATH="$ARCHIVE_PATH/Products/Applications/OptClicker.app"
[[ -d "$ARCHIVED_APP_PATH/Contents" ]] || die "archive did not contain OptClicker.app"
ditto "$ARCHIVED_APP_PATH" "$BRIDGE_APP_PATH"
APP_INFO_PLIST="$BRIDGE_APP_PATH/Contents/Info.plist"
[[ "$(plist_value "$APP_INFO_PLIST" CFBundleIdentifier)" == "$LEGACY_BUNDLE_IDENTIFIER" ]] || die "bridge has the wrong bundle identifier"
[[ "$(plist_value "$APP_INFO_PLIST" CFBundleShortVersionString)" == "$MARKETING_VERSION" ]] || die "bridge version mismatch"
[[ "$(plist_value "$APP_INFO_PLIST" CFBundleVersion)" == "$BUILD_NUMBER" ]] || die "bridge build mismatch"
[[ "$(plist_value "$APP_INFO_PLIST" OptClickerMigrationPackageURL)" == "$MIGRATION_PACKAGE_URL" ]] || die "bridge package URL mismatch"
[[ "$(plist_value "$APP_INFO_PLIST" OptClickerMigrationPackageSHA256)" == "$(printf '%s' "$MIGRATION_PACKAGE_SHA256" | tr '[:upper:]' '[:lower:]')" ]] || die "bridge package checksum mismatch"
[[ "$(plist_value "$APP_INFO_PLIST" OptClickerMigrationPackageVersion)" == "$MIGRATION_PACKAGE_VERSION" ]] || die "bridge package version mismatch"
[[ "$(plist_value "$APP_INFO_PLIST" OptClickerReleaseTag)" == "$RELEASE_TAG" ]] || die "bridge release tag mismatch"

hdiutil create -volname OptClicker -srcfolder "$BRIDGE_APP_PATH" -ov -format UDZO "$DMG_PATH"
echo "Bridge app: $BRIDGE_APP_PATH"
echo "Bridge DMG: $DMG_PATH"
echo "Bridge DMG SHA256: $(shasum -a 256 "$DMG_PATH" | awk '{print tolower($1)}')"
