#!/bin/bash

set -e

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# The name of your Scheme and App (usually the same)
APP_NAME="AppTidy"

# Your Team ID (from Apple Developer Portal)
TEAM_ID="CL6XWJCS9R"

# The name of the Keychain Profile created with `xcrun notarytool store-credentials`
KEYCHAIN_PROFILE="AppTidyProfile"

# ==============================================================================
# SCRIPT START
# ==============================================================================

ARCHIVE_PATH="./build/${APP_NAME}.xcarchive"
EXPORT_PATH="./build/Export"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
ZIP_PATH="${EXPORT_PATH}/${APP_NAME}.zip"
EXPORT_OPTIONS_PLIST="${EXPORT_PATH}/ExportOptions.plist"

echo "----------------------------------------------------------------"
echo "  🚀 ${APP_NAME} Release Automation"
echo "----------------------------------------------------------------"

# 0. Clean Build Directory
rm -rf "./build"
mkdir -p "$EXPORT_PATH"

# 1. Archive
echo "📦 Archiving..."
xcodebuild archive \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -quiet

# 2. Generate ExportOptions.plist
echo "⚙️  Generating Export Options..."
cat <<EOF > "$EXPORT_OPTIONS_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
</dict>
</plist>
EOF

# 3. Export
echo "📤 Exporting..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -exportPath "$EXPORT_PATH" \
  -quiet

# 4. Zip for Notarization
echo "🤐 Zipping for Notarization..."
cd "$EXPORT_PATH"
zip -r "${APP_NAME}.zip" "${APP_NAME}.app"
cd - > /dev/null

# 5. Notarize
echo "📝 Notarizing..."
echo "Using Keychain Profile: $KEYCHAIN_PROFILE"

xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

# 6. Staple
echo "📎 Stapling..."
xcrun stapler staple "$APP_PATH"

# 7. Final Zip
echo "🎁 Creating Final Distribution Zip..."
cd "$EXPORT_PATH"
zip -r "${APP_NAME}_Final.zip" "${APP_NAME}.app"
cd - > /dev/null

echo "----------------------------------------------------------------"
echo "✅ Release Build Complete!"
echo "File: $EXPORT_PATH/${APP_NAME}_Final.zip"
echo "----------------------------------------------------------------"
