#!/bin/bash
set -euo pipefail

# Build script for ReLay
# Creates a proper macOS app bundle with code signing.
#
# Usage:
#   ./build.sh              # build to .build/release/ReLay.app only
#   ./build.sh --install    # copy latest build into /Applications/ReLay.app

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/.build/release"
APP_NAME="ReLay"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
BINARY="${BUILD_DIR}/${APP_NAME}"
APP_BINARY="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
ICON_ICNS="${PROJECT_DIR}/Resources/AppIcon.icns"
INSTALL=0

for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        -h|--help)
            echo "Usage: $0 [--install]"
            echo "  (default)  Build and sign .build/release/ReLay.app"
            echo "  --install  Copy the new build into /Applications/ReLay.app"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

# Step 1: Build the executable
echo "Building executable via SPM..."
swift build -c release

# Step 2: Create app bundle structure
echo "Creating app bundle structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Step 3: Copy executable
echo "Copying executable..."
cp "${BINARY}" "${APP_BINARY}"
chmod +x "${APP_BINARY}"

# Step 4: Copy Info.plist + icon
echo "Copying Info.plist..."
cp "${PROJECT_DIR}/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
if [ -f "${ICON_ICNS}" ]; then
    echo "Copying AppIcon.icns..."
    cp "${ICON_ICNS}" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
else
    echo "Warning: ${ICON_ICNS} missing — app will use the default icon"
fi

# Step 5: Code sign
echo "Code signing app bundle..."

SIGNING_IDENTITY=""
if [ -n "${SIGNING_IDENTITY_OVERRIDE:-}" ]; then
    SIGNING_IDENTITY="$SIGNING_IDENTITY_OVERRIDE"
else
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | head -1 | awk -F'"' '{print $2}' | head -1)
fi

if [ -z "$SIGNING_IDENTITY" ]; then
    echo "Using ad-hoc signing (permission state may not persist across rebuilds)"
    codesign -f -s - "${APP_BUNDLE}" 2>&1 | grep -v "code has no resources" || true
else
    echo "Using identity: $SIGNING_IDENTITY"
    codesign -f -s "${SIGNING_IDENTITY}" "${APP_BUNDLE}" 2>&1 | grep -v "code has no resources" || true
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Build complete: ${APP_BUNDLE}"
echo "   SHA256: $(shasum -a 256 "${APP_BINARY}" | awk '{print $1}')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Step 6: Optional install — real copy into /Applications (not a symlink)
# so Finder/Dock reliably show AppIcon.icns.
if [ "$INSTALL" -eq 1 ]; then
    DEST="/Applications/${APP_NAME}.app"
    BACKUP_ROOT="${PROJECT_DIR}/archives"
    mkdir -p "${BACKUP_ROOT}"

    if [ -L "${DEST}" ] || [ -d "${DEST}" ] || [ -e "${DEST}" ]; then
        STAMP=$(date +%Y%m%d-%H%M%S)
        BACKUP="${BACKUP_ROOT}/ReLay.app.bak-${STAMP}"
        echo "Backing up existing ${DEST} → ${BACKUP}"
        rm -rf "${BACKUP}"
        mv "${DEST}" "${BACKUP}"
        if [ -f "${BACKUP}/Contents/MacOS/${APP_NAME}" ]; then
            echo "   SHA256: $(shasum -a 256 "${BACKUP}/Contents/MacOS/${APP_NAME}" | awk '{print $1}')"
        fi
    fi

    echo "Copying ${APP_BUNDLE} → ${DEST}"
    ditto "${APP_BUNDLE}" "${DEST}"
    # Re-sign the installed copy so Gatekeeper/Launch Services see a coherent bundle
    if [ -z "$SIGNING_IDENTITY" ]; then
        codesign -f -s - "${DEST}" 2>&1 | grep -v "code has no resources" || true
    else
        codesign -f -s "${SIGNING_IDENTITY}" "${DEST}" 2>&1 | grep -v "code has no resources" || true
    fi
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${DEST}" 2>/dev/null || true
    touch "${DEST}"
    echo "Installed:"
    ls -la "${DEST}"
    echo "Icon: ${DEST}/Contents/Resources/AppIcon.icns"
    echo "Quit any running ReLay, then open ${DEST}"
else
    echo ""
    echo "Not linked into /Applications (pass --install to do that)."
    echo "Run the build with: open \"${APP_BUNDLE}\""
fi
