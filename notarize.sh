#!/bin/bash

# Configuration
APP_PATH="build/Release/AppTidy.app"
ZIP_PATH="AppTidy_Release_Signed.zip"
TEAM_ID="44LGHR6NC7" # Your Team ID

# Check if zip exists
if [ ! -f "$ZIP_PATH" ]; then
    echo "Error: $ZIP_PATH not found. Please build the app first."
    exit 1
fi

echo "----------------------------------------------------------------"
echo "  AppTidy Notarization Helper"
echo "----------------------------------------------------------------"
echo "To notarize, you need an App-Specific Password."
echo "1. Go to https://appleid.apple.com"
echo "2. Sign in and go to 'App-Specific Passwords'"
echo "3. Generate a new one (e.g. name it 'AppTidy Notarization')"
echo "----------------------------------------------------------------"

# Get Credentials
read -p "Enter your Apple ID (email): " APPLE_ID
read -s -p "Enter your App-Specific Password: " APP_SPECIFIC_PASSWORD
echo ""

echo "----------------------------------------------------------------"
echo "Step 1: Uploading to Apple Notary Service..."
echo "This may take a few minutes."
echo "----------------------------------------------------------------"

# Submit to Apple
xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait

# Check return code
if [ $? -ne 0 ]; then
    echo "----------------------------------------------------------------"
    echo "❌ Notarization Failed."
    echo "Check the error message above."
    exit 1
fi

echo "----------------------------------------------------------------"
echo "Step 2: Stapling the ticket to the App..."
echo "----------------------------------------------------------------"

# Staple the ticket
xcrun stapler staple "$APP_PATH"

if [ $? -eq 0 ]; then
    echo "----------------------------------------------------------------"
    echo "✅ Success! App is notarized and stapled."
    echo "You can now zip '$APP_PATH' and distribute it."
    echo "----------------------------------------------------------------"
    
    # Re-zip the stapled app
    echo "Creating final distribution zip..."
    zip -r AppTidy_Final_Distribution.zip "$APP_PATH"
    echo "Created: AppTidy_Final_Distribution.zip"
else
    echo "❌ Stapling failed."
fi
