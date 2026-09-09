#!/bin/bash
set -euo pipefail

LEGACY_BUNDLE_IDENTIFIER="michaelqiu.OptClicker"
CURRENT_BUNDLE_IDENTIFIER="dev.mqiu.OptClicker"
STAGED_APPLICATION_NAME="OptClicker-Migration.app"
DEFAULT_STAGING_PATH="/Applications/$STAGED_APPLICATION_NAME"

die() { echo "error: $*" >&2; exit 1; }
absolute_path() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$PWD" "$1" ;; esac; }
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }
assert_equal() { [[ "$2" == "$3" ]] || die "$1 mismatch (expected '$2', got '$3')"; }

BRIDGE_APP=""
BRIDGE_DMG=""
MIGRATION_PACKAGE=""
MARKETING_VERSION=""
BUILD_NUMBER=""
RELEASE_TAG=""
FEED_URL=""
MIGRATION_PACKAGE_URL=""
MIGRATION_PACKAGE_SHA256=""
MIGRATION_PACKAGE_VERSION=""
STAGING_PATH="$DEFAULT_STAGING_PATH"

while (($# > 0)); do
    case "$1" in
        --bridge-dmg) BRIDGE_DMG="${2:?}"; shift 2 ;;
        --bridge-app) BRIDGE_APP="${2:?}"; shift 2 ;;
        --migration-package) MIGRATION_PACKAGE="${2:?}"; shift 2 ;;
        --version) MARKETING_VERSION="${2:?}"; shift 2 ;;
        --build-number) BUILD_NUMBER="${2:?}"; shift 2 ;;
        --release-tag) RELEASE_TAG="${2:?}"; shift 2 ;;
        --feed-url) FEED_URL="${2:?}"; shift 2 ;;
        --migration-package-url) MIGRATION_PACKAGE_URL="${2:?}"; shift 2 ;;
        --migration-package-sha256) MIGRATION_PACKAGE_SHA256="${2:?}"; shift 2 ;;
        --migration-package-version) MIGRATION_PACKAGE_VERSION="${2:?}"; shift 2 ;;
        --staging-path) STAGING_PATH="${2:?}"; shift 2 ;;
        -h|--help) echo "See Scripts/README.md for verification usage."; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[[ -n "$MIGRATION_PACKAGE" ]] || die "--migration-package is required"
[[ -n "$BRIDGE_DMG" || -n "$BRIDGE_APP" ]] || die "--bridge-dmg or --bridge-app is required"
[[ -z "$BRIDGE_DMG" || -z "$BRIDGE_APP" ]] || die "--bridge-dmg and --bridge-app are mutually exclusive"
BRIDGE_DMG="${BRIDGE_DMG:+$(absolute_path "$BRIDGE_DMG")}"; BRIDGE_APP="${BRIDGE_APP:+$(absolute_path "$BRIDGE_APP")}"
MIGRATION_PACKAGE="$(absolute_path "$MIGRATION_PACKAGE")"
[[ -f "$MIGRATION_PACKAGE" ]] || die "migration package not found"
[[ -n "$BRIDGE_APP" && -d "$BRIDGE_APP/Contents" || -n "$BRIDGE_DMG" ]] || die "bridge artifact not found"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/OptClickerBridgeVerification.XXXXXX")"
trap 'hdiutil detach -quiet "$WORK_DIR/mount" >/dev/null 2>&1 || true; rm -rf "$WORK_DIR"' EXIT
if [[ -n "$BRIDGE_DMG" ]]; then
    mkdir -p "$WORK_DIR/mount"
    hdiutil attach -nobrowse -readonly -mountpoint "$WORK_DIR/mount" "$BRIDGE_DMG" >/dev/null
    BRIDGE_APP="$WORK_DIR/mount/OptClicker.app"
fi

BRIDGE_INFO_PLIST="$BRIDGE_APP/Contents/Info.plist"
assert_equal "bridge bundle identifier" "$LEGACY_BUNDLE_IDENTIFIER" "$(plist_value "$BRIDGE_INFO_PLIST" CFBundleIdentifier)"
assert_equal "bridge marketing version" "$MARKETING_VERSION" "$(plist_value "$BRIDGE_INFO_PLIST" CFBundleShortVersionString)"
assert_equal "bridge build number" "$BUILD_NUMBER" "$(plist_value "$BRIDGE_INFO_PLIST" CFBundleVersion)"
assert_equal "bridge feed URL" "$FEED_URL" "$(plist_value "$BRIDGE_INFO_PLIST" SUFeedURL)"
assert_equal "bridge package URL" "$MIGRATION_PACKAGE_URL" "$(plist_value "$BRIDGE_INFO_PLIST" OptClickerMigrationPackageURL)"
assert_equal "bridge package checksum" "$(printf '%s' "$MIGRATION_PACKAGE_SHA256" | tr '[:upper:]' '[:lower:]')" "$(plist_value "$BRIDGE_INFO_PLIST" OptClickerMigrationPackageSHA256)"
assert_equal "bridge package version" "$MIGRATION_PACKAGE_VERSION" "$(plist_value "$BRIDGE_INFO_PLIST" OptClickerMigrationPackageVersion)"
assert_equal "bridge staging path" "$STAGING_PATH" "$(plist_value "$BRIDGE_INFO_PLIST" OptClickerMigrationStagingPath)"
assert_equal "bridge release tag" "$RELEASE_TAG" "$(plist_value "$BRIDGE_INFO_PLIST" OptClickerReleaseTag)"

assert_equal "migration package SHA256" "$(printf '%s' "$MIGRATION_PACKAGE_SHA256" | tr '[:upper:]' '[:lower:]')" "$(shasum -a 256 "$MIGRATION_PACKAGE" | awk '{print tolower($1)}')"
EXPANDED_PACKAGE="$WORK_DIR/expanded-package"
pkgutil --expand-full "$MIGRATION_PACKAGE" "$EXPANDED_PACKAGE" >/dev/null
STAGED_APP="$EXPANDED_PACKAGE/Payload/Applications/$STAGED_APPLICATION_NAME"
STAGED_INFO_PLIST="$STAGED_APP/Contents/Info.plist"
[[ -f "$STAGED_INFO_PLIST" ]] || die "migration package does not stage the expected app"
assert_equal "staged bundle identifier" "$CURRENT_BUNDLE_IDENTIFIER" "$(plist_value "$STAGED_INFO_PLIST" CFBundleIdentifier)"
assert_equal "staged build number" "$MIGRATION_PACKAGE_VERSION" "$(plist_value "$STAGED_INFO_PLIST" CFBundleVersion)"
assert_equal "staged feed URL" "$FEED_URL" "$(plist_value "$STAGED_INFO_PLIST" SUFeedURL)"
echo "OptClicker bridge release verification passed"
