#!/bin/zsh
# Builds a notarized Tubeline release: Developer ID–signed, notarized and stapled app in a
# notarized DMG, plus the notarized `tubeline` command-line tool, SHA-256 checksums and
# release notes from CHANGELOG.md. With --publish it also tags the release and creates the
# GitHub Release.
#
# One-time setup on the release Mac:
#   - "Developer ID Application: Tent Studios, LLC (ACL5A8Y9U7)" in the login keychain
#   - a notarytool keychain profile:
#       xcrun notarytool store-credentials tubeline-notary \
#         --apple-id <apple-id> --team-id ACL5A8Y9U7 --password <app-specific-password>
#     (any existing profile for the team works: TUBELINE_NOTARY_PROFILE=<name>)
#   - XcodeGen and the GitHub CLI (`brew install xcodegen gh`)
#
# Usage:
#   scripts/release.sh             # build + notarize into build/release/
#   scripts/release.sh --publish   # ... then tag v<version>, push the tag, create the release
#
# The version comes from MARKETING_VERSION in app/project.yml, and CHANGELOG.md must have a
# "## [<version>]" section.
set -euo pipefail
cd "$(dirname "$0")/.."

PUBLISH=0
[[ "${1:-}" == "--publish" ]] && PUBLISH=1

PROFILE="${TUBELINE_NOTARY_PROFILE:-tubeline-notary}"
AUTHORITY="Developer ID Application: Tent Studios, LLC (ACL5A8Y9U7)"
VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' app/project.yml | head -1)
TAG="v$VERSION"
OUT=build/release
APP_NAME=Tubeline

echo "==> Tubeline $VERSION"

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------
[[ -n "$VERSION" ]] || { echo "error: MARKETING_VERSION not found in app/project.yml" >&2; exit 1; }
grep -q "^## \[$VERSION\]" CHANGELOG.md || { echo "error: CHANGELOG.md has no [$VERSION] section" >&2; exit 1; }
security find-identity -v -p codesigning | grep -Fq "$AUTHORITY" \
  || { echo "error: '$AUTHORITY' is not in the keychain" >&2; exit 1; }
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || { echo "error: notarytool profile '$PROFILE' is missing (see header)" >&2; exit 1; }
if (( PUBLISH )); then
  [[ -z "$(git status --porcelain)" ]] || { echo "error: working tree is not clean" >&2; exit 1; }
  ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "error: tag $TAG already exists" >&2; exit 1; }
fi
echo "==> preflight OK (notary profile: $PROFILE)"

rm -rf "$OUT"
mkdir -p "$OUT"

# ---------------------------------------------------------------------------
# 2. Test, archive, export (Developer ID)
# ---------------------------------------------------------------------------
(cd app && xcodegen generate --quiet)
echo "==> tests"
xcodebuild -project app/Tubeline.xcodeproj -scheme Tubeline -derivedDataPath "$OUT/dd" -quiet test

echo "==> archive"
xcodebuild -project app/Tubeline.xcodeproj -scheme Tubeline -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$OUT/$APP_NAME.xcarchive" -quiet archive

echo "==> export (developer-id)"
xcodebuild -exportArchive -archivePath "$OUT/$APP_NAME.xcarchive" \
  -exportOptionsPlist app/ExportOptions-developer-id.plist -exportPath "$OUT/export" \
  -allowProvisioningUpdates -quiet
