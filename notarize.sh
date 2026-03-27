#!/usr/bin/env bash
# ============================================================
# notarize.sh — build, notarize, and staple MiddleMouseFocus
# ============================================================
#
# ONE-TIME SETUP (run this once, then never again):
#
#   xcrun notarytool store-credentials "middlemousefocus-notary" \
#     --apple-id "your@appleid.com" \
#     --team-id "8BC58HVUU8" \
#     --password "xxxx-xxxx-xxxx-xxxx"   # app-specific password from appleid.apple.com
#
# Generate the app-specific password at:
#   https://appleid.apple.com → Sign-In and Security → App-Specific Passwords
# ============================================================

set -euo pipefail

APP_NAME="MiddleMouseFocus"
BUNDLE_ID="dev.himon.middlemousefocus"
TEAM_ID="8BC58HVUU8"
KEYCHAIN_PROFILE="middlemousefocus-notary"

# ── Helpers ──────────────────────────────────────────────────

pass() { echo "  ✓ $*"; }
fail() { echo "  ✗ $*" >&2; exit 1; }
step() { echo; echo "▶ $*"; }

# ── Pre-flight checks ────────────────────────────────────────

step "Pre-flight checks"

# Required tools
for tool in xcodebuild create-dmg xcrun; do
    command -v "$tool" &>/dev/null || fail "Required tool not found: $tool"
done
pass "Required tools present (xcodebuild, create-dmg, xcrun)"

# Project file
[ -f "${APP_NAME}.xcodeproj/project.pbxproj" ] || \
    fail "Project not found — run this script from the repo root"
pass "Project file found"

# Developer ID certificate
CERT=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | grep "$TEAM_ID" | head -1)
[ -n "$CERT" ] || fail "No 'Developer ID Application' certificate found for team $TEAM_ID in keychain.
       Generate one at developer.apple.com → Certificates."
pass "Developer ID Application certificate found"

# Notarytool credentials — use `history` as a lightweight auth check
xcrun notarytool history \
    --keychain-profile "$KEYCHAIN_PROFILE" &>/dev/null || \
    fail "Notarytool credentials not found or invalid for profile '${KEYCHAIN_PROFILE}'.
       Run the one-time setup command at the top of this script."
pass "Notarytool credentials validated"

# ── Build ─────────────────────────────────────────────────────

VERSION=$(defaults read "$(pwd)/App/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.2")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DERIVED_DATA="$(mktemp -d)/build"

# Clean up derived data on exit (success or failure)
trap 'rm -rf "${DERIVED_DATA}"' EXIT

step "Building ${APP_NAME} ${VERSION} (Release, Developer ID)"
XCODE_ARGS=(
    -project "${APP_NAME}.xcodeproj"
    -scheme "${APP_NAME}"
    -configuration Release
    -derivedDataPath "${DERIVED_DATA}"
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="Developer ID Application"
    PROVISIONING_PROFILE_SPECIFIER=""
    ENABLE_HARDENED_RUNTIME=YES
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
    OTHER_CODE_SIGN_FLAGS="--timestamp"
    clean build
)

if command -v xcpretty &>/dev/null; then
    xcodebuild "${XCODE_ARGS[@]}" | xcpretty
else
    xcodebuild "${XCODE_ARGS[@]}"
fi

APP_PATH="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"
[ -d "${APP_PATH}" ] || fail "App bundle not found after build — check build output above"
pass "App bundle produced"

# ── Post-build validation ─────────────────────────────────────

step "Validating app bundle"

# Bundle ID matches
BUILT_ID=$(defaults read "${APP_PATH}/Contents/Info" CFBundleIdentifier 2>/dev/null || true)
[ "$BUILT_ID" = "$BUNDLE_ID" ] || \
    fail "Bundle ID mismatch: expected '${BUNDLE_ID}', got '${BUILT_ID}'"
pass "Bundle ID correct (${BUNDLE_ID})"

