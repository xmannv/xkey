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
ENABLE_XKEYIM=${ENABLE_XKEYIM:-true}  # Set to false to skip XKeyIM build
ENABLE_XKEYIM_BUNDLE=${ENABLE_XKEYIM_BUNDLE:-true}  # Set to false to skip bundling XKeyIM inside XKey.app

# Smart defaults: If notarizing, assume it's a full release
if [ "$ENABLE_NOTARIZE" = true ]; then
    # Auto-enable Sparkle signing for notarized releases
    ENABLE_SPARKLE_SIGN=${ENABLE_SPARKLE_SIGN:-true}
else
    # For development builds, keep conservative defaults
    ENABLE_SPARKLE_SIGN=${ENABLE_SPARKLE_SIGN:-true}
fi

BUNDLE_ID="com.codetay.XKey"
XKEYIM_BUNDLE_ID="com.codetay.inputmethod.XKey"
APP_NAME="XKey"
DMG_NAME="XKey.dmg"
DMG_VOLUME_NAME="XKey"
REPO_URL="https://github.com/xmannv/xkey"
SPARKLE_BIN="/tmp/Sparkle-2.8.1/bin"



echo "🚀 Building XKey (Release configuration)..."

# Show build mode
if [ "$ENABLE_NOTARIZE" = true ]; then
    echo "📦 Full Release Mode (Notarization enabled)"
    echo "   ✅ Code signing"
    echo "   ✅ Notarization"
    echo "   ✅ Sparkle signing"
    echo "   ✅ XKeyIM bundled in XKey.app"
else
    echo "🔨 Development Build Mode"
    [ "$ENABLE_CODESIGN" = true ] && echo "   ✅ Code signing" || echo "   ⚠️  Code signing disabled"
    [ "$ENABLE_SPARKLE_SIGN" = true ] && echo "   ✅ Sparkle signing" || echo "   ⚠️  Sparkle signing disabled"
    [ "$ENABLE_XKEYIM_BUNDLE" = true ] && echo "   ✅ XKeyIM bundled in XKey.app" || echo "   ⏭️  XKeyIM separate build"
fi
echo ""

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
      CODE_SIGN_STYLE=Automatic \
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

# Sign Sparkle framework's nested components (IMPORTANT: must be done before signing main app)
if [ "$ENABLE_CODESIGN" = true ]; then
    echo "🔐 Signing Sparkle framework components..."
    
    SPARKLE_FW="Release/XKey.app/Contents/Frameworks/Sparkle.framework/Versions/B"
    
    # Sign XPC Services first (deepest level)
    if [ -d "$SPARKLE_FW/XPCServices/Installer.xpc" ]; then
        echo "   Signing Installer.xpc..."
        codesign --force --sign "$DEVELOPER_ID" \
            --timestamp \
            --options=runtime \
            "$SPARKLE_FW/XPCServices/Installer.xpc"
        echo "   ✅ Installer.xpc signed"
    fi
    
    if [ -d "$SPARKLE_FW/XPCServices/Downloader.xpc" ]; then
        echo "   Signing Downloader.xpc..."
        codesign --force --sign "$DEVELOPER_ID" \
            --timestamp \
            --options=runtime \
            "$SPARKLE_FW/XPCServices/Downloader.xpc"
        echo "   ✅ Downloader.xpc signed"
    fi
    
    # Sign Updater.app
    if [ -d "$SPARKLE_FW/Updater.app" ]; then
        echo "   Signing Updater.app..."
        codesign --force --sign "$DEVELOPER_ID" \
            --timestamp \
            --options=runtime \
            "$SPARKLE_FW/Updater.app"
        echo "   ✅ Updater.app signed"
    fi
    
    # Sign Autoupdate binary
    if [ -f "$SPARKLE_FW/Autoupdate" ]; then
        echo "   Signing Autoupdate binary..."
        codesign --force --sign "$DEVELOPER_ID" \
            --timestamp \
            --options=runtime \
            "$SPARKLE_FW/Autoupdate"
        echo "   ✅ Autoupdate signed"
    fi
    
    # Finally, sign the entire Sparkle.framework
    if [ -d "Release/XKey.app/Contents/Frameworks/Sparkle.framework" ]; then
        echo "   Signing Sparkle.framework..."
        codesign --force --sign "$DEVELOPER_ID" \
            --timestamp \
            --options=runtime \
            "Release/XKey.app/Contents/Frameworks/Sparkle.framework"
        echo "   ✅ Sparkle.framework signed"
    fi
    
    echo "✅ Sparkle framework components signed"