APP="$OUT/export/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "error: export produced no $APP" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 3. Verify what we ship
# ---------------------------------------------------------------------------
echo "==> verify signature, entitlements, architecture"
codesign --verify --deep --strict "$APP"
details=$(codesign -dv --verbose=4 "$APP" 2>&1)
entitlements=$(codesign -d --entitlements - "$APP" 2>/dev/null)
grep -Fq "Authority=$AUTHORITY" <<<"$details" || { echo "error: not signed by $AUTHORITY" >&2; exit 1; }
grep -q "flags=0x10000(runtime)" <<<"$details" || { echo "error: hardened runtime is off" >&2; exit 1; }
grep -q "com.apple.security.app-sandbox" <<<"$entitlements" || { echo "error: sandbox entitlement missing" >&2; exit 1; }
! grep -q "get-task-allow" <<<"$entitlements" || { echo "error: development-signed (get-task-allow)" >&2; exit 1; }
[[ "$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")" == "arm64" ]] || { echo "error: expected arm64-only binary" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]] \
  || { echo "error: app version does not match $VERSION" >&2; exit 1; }
! /usr/libexec/PlistBuddy -c 'Print CFBundleIconFile' "$APP/Contents/Info.plist" >/dev/null 2>&1 \
  || { echo "error: stale CFBundleIconFile (validator error 90236)" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 4. Notarize + staple the app
# ---------------------------------------------------------------------------
echo "==> notarize app"
ditto -c -k --keepParent "$APP" "$OUT/notarize-app.zip"
xcrun notarytool submit "$OUT/notarize-app.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose "$APP"

# ---------------------------------------------------------------------------
# 5. DMG: sign, notarize, staple
# ---------------------------------------------------------------------------
DMG="$OUT/$APP_NAME-$VERSION.dmg"
echo "==> dmg"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$AUTHORITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

# ---------------------------------------------------------------------------
# 6. Command-line tool: sign (hardened runtime), notarize, zip
# ---------------------------------------------------------------------------
echo "==> command-line tool"
swift build -c release --arch arm64 --product tubeline >/dev/null
CLI_DIR="$OUT/cli/tubeline-$VERSION"
mkdir -p "$CLI_DIR"
cp "$(swift build -c release --arch arm64 --show-bin-path)/tubeline" "$CLI_DIR/tubeline"
cp LICENSE "$CLI_DIR/"
codesign --force --options runtime --timestamp --sign "$AUTHORITY" "$CLI_DIR/tubeline"
"$CLI_DIR/tubeline" Samples/heart.svg -o "$OUT/cli-check" >/dev/null   # smoke test the shipped binary
CLI_ZIP="$OUT/tubeline-cli-$VERSION.zip"
ditto -c -k --keepParent "$CLI_DIR" "$CLI_ZIP"
xcrun notarytool submit "$CLI_ZIP" --keychain-profile "$PROFILE" --wait

# ---------------------------------------------------------------------------
# 7. Checksums + notes
# ---------------------------------------------------------------------------
(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" "$(basename "$CLI_ZIP")" > SHA256SUMS.txt && cat SHA256SUMS.txt)
NOTES="$OUT/release-notes.md"
awk -v want="## [$VERSION]" '/^## \[/ { if (p) exit; if (index($0, want) == 1) { p = 1; next } } /^\[.*\]: / { next } p' CHANGELOG.md > "$NOTES"
cat >> "$NOTES" <<EOF

---

**Install:** open \`$APP_NAME-$VERSION.dmg\` and drag Tubeline to Applications. Requires an Apple silicon Mac with macOS 14 or later. The app and the command-line tool are signed by Tent Studios, LLC and notarized by Apple.

**Command line:** unzip \`tubeline-cli-$VERSION.zip\` and run \`./tubeline --help\`.
EOF

echo "==> artifacts in $OUT: $(basename "$DMG"), $(basename "$CLI_ZIP"), SHA256SUMS.txt"

# ---------------------------------------------------------------------------
# 8. Publish
# ---------------------------------------------------------------------------
if (( PUBLISH )); then
  echo "==> tag $TAG and publish GitHub release"
  git tag -a "$TAG" -m "Tubeline $VERSION"
  git push origin "$TAG"
  gh release create "$TAG" "$DMG" "$CLI_ZIP" "$OUT/SHA256SUMS.txt" \
    --title "Tubeline $VERSION" --notes-file "$NOTES" --verify-tag
fi
