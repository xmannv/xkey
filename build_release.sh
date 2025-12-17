#!/bin/bash

# Build Release version of XKey with Developer ID code signing
# Output will be copied to ./Release/XKey.app and ./Release/XKey.dmg

set -e  # Exit on error

# Load environment variables from .env file
if [ -f ".env" ]; then
    echo "📄 Loading environment variables from .env..."
    export $(grep -v '^#' .env | xargs)
fi

# Configuration
ENABLE_CODESIGN=${ENABLE_CODESIGN:-true}  # Set to false to disable code signing
ENABLE_NOTARIZE=${ENABLE_NOTARIZE:-false}  # Set to true to enable notarization
ENABLE_DMG=${ENABLE_DMG:-true}  # Set to false to skip DMG creation
BUNDLE_ID="com.codetay.XKey"
APP_NAME="XKey"
DMG_NAME="XKey.dmg"
DMG_VOLUME_NAME="XKey"

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
echo "🔨 Building Universal Binary (Intel + Apple Silicon)..."

if [ "$ENABLE_CODESIGN" = true ]; then
    echo "🔐 Code signing enabled with: $DEVELOPER_ID"
    xcodebuild -project XKey.xcodeproj \
      -scheme XKey \
      -configuration Release \
      -derivedDataPath ./build \
      -arch x86_64 -arch arm64 \
      ONLY_ACTIVE_ARCH=NO \
      PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
      DEVELOPMENT_TEAM="$TEAM_ID" \
      CODE_SIGNING_REQUIRED=YES \
      CODE_SIGNING_ALLOWED=YES \
      CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
      OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
      build
else
    echo "⚠️  Code signing disabled"
    xcodebuild -project XKey.xcodeproj \
      -scheme XKey \
      -configuration Release \
      -derivedDataPath ./build \
      -arch x86_64 -arch arm64 \
      ONLY_ACTIVE_ARCH=NO \
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

# Ad-hoc sign with correct identifier (required for Accessibility permissions)
if [ "$ENABLE_CODESIGN" = false ]; then
    echo "🔐 Ad-hoc signing with correct bundle identifier..."
    codesign --force --deep --sign - --identifier "$BUNDLE_ID" Release/XKey.app
    echo "✅ Ad-hoc signed with identifier: $BUNDLE_ID"
fi

# Verify code signature
echo "🔍 Verifying code signature..."
codesign -vvv --deep --strict Release/XKey.app
echo "✅ Code signature verified"

# Display signature info
echo ""
echo "📝 Signature details:"
codesign -dvvv Release/XKey.app 2>&1 | grep -E "(Authority|Identifier|TeamIdentifier|Timestamp)"


# ============================================
# Create DMG with Applications folder symlink
# ============================================
if [ "$ENABLE_DMG" = true ]; then
    echo ""
    echo "💿 Creating DMG installer..."
    
    # Create temporary directory for DMG contents
    DMG_TEMP_DIR=$(mktemp -d)
    DMG_SOURCE_DIR="$DMG_TEMP_DIR/$DMG_VOLUME_NAME"
    mkdir -p "$DMG_SOURCE_DIR"
    
    # Copy app to temp directory
    cp -R "Release/XKey.app" "$DMG_SOURCE_DIR/"
    
    # Create symbolic link to Applications folder
    ln -s /Applications "$DMG_SOURCE_DIR/Applications"
    
    # Remove old DMG if exists
    rm -f "Release/$DMG_NAME"
    
    # Create DMG
    echo "📀 Creating DMG file..."
    hdiutil create \
        -volname "$DMG_VOLUME_NAME" \
        -srcfolder "$DMG_SOURCE_DIR" \
        -ov \
        -format UDZO \
        "Release/$DMG_NAME"
    
    # Sign DMG if code signing is enabled
    if [ "$ENABLE_CODESIGN" = true ]; then
        echo "🔐 Signing DMG..."
        codesign --sign "$DEVELOPER_ID" --timestamp "Release/$DMG_NAME"
        echo "✅ DMG signed"
    fi
    
    # Cleanup temp directory
    rm -rf "$DMG_TEMP_DIR"
    
    echo "✅ DMG created: Release/$DMG_NAME"
fi

