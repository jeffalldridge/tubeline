#!/bin/zsh
# Builds, signs, notarizes and staples Tubeline, then packages it as a zip in dist/.
#
# One-time setup:
#   1. Put your team in Config/Local.xcconfig:  DEVELOPMENT_TEAM = ABCDE12345
#   2. Have a "Developer ID Application" certificate in your keychain.
#   3. Store notary credentials:
#        xcrun notarytool store-credentials tubeline-notary --apple-id you@example.com --team-id ABCDE12345
#
# Usage: Scripts/release.sh [keychain-profile]   (default profile: tubeline-notary)
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${1:-tubeline-notary}"
BUILD=build/release
ARCHIVE="$BUILD/Tubeline.xcarchive"
EXPORT="$BUILD/export"
mkdir -p "$BUILD" dist

if command -v xcodegen >/dev/null; then xcodegen generate --quiet; fi

xcodebuild -project Tubeline.xcodeproj -scheme Tubeline -configuration Release \
  -archivePath "$ARCHIVE" archive

cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST

rm -rf "$EXPORT"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$BUILD/ExportOptions.plist"

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
