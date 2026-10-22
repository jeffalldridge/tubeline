#!/bin/zsh
# Builds, signs (Developer ID), notarizes and staples Tubeline, then zips it into dist/.
#
# One-time setup: a "Developer ID Application" certificate for team ACL5A8Y9U7 in
# your keychain, and notary credentials:
#   xcrun notarytool store-credentials tubeline-notary --apple-id <you> --team-id ACL5A8Y9U7
#
# Usage: scripts/release.sh [keychain-profile]   (default: tubeline-notary)
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${1:-tubeline-notary}"
BUILD=build/release
ARCHIVE="$BUILD/Tubeline.xcarchive"
EXPORT="$BUILD/export"
mkdir -p "$BUILD" dist

(cd app && xcodegen generate --quiet)
xcodebuild -project app/Tubeline.xcodeproj -scheme Tubeline -configuration Release \
  -archivePath "$ARCHIVE" archive

rm -rf "$EXPORT"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist app/ExportOptions-developer-id.plist

APP="$EXPORT/Tubeline.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="dist/Tubeline-$VERSION.zip"

ditto -c -k --keepParent "$APP" "$BUILD/notarize.zip"
xcrun notarytool submit "$BUILD/notarize.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Ready: $ZIP"