# ============================================
# Notarization
# ============================================
if [ "$ENABLE_NOTARIZE" = true ] && [ "$ENABLE_CODESIGN" = true ]; then
    echo ""
    echo "📤 Starting notarization process..."
    
    # Check for required environment variables
    if [ -z "$APPLE_ID" ] || [ -z "$APPLE_APP_PASSWORD" ] || [ -z "$APPLE_TEAM_ID" ]; then
        echo "❌ Notarization requires the following environment variables:"
        echo "   APPLE_ID          - Your Apple ID email"
        echo "   APPLE_APP_PASSWORD - App-specific password"
        echo "   APPLE_TEAM_ID     - Your Apple Developer Team ID"
        echo ""
        echo "   Set these in .env file or export them before running this script."
        echo "   See .env.example for reference."
        exit 1
    fi
    
    # Determine what to notarize (prefer DMG if available)
    if [ "$ENABLE_DMG" = true ] && [ -f "Release/$DMG_NAME" ]; then
        NOTARIZE_TARGET="Release/$DMG_NAME"
        echo "📦 Notarizing DMG: $NOTARIZE_TARGET"
    else
        # Create a zip for notarization if DMG is not available
        echo "📦 Creating zip for notarization..."
        NOTARIZE_TARGET="Release/XKey.zip"
        ditto -c -k --keepParent "Release/XKey.app" "$NOTARIZE_TARGET"
    fi
    
    # Submit for notarization and capture output
    echo "⏳ Submitting to Apple for notarization (this may take several minutes)..."
    NOTARIZE_OUTPUT=$(xcrun notarytool submit "$NOTARIZE_TARGET" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait 2>&1)
    
    echo "$NOTARIZE_OUTPUT"
    
    # Extract submission ID
    SUBMISSION_ID=$(echo "$NOTARIZE_OUTPUT" | grep -E "^\s*id:" | head -1 | awk '{print $2}')
    
    # Check if notarization was successful
    if echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
        echo "✅ Notarization accepted!"
        
        # Staple the notarization ticket
        echo "📎 Stapling notarization ticket..."
        if [ "$ENABLE_DMG" = true ] && [ -f "Release/$DMG_NAME" ]; then
            xcrun stapler staple "Release/$DMG_NAME"
            echo "✅ DMG notarized and stapled"
        fi
        
        # Also staple the app
        xcrun stapler staple "Release/XKey.app"
        echo "✅ App notarized and stapled"
        
        # Clean up zip if we created one
        if [ -f "Release/XKey.zip" ]; then
            rm -f "Release/XKey.zip"
        fi
        
        # Verify notarization
        echo ""
        echo "🔍 Verifying notarization..."
        spctl -a -vvv -t install "Release/XKey.app"
        if [ "$ENABLE_DMG" = true ] && [ -f "Release/$DMG_NAME" ]; then
            spctl -a -vvv -t install "Release/$DMG_NAME"
        fi
        echo "✅ Notarization verified"
    else
        echo ""
        echo "❌ Notarization failed!"
        
        # Fetch detailed log from Apple
        if [ -n "$SUBMISSION_ID" ]; then
            echo ""
            echo "📋 Fetching detailed error log from Apple..."
            echo "   Submission ID: $SUBMISSION_ID"
            echo ""
            xcrun notarytool log "$SUBMISSION_ID" \
                --apple-id "$APPLE_ID" \
                --team-id "$APPLE_TEAM_ID" \
                --password "$APPLE_APP_PASSWORD"
        fi
        
        echo ""
        echo "💡 Common issues:"
        echo "   - Missing hardened runtime (--options=runtime)"
        echo "   - Unsigned nested code or frameworks"
        echo "   - Missing timestamp in signature"
        echo "   - Invalid entitlements"
        exit 1
    fi
fi

# Clear macOS launch services cache
echo ""
echo "🧹 Clearing macOS cache..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -r -domain local -domain system -domain user

echo ""
echo "✅ Build successful!"

echo ""
echo "✅ Done! Release build is ready at:"
echo "   $(pwd)/Release/XKey.app"
if [ "$ENABLE_DMG" = true ]; then
    echo "   $(pwd)/Release/$DMG_NAME"
fi
echo ""
echo "📊 App size:"
du -sh Release/XKey.app
if [ "$ENABLE_DMG" = true ] && [ -f "Release/$DMG_NAME" ]; then
    echo ""
    echo "📀 DMG size:"
    du -sh "Release/$DMG_NAME"
fi
echo ""
echo "🏗️  Architecture:"
lipo -info Release/XKey.app/Contents/MacOS/XKey
echo ""

if [ "$ENABLE_CODESIGN" = true ]; then
    echo "🔐 Code signing: ENABLED"
    echo "   Certificate: $DEVELOPER_ID"
else
    echo "⚠️  Code signing: DISABLED"
fi

if [ "$ENABLE_NOTARIZE" = true ] && [ "$ENABLE_CODESIGN" = true ]; then
    echo "📤 Notarization: COMPLETED"
fi

echo ""
echo "💡 Usage:"
echo "   Default (with code signing + DMG):  ./build_release.sh"
echo "   Without code signing:               ENABLE_CODESIGN=false ./build_release.sh"
echo "   Without DMG:                        ENABLE_DMG=false ./build_release.sh"
echo "   With notarization:                  ENABLE_NOTARIZE=true ./build_release.sh"
echo ""
echo "📝 For notarization, create .env file with:"
echo "   APPLE_ID=your-apple-id@example.com"
echo "   APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx"
echo "   APPLE_TEAM_ID=XXXXXXXXXX"