# Code signature is valid and deep
codesign --verify --deep --strict "${APP_PATH}" 2>/dev/null || \
    fail "Code signature verification failed"
pass "Code signature valid"

# Signed with Developer ID (not Apple Development)
SIGN_ID=$(codesign -dvv "${APP_PATH}" 2>&1 | grep "^Authority" | head -1)
echo "$SIGN_ID" | grep -q "Developer ID Application" || \
    fail "App is not signed with Developer ID Application.
       Got: ${SIGN_ID}
       Ensure the Release scheme uses Developer ID signing."
pass "Signed with Developer ID Application"

# Hardened Runtime is enabled (appears as flags=0x10000(runtime) in CodeDirectory line)
CODESIGN_INFO=$(codesign -dvv "${APP_PATH}" 2>&1)
echo "$CODESIGN_INFO" | grep -q "runtime" || {
    echo "  Debug — codesign output:"
    echo "$CODESIGN_INFO" | sed 's/^/    /'
    fail "Hardened Runtime is not enabled — notarization will be rejected.
       Enable it in Build Settings → Hardened Runtime."
}
pass "Hardened Runtime enabled"

# Secure timestamp is present (required by Apple notarization)
echo "$CODESIGN_INFO" | grep -q "Timestamp=" || \
    fail "Signature is missing a secure timestamp — add OTHER_CODE_SIGN_FLAGS=--timestamp to the build."
pass "Secure timestamp present"

# get-task-allow entitlement must not be present (Apple rejects it)
ENTITLEMENTS=$(codesign -d --entitlements :- "${APP_PATH}" 2>/dev/null || true)
echo "$ENTITLEMENTS" | grep -q "get-task-allow" && \
    fail "Entitlements contain com.apple.security.get-task-allow — Apple will reject this.
       Ensure CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO is passed to xcodebuild."
pass "No get-task-allow entitlement"

# ── Package DMG ───────────────────────────────────────────────

step "Creating DMG (${DMG_NAME})"
rm -f "${DMG_NAME}"
create-dmg \
    --volname "${APP_NAME}" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 128 \
    --icon "${APP_NAME}.app" 180 185 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 420 185 \
    "${DMG_NAME}" \
    "${APP_PATH}"

[ -f "${DMG_NAME}" ] || fail "DMG was not created"
pass "DMG created ($(du -sh "${DMG_NAME}" | cut -f1))"

# ── Notarize ──────────────────────────────────────────────────

step "Submitting for notarization (this takes ~1–2 minutes)"
NOTARY_OUTPUT=$(xcrun notarytool submit "${DMG_NAME}" \
    --keychain-profile "${KEYCHAIN_PROFILE}" \
    --wait 2>&1)
echo "$NOTARY_OUTPUT"

echo "$NOTARY_OUTPUT" | grep -q "status: Accepted" || \
    fail "Notarization was not accepted — check the output above.
       Retrieve detailed logs with:
         xcrun notarytool log <submission-id> --keychain-profile ${KEYCHAIN_PROFILE}"
pass "Notarization accepted by Apple"

# ── Staple & final check ──────────────────────────────────────

step "Stapling notarization ticket"
xcrun stapler staple "${DMG_NAME}"
pass "Ticket stapled"

step "Final Gatekeeper assessment"
MOUNT_POINT=$(mktemp -d)
hdiutil attach "${DMG_NAME}" -mountpoint "${MOUNT_POINT}" -quiet -nobrowse
spctl --assess --type exec "${MOUNT_POINT}/${APP_NAME}.app" || {
    hdiutil detach "${MOUNT_POINT}" -quiet
    fail "Gatekeeper rejected the app inside the DMG — something went wrong with notarization or stapling"
}
hdiutil detach "${MOUNT_POINT}" -quiet
pass "Gatekeeper accepts the notarized app"

# ── Done ──────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
echo "  ✓  ${DMG_NAME} is ready to distribute"
echo "════════════════════════════════════════"
