#!/bin/bash
# build-pkg.sh — Build a signed & notarized .pkg installer for Mac Doctor
#
# Usage:
#   ./packaging/pkg/build-pkg.sh                    # unsigned (for testing)
#   ./packaging/pkg/build-pkg.sh --sign "Dev ID"    # signed + notarized
#
# Prerequisites for signed builds:
#   - Apple Developer ID Installer certificate in Keychain
#   - Set APPLE_ID, TEAM_ID, and APP_PASSWORD env vars for notarization

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERSION="2.1.0"
PKG_NAME="mac-doctor-${VERSION}.pkg"
BUILD_DIR="${PROJECT_ROOT}/build/pkg"
PAYLOAD_DIR="${BUILD_DIR}/payload"
SCRIPTS_DIR="${BUILD_DIR}/scripts"

SIGN_IDENTITY=""
for arg in "$@"; do
    case "$arg" in
        --sign) shift; SIGN_IDENTITY="${1:-}"; shift || true ;;
    esac
done

echo "==> Building Mac Doctor ${VERSION} installer..."

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$PAYLOAD_DIR/usr/local/bin"
mkdir -p "$PAYLOAD_DIR/usr/local/share/mac-doctor"
mkdir -p "$SCRIPTS_DIR"

# Payload — the files to install
cp "$PROJECT_ROOT/mac-doctor.sh" "$PAYLOAD_DIR/usr/local/bin/mac-doctor"
chmod 755 "$PAYLOAD_DIR/usr/local/bin/mac-doctor"

cp "$PROJECT_ROOT/packaging/launchd/mac-doctor-notify.sh" \
   "$PAYLOAD_DIR/usr/local/share/mac-doctor/mac-doctor-notify.sh"
chmod 755 "$PAYLOAD_DIR/usr/local/share/mac-doctor/mac-doctor-notify.sh"

cp "$PROJECT_ROOT/packaging/launchd/com.macdoctor.scan.plist" \
   "$PAYLOAD_DIR/usr/local/share/mac-doctor/com.macdoctor.scan.plist"

# Scripts — run after installation
cp "$SCRIPT_DIR/scripts/postinstall" "$SCRIPTS_DIR/postinstall"
chmod 755 "$SCRIPTS_DIR/postinstall"

# Build component pkg
pkgbuild \
    --root "$PAYLOAD_DIR" \
    --scripts "$SCRIPTS_DIR" \
    --identifier "com.macdoctor.pkg" \
    --version "$VERSION" \
    --install-location "/" \
    "${BUILD_DIR}/mac-doctor-component.pkg"

# Build product pkg (with welcome/license/distribution)
productbuild \
    --distribution "$SCRIPT_DIR/distribution.xml" \
    --package-path "$BUILD_DIR" \
    --resources "$SCRIPT_DIR/resources" \
    "${BUILD_DIR}/${PKG_NAME}"

# Sign if identity provided
if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> Signing with: $SIGN_IDENTITY"
    productsign \
        --sign "$SIGN_IDENTITY" \
        "${BUILD_DIR}/${PKG_NAME}" \
        "${BUILD_DIR}/${PKG_NAME}.signed"
    mv "${BUILD_DIR}/${PKG_NAME}.signed" "${BUILD_DIR}/${PKG_NAME}"

    # Notarize
    if [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APP_PASSWORD:-}" ]; then
        echo "==> Submitting for notarization..."
        xcrun notarytool submit "${BUILD_DIR}/${PKG_NAME}" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --password "$APP_PASSWORD" \
            --wait

        echo "==> Stapling notarization ticket..."
        xcrun stapler staple "${BUILD_DIR}/${PKG_NAME}"
    else
        echo "    Skipping notarization (set APPLE_ID, TEAM_ID, APP_PASSWORD to enable)"
    fi
fi

# Copy final pkg to project root
cp "${BUILD_DIR}/${PKG_NAME}" "${PROJECT_ROOT}/${PKG_NAME}"

echo ""
echo "==> Done: ${PKG_NAME}"
echo "    Size: $(du -h "${PROJECT_ROOT}/${PKG_NAME}" | awk '{print $1}')"
echo "    Signed: $([ -n "$SIGN_IDENTITY" ] && echo "Yes" || echo "No (use --sign to sign)")"