fi

# Re-sign XKey.app after modifying nested frameworks
if [ "$ENABLE_CODESIGN" = true ]; then
    echo "🔐 Re-signing XKey.app after framework modifications..."
    codesign --force --sign "$DEVELOPER_ID" \
        --timestamp \
        --options=runtime \
        Release/XKey.app
    echo "✅ XKey.app re-signed"
else
    # Ad-hoc sign with correct identifier (required for Accessibility permissions)
    echo "🔐 Ad-hoc signing with correct bundle identifier..."
    codesign --force --sign - --identifier "$BUNDLE_ID" Release/XKey.app
    echo "✅ Ad-hoc signed with identifier: $BUNDLE_ID"
fi

# Verify code signature
echo "🔍 Verifying code signature..."
codesign -vvv --strict Release/XKey.app
echo "✅ Code signature verified"

# Display signature info
echo ""
echo "📝 Signature details:"
codesign -dvvv Release/XKey.app 2>&1 | grep -E "(Authority|Identifier|TeamIdentifier|Timestamp)"


# ============================================
# Build XKeyIM (Input Method Kit)
# ============================================
if [ "$ENABLE_XKEYIM" = true ]; then
    echo ""
    echo "🔨 Building XKeyIM (Input Method)..."
    
    # Check if XKeyIM scheme exists
    if xcodebuild -project XKey.xcodeproj -list 2>/dev/null | grep -q "XKeyIM"; then
        
        if [ "$ENABLE_CODESIGN" = true ]; then
            xcodebuild -project XKey.xcodeproj \
              -scheme XKeyIM \
              -configuration Release \
              -derivedDataPath ./build \
              -arch x86_64 -arch arm64 \
              ONLY_ACTIVE_ARCH=NO \
              PRODUCT_BUNDLE_IDENTIFIER="$XKEYIM_BUNDLE_ID" \
              CODE_SIGN_STYLE=Automatic \
              DEVELOPMENT_TEAM="$TEAM_ID" \
              CODE_SIGNING_REQUIRED=YES \
              CODE_SIGNING_ALLOWED=YES \
              OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
              build
        else
            xcodebuild -project XKey.xcodeproj \
              -scheme XKeyIM \
              -configuration Release \
              -derivedDataPath ./build \
              -arch x86_64 -arch arm64 \
              ONLY_ACTIVE_ARCH=NO \
              PRODUCT_BUNDLE_IDENTIFIER="$XKEYIM_BUNDLE_ID" \
              CODE_SIGN_STYLE=Manual \
              CODE_SIGN_IDENTITY="-" \
              CODE_SIGNING_REQUIRED=NO \
              CODE_SIGNING_ALLOWED=NO \
              CODE_SIGN_ENTITLEMENTS="XKeyIM/XKeyIMRelease.entitlements" \
              PROVISIONING_PROFILE_SPECIFIER="" \
              build
        fi
        
        # Kill running XKeyIM process if it exists
        echo "🔍 Checking for running XKeyIM process..."
        if pgrep -x "XKeyIM" > /dev/null; then
            echo "⚠️  XKeyIM is currently running, killing process..."
            killall XKeyIM 2>/dev/null || true
            echo "✅ XKeyIM process killed"
            # Wait a bit to ensure process is fully terminated
            sleep 1
        else
            echo "✅ No running XKeyIM process found"
        fi
        
        # Copy XKeyIM to Release directory
        echo "📦 Copying XKeyIM.app to Release..."
        rm -rf Release/XKeyIM.app
        cp -R "./build/Build/Products/Release/XKeyIM.app" Release/

        # Ensure menu icon is present
        if [ -f "XKeyIM/MenuIcon.pdf" ]; then
            echo "📎 Adding MenuIcon.pdf to XKeyIM..."
            cp "XKeyIM/MenuIcon.pdf" "Release/XKeyIM.app/Contents/Resources/"
        fi

        # Update display name to "XKey"
        echo "📝 Updating XKeyIM display name..."
        /usr/libexec/PlistBuddy -c "Set :CFBundleName XKey" "Release/XKeyIM.app/Contents/Info.plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName XKey" "Release/XKeyIM.app/Contents/Info.plist" 2>/dev/null || true
        
        # Re-sign after modifying Info.plist
        if [ "$ENABLE_CODESIGN" = true ]; then
            echo "🔐 Re-signing XKeyIM after Info.plist update..."
            codesign --force --sign "$DEVELOPER_ID" --timestamp --options=runtime --entitlements "XKeyIM/XKeyIM.entitlements" "Release/XKeyIM.app"
        else
            echo "🔐 Ad-hoc signing XKeyIM with entitlements..."
            codesign --force --sign - --identifier "$XKEYIM_BUNDLE_ID" --entitlements "XKeyIM/XKeyIM.entitlements" Release/XKeyIM.app
        fi
        
        # Verify signature
        codesign -vvv --strict Release/XKeyIM.app
        echo "✅ XKeyIM built successfully"
        
        # Embed XKeyIM inside XKey.app for easy installation (optional)
        if [ "$ENABLE_XKEYIM_BUNDLE" = true ]; then
            echo "📦 Embedding XKeyIM.app inside XKey.app/Contents/Resources..."
            mkdir -p "Release/XKey.app/Contents/Resources"
            rm -rf "Release/XKey.app/Contents/Resources/XKeyIM.app"
            cp -R "Release/XKeyIM.app" "Release/XKey.app/Contents/Resources/"
            echo "✅ XKeyIM embedded in XKey.app"

            # Re-sign XKey.app after embedding XKeyIM (IMPORTANT: embedding modifies sealed resources)
            echo "🔐 Re-signing XKey.app after embedding XKeyIM..."
            if [ "$ENABLE_CODESIGN" = true ]; then
                codesign --force --sign "$DEVELOPER_ID" --timestamp --options=runtime "Release/XKey.app"
            else
                codesign --force --sign - --identifier "$BUNDLE_ID" "Release/XKey.app"
            fi

            # Verify XKey.app signature after re-signing
            echo "🔍 Verifying XKey.app signature after embedding..."
            codesign -vvv --strict Release/XKey.app
            echo "✅ XKey.app signature verified"
        else
            echo "⏭️  Skipping XKeyIM embedding (ENABLE_XKEYIM_BUNDLE=false)"
        fi

        
        # Auto-install XKeyIM to user's Input Methods
        echo ""
        echo "📲 Installing XKeyIM to ~/Library/Input Methods/..."
        mkdir -p ~/Library/Input\ Methods/
        
        # Kill XKeyIM process again before installing (in case it was restarted)
        if pgrep -x "XKeyIM" > /dev/null; then
            echo "🔄 Killing XKeyIM process before installation..."
            killall XKeyIM 2>/dev/null || true
            sleep 1
        fi
        
        # Copy to Input Methods
        rm -rf ~/Library/Input\ Methods/XKeyIM.app
        cp -R "Release/XKeyIM.app" ~/Library/Input\ Methods/
        echo "✅ XKeyIM installed to ~/Library/Input Methods/"
        echo "   New version will load automatically on next use"

    else
        echo "⚠️  XKeyIM target not found in Xcode project, skipping..."
    fi
