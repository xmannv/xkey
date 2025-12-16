#!/bin/bash

# Build Release version of XKey with Developer ID code signing
# Output will be copied to ./Release/XKey.app

set -e  # Exit on error

# Configuration
ENABLE_CODESIGN=${ENABLE_CODESIGN:-true}  # Set to false to disable code signing
ENABLE_NOTARIZE=${ENABLE_NOTARIZE:-false}  # Set to true to enable notarization
BUNDLE_ID="com.codetay.XKey"

echo "🚀 Building XKey (Release configuration)..."

# Create Release directory
mkdir -p Release

# Detect Developer ID if code signing is enabled
if [ "$ENABLE_CODESIGN" = true ]; then
    echo "🔍 Detecting Developer ID certificate..."
    
    # Find Developer ID Application certificate
    DEVELOPER_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
    
    if [ -z "$DEVELOPER_ID" ]; then
        echo "⚠️  No Developer ID Application certificate found in keychain"
        echo "   Available certificates:"
        security find-identity -v -p codesigning
        echo ""
        echo "   Building without code signing..."
        ENABLE_CODESIGN=false
    else
        echo "✅ Found: $DEVELOPER_ID"
        
        # Extract Team ID from certificate
        TEAM_ID=$(echo "$DEVELOPER_ID" | sed -E 's/.*\(([A-Z0-9]+)\).*/\1/')
        echo "✅ Team ID: $TEAM_ID"
    fi
fi

# Clean previous build
echo "🧹 Cleaning previous build..."
xcodebuild -project XKey.xcodeproj -scheme XKey -configuration Release -derivedDataPath ./build clean

# Build with or without code signing
echo "🔨 Building Release..."

if [ "$ENABLE_CODESIGN" = true ]; then
    echo "🔐 Code signing enabled with: $DEVELOPER_ID"
    xcodebuild -project XKey.xcodeproj \
      -scheme XKey \
      -configuration Release \
      -derivedDataPath ./build \
      PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
      DEVELOPMENT_TEAM="$TEAM_ID" \
      CODE_SIGNING_REQUIRED=YES \
      CODE_SIGNING_ALLOWED=YES \
      OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
      build
else
    echo "⚠️  Code signing disabled"
    xcodebuild -project XKey.xcodeproj \
      -scheme XKey \
      -configuration Release \
      -derivedDataPath ./build \
      PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY="-" \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGNING_ALLOWED=NO \
      build
fi

# Copy to Release directory
echo "📦 Copying to ./Release/XKey.app..."
rm -rf Release/XKey.app
cp -R "./build/Build/Products/Release/XKey.app" Release/

# Verify code signature
if [ "$ENABLE_CODESIGN" = true ]; then
    echo "🔍 Verifying code signature..."
    codesign -vvv --deep --strict Release/XKey.app
    echo "✅ Code signature verified"
    
    # Display signature info
    echo ""
    echo "📝 Signature details:"
    codesign -dvvv Release/XKey.app 2>&1 | grep -E "(Authority|Identifier|TeamIdentifier|Timestamp)"
fi

# Notarization (optional)
if [ "$ENABLE_NOTARIZE" = true ] && [ "$ENABLE_CODESIGN" = true ]; then
    echo ""
    echo "📤 Notarizing with Apple..."
    echo "⚠️  This requires:"
    echo "   - Apple ID"
    echo "   - App-specific password"
    echo "   - Team ID"
    echo ""
    echo "   Run: xcrun notarytool submit Release/XKey.app --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID --password YOUR_APP_PASSWORD --wait"
    echo "   Then: xcrun stapler staple Release/XKey.app"
fi

# Clear macOS launch services cache
echo ""
echo "🧹 Clearing macOS cache..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user

echo ""
echo "✅ Build successful!"

echo ""
echo "✅ Done! Release build is ready at:"
echo "   $(pwd)/Release/XKey.app"
echo ""
echo "📊 App size:"
du -sh Release/XKey.app
echo ""

if [ "$ENABLE_CODESIGN" = true ]; then
    echo "🔐 Code signing: ENABLED"
    echo "   Certificate: $DEVELOPER_ID"
else
    echo "⚠️  Code signing: DISABLED"
fi

echo ""
echo "📦 To create signed DMG for distribution:"
if [ "$ENABLE_CODESIGN" = true ]; then
    echo "   hdiutil create -volname XKey -srcfolder Release/XKey.app -ov -format UDZO Release/XKey.dmg"
    echo "   codesign --sign \"$DEVELOPER_ID\" --timestamp Release/XKey.dmg"
else
    echo "   hdiutil create -volname XKey -srcfolder Release/XKey.app -ov -format UDZO Release/XKey.dmg"
fi

echo ""
echo "💡 Usage:"
echo "   Default (with code signing):  ./build_release.sh"
echo "   Without code signing:         ENABLE_CODESIGN=false ./build_release.sh"
echo "   With notarization:            ENABLE_NOTARIZE=true ./build_release.sh"
