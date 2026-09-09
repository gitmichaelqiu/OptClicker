#!/bin/bash
set -euo pipefail

CURRENT_BUNDLE_IDENTIFIER="dev.mqiu.OptClicker"
STAGED_APPLICATION_NAME="OptClicker-Migration.app"
DEFAULT_PACKAGE_IDENTIFIER="dev.mqiu.OptClicker.migration"
SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
    cat <<'EOF'
Usage: build-migration-package.sh --app PATH --version BUILD \
    --update-feed-url URL [options]

Builds the package that stages a current-ID OptClicker app at
/Applications/OptClicker-Migration.app for the legacy bridge handoff.

Required:
  --app PATH                    Final current-ID OptClicker.app
  --version BUILD               CFBundleVersion of the staged app/package
  --update-feed-url URL         Shared Sparkle appcast URL

Options:
  --output PATH                 Destination .pkg (default: tmp/OptClicker-Migration.pkg)
  --package-identifier ID       Installer package identifier
  --signing-identity NAME       Developer ID Installer identity
  --notary-profile NAME         notarytool keychain profile
  --skip-notarization           Skip notarization and Gatekeeper checks
  --manual-approval              Use the development/manual-approval workflow
EOF
}

die() { echo "error: $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }
absolute_path() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$PWD" "$1" ;; esac; }
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }

APP_PATH=""
PACKAGE_VERSION=""
UPDATE_FEED_URL=""
OUTPUT_PATH="tmp/OptClicker-Migration.pkg"
PACKAGE_IDENTIFIER="$DEFAULT_PACKAGE_IDENTIFIER"
SIGNING_IDENTITY="${DEVELOPER_ID_INSTALLER:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SKIP_NOTARIZATION=0
MANUAL_APPROVAL=0

while (($# > 0)); do
    case "$1" in
        --app) APP_PATH="${2:?}"; shift 2 ;;
        --version) PACKAGE_VERSION="${2:?}"; shift 2 ;;
        --update-feed-url) UPDATE_FEED_URL="${2:?}"; shift 2 ;;
        --output) OUTPUT_PATH="${2:?}"; shift 2 ;;
        --package-identifier) PACKAGE_IDENTIFIER="${2:?}"; shift 2 ;;
        --signing-identity) SIGNING_IDENTITY="${2:?}"; shift 2 ;;
        --notary-profile) NOTARY_PROFILE="${2:?}"; shift 2 ;;
        --skip-notarization) SKIP_NOTARIZATION=1; shift ;;
        --manual-approval) MANUAL_APPROVAL=1; SKIP_NOTARIZATION=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[[ -n "$APP_PATH" ]] || die "--app is required"
[[ "$PACKAGE_VERSION" =~ ^[0-9]+([.][0-9]+){0,3}$ ]] || die "--version must be a numeric build number"
[[ "$UPDATE_FEED_URL" =~ ^https://[^[:space:]]+$ ]] || die "--update-feed-url must be HTTPS"
[[ "$PACKAGE_IDENTIFIER" =~ ^[A-Za-z0-9.-]+$ ]] || die "invalid package identifier"
if ((MANUAL_APPROVAL == 0 && SKIP_NOTARIZATION == 0)); then
    [[ -n "$SIGNING_IDENTITY" ]] || die "use --manual-approval or provide a Developer ID Installer identity"
    [[ -n "$NOTARY_PROFILE" ]] || die "--notary-profile or NOTARY_PROFILE is required"
fi

APP_PATH="$(absolute_path "$APP_PATH")"
OUTPUT_PATH="$(absolute_path "$OUTPUT_PATH")"
[[ -d "$APP_PATH/Contents" ]] || die "app bundle not found: $APP_PATH"
[[ ! -e "$OUTPUT_PATH" ]] || die "output already exists: $OUTPUT_PATH"
for command_name in codesign ditto mkdir pkgbuild pkgutil shasum; do require_command "$command_name"; done

APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ "$(plist_value "$APP_INFO_PLIST" CFBundleIdentifier)" == "$CURRENT_BUNDLE_IDENTIFIER" ]] || die "staged app has the wrong bundle identifier"
[[ "$(plist_value "$APP_INFO_PLIST" CFBundleVersion)" == "$PACKAGE_VERSION" ]] || die "staged app build number does not match --version"
[[ "$(plist_value "$APP_INFO_PLIST" SUFeedURL)" == "$UPDATE_FEED_URL" ]] || die "staged app feed URL does not match --update-feed-url"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/OptClickerMigrationPackage.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
PACKAGE_ROOT="$WORK_DIR/root"
mkdir -p "$PACKAGE_ROOT/Applications"
ditto "$APP_PATH" "$PACKAGE_ROOT/Applications/$STAGED_APPLICATION_NAME"

if ! codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1 && ((MANUAL_APPROVAL == 0)); then
    die "staged app failed strict code-signature verification"
fi

PACKAGE_ARGUMENTS=(
    --root "$PACKAGE_ROOT"
    --identifier "$PACKAGE_IDENTIFIER"
    --version "$PACKAGE_VERSION"
    --install-location /
    --scripts "$SCRIPT_DIRECTORY/migration-package-scripts"
)
[[ -n "$SIGNING_IDENTITY" ]] && PACKAGE_ARGUMENTS+=(--sign "$SIGNING_IDENTITY")
mkdir -p "$(dirname "$OUTPUT_PATH")"
pkgbuild "${PACKAGE_ARGUMENTS[@]}" "$OUTPUT_PATH"

if ((SKIP_NOTARIZATION == 0)); then
    xcrun notarytool submit "$OUTPUT_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$OUTPUT_PATH"
    xcrun stapler validate -q "$OUTPUT_PATH"
    spctl --assess --type install --verbose=2 "$OUTPUT_PATH"
fi

echo "Migration package: $OUTPUT_PATH"
echo "Migration package SHA256: $(shasum -a 256 "$OUTPUT_PATH" | awk '{print tolower($1)}')"