fi

# ============================================
# Cleanup build folder
# ============================================
# IMPORTANT: Remove built apps from build folder to prevent LaunchServices
# from finding duplicate versions when opening XKey from XKeyIM menu
echo ""
echo "🧹 Cleaning up build folder..."
rm -rf "./build/Build/Products/Release/XKey.app"
rm -rf "./build/Build/Products/Release/XKeyIM.app"
echo "✅ Build folder cleaned (prevents duplicate app versions)"


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
# Cleanup XKeyIM.app after bundling
# ============================================
if [ "$ENABLE_XKEYIM" = true ] && [ "$ENABLE_XKEYIM_BUNDLE" = true ] && [ -d "Release/XKeyIM.app" ]; then
    echo ""
    echo "🧹 Cleaning up XKeyIM.app (already bundled in XKey.app)..."
    rm -rf "Release/XKeyIM.app"
    echo "✅ XKeyIM.app removed"
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
    fi
fi

# ============================================
# Sparkle Signing (for auto-update)
# ============================================
if [ "$ENABLE_SPARKLE_SIGN" = true ] && [ "$ENABLE_DMG" = true ] && [ -f "Release/$DMG_NAME" ]; then
    echo ""
    echo "🔐 Sparkle Signing for Auto-Update..."
    
    # Check if Sparkle tools exist
    if [ ! -d "$SPARKLE_BIN" ]; then
        echo "📥 Downloading Sparkle tools (v2.8.1)..."
        cd /tmp
        curl -L https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz -o Sparkle-2.8.1.tar.xz
        rm -rf Sparkle-2.8.1
        mkdir Sparkle-2.8.1
        cd Sparkle-2.8.1
        tar -xf ../Sparkle-2.8.1.tar.xz
        cd - > /dev/null
        echo "✅ Sparkle tools downloaded"
    fi
    
    # Check for private key
    if [ -z "$SPARKLE_PRIVATE_KEY" ]; then
        echo "⚠️  SPARKLE_PRIVATE_KEY not found in .env"
        echo "   Attempting to retrieve from Keychain..."
        
        SPARKLE_PRIVATE_KEY=$(security find-generic-password -s "https://sparkle-project.org" -a "ed25519" -w 2>/dev/null || echo "")
        
        if [ -z "$SPARKLE_PRIVATE_KEY" ]; then
            echo "❌ Error: Sparkle private key not found"
            echo ""
            echo "   To generate keys, run:"
            echo "   $SPARKLE_BIN/generate_keys"
            echo ""
            echo "   Then add SPARKLE_PRIVATE_KEY to .env file"
            echo "   Or skip Sparkle signing with: ENABLE_SPARKLE_SIGN=false"
            exit 1
        else
            echo "✅ Retrieved private key from Keychain"
        fi
    fi
    
    # Sign DMG with EdDSA signature
    echo "🔏 Signing DMG with EdDSA key..."
    SPARKLE_OUTPUT=$("$SPARKLE_BIN/sign_update" "Release/$DMG_NAME" --ed-key-file <(echo "$SPARKLE_PRIVATE_KEY") 2>&1)
    
    # Extract signature from output
    # The output might be in different formats:
    # 1. Just the signature: "ud+UXzlYN4y7cIgbyOYZB3Nq1zjCgV0g0p+Xg7LGpcri9+HO+FEHhBPKPNWzPzDjXevVv5vZ0Sfv4372TOdDBA=="
    # 2. XML attribute format: sparkle:edSignature="ud+UXzlYN4y7cIgbyOYZB3Nq1zjCgV0g0p+Xg7LGpcri9+HO+FEHhBPKPNWzPzDjXevVv5vZ0Sfv4372TOdDBA==" length="8298463"
    
    # Try to extract from XML attribute format first
    if echo "$SPARKLE_OUTPUT" | grep -q 'sparkle:edSignature='; then
        SPARKLE_SIGNATURE=$(echo "$SPARKLE_OUTPUT" | grep 'sparkle:edSignature=' | sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/' | tail -1)
    else
        # Fallback: assume it's just the signature (old format)
        SPARKLE_SIGNATURE=$(echo "$SPARKLE_OUTPUT" | grep -v "^$" | tail -1)
    fi
    
    if [ -z "$SPARKLE_SIGNATURE" ]; then
        echo "❌ Error: Failed to generate Sparkle signature"
        echo "   Output from sign_update:"
        echo "$SPARKLE_OUTPUT"
        exit 1
    fi
    
    echo "✅ DMG signed with Sparkle EdDSA signature"
    echo "   Signature: ${SPARKLE_SIGNATURE:0:50}..."
    
    # Export signature for reference
    export SPARKLE_SIGNATURE
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
if [ "$ENABLE_XKEYIM" = true ]; then
    if [ "$ENABLE_XKEYIM_BUNDLE" = true ]; then
        echo "   └── XKeyIM.app embedded in XKey.app/Contents/Resources/"
    elif [ -f "Release/XKeyIM.app" ]; then
        echo "   $(pwd)/Release/XKeyIM.app"
    fi
fi
if [ "$ENABLE_DMG" = true ]; then
    echo "   $(pwd)/Release/$DMG_NAME"
fi

echo ""
echo "📊 App size:"
du -sh Release/XKey.app
if [ "$ENABLE_XKEYIM" = true ] && [ "$ENABLE_XKEYIM_BUNDLE" = false ] && [ -f "Release/XKeyIM.app" ]; then
    du -sh Release/XKeyIM.app
fi
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

if [ "$ENABLE_SPARKLE_SIGN" = true ] && [ -n "$SPARKLE_SIGNATURE" ]; then
    echo "🔐 Sparkle Signing: ENABLED"
    echo "   EdDSA signature generated"
fi

echo ""
echo "💡 Usage:"
echo "   Default (with code signing + DMG):  ./build_release.sh"
echo "   Without code signing:               ENABLE_CODESIGN=false ./build_release.sh"
echo "   Without DMG:                        ENABLE_DMG=false ./build_release.sh"
echo "   Without XKeyIM:                     ENABLE_XKEYIM=false ./build_release.sh"
echo "   Separate XKeyIM build:              ENABLE_XKEYIM_BUNDLE=false ./build_release.sh"
echo "   With notarization:                  ENABLE_NOTARIZE=true ./build_release.sh"
echo "   Without Sparkle signing:            ENABLE_SPARKLE_SIGN=false ./build_release.sh"
echo ""
echo "📝 For notarization, create .env file with:"
echo "   APPLE_ID=your-apple-id@example.com"
echo "   APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx"
echo "   APPLE_TEAM_ID=XXXXXXXXXX"
echo ""
echo "🔐 For Sparkle auto-update, add to .env:"
echo "   SPARKLE_PRIVATE_KEY=your-private-key-here"
echo "   (Or it will be retrieved from Keychain automatically)"
echo ""
echo "📋 Next steps for release:"
CURRENT_VERSION=$(defaults read "$(pwd)/XKey/Info.plist" CFBundleShortVersionString)
echo "   1. Create GitHub Release:"
echo "      gh release create v$CURRENT_VERSION Release/XKey.dmg \\"
echo "         --title \"XKey v$CURRENT_VERSION\" \\"
echo "         --notes \"Your release notes here\""
echo ""
echo "   2. GitHub Actions will automatically:"
echo "      - Update feed for Sparkle auto-updates"
echo "      - Users will receive update notification"
echo ""
echo "   📖 See .github/QUICK_SETUP.md for GitHub Pages setup"


