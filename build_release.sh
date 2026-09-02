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
ENABLE_PROFILE_EMBED=${ENABLE_PROFILE_EMBED:-true}  # Set to false to skip embedding Developer ID provisioning profile
ENABLE_ICLOUD_ENTITLEMENT=${ENABLE_ICLOUD_ENTITLEMENT:-true}  # Trusts XKeyRelease.entitlements by default (declares iCloud KVS: com.apple.developer.ubiquity-kvstore-identifier). iCloud sync IS valid on a notarized Developer ID build, provided the signing cert is the one listed in the embedded Developer ID profile's DeveloperCertificates (otherwise amfid rejects with -413 "No matching profile found" → SIGKILL). Set false only to strip the KVS entitlement from the /tmp expanded copy for a sync-disabled control build.

# Smart defaults: If notarizing, assume it's a full release
if [ "$ENABLE_NOTARIZE" = true ]; then
    # Auto-enable Sparkle signing for notarized releases
    ENABLE_SPARKLE_SIGN=${ENABLE_SPARKLE_SIGN:-true}
    # Auto-enable GitHub release for notarized builds (unless explicitly disabled)
    ENABLE_GITHUB_RELEASE=${ENABLE_GITHUB_RELEASE:-true}
else
    # For development builds, keep conservative defaults
    ENABLE_SPARKLE_SIGN=${ENABLE_SPARKLE_SIGN:-true}
    ENABLE_GITHUB_RELEASE=${ENABLE_GITHUB_RELEASE:-false}
fi

BUNDLE_ID="com.codetay.XKey"
XKEYIM_BUNDLE_ID="com.codetay.inputmethod.XKey"
APP_NAME="XKey"
DMG_NAME="XKey.dmg"
DMG_VOLUME_NAME="XKey"
REPO_URL="https://github.com/xmannv/xkey"
SPARKLE_BIN="/tmp/Sparkle-2.9.0/bin"

# Read version from Version.xcconfig (centralized version management)
XCCONFIG_FILE="$(pwd)/Version.xcconfig"
if [ -f "$XCCONFIG_FILE" ]; then
    CURRENT_VERSION=$(grep "^MARKETING_VERSION" "$XCCONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
    BUILD_NUMBER=$(grep "^CURRENT_PROJECT_VERSION" "$XCCONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
else
    echo "❌ Error: Version.xcconfig not found"
    exit 1
fi


echo "🚀 Building XKey (Release configuration)..."

# Show build mode
if [ "$ENABLE_NOTARIZE" = true ]; then
    echo "📦 Full Release Mode (Notarization enabled)"
    echo "   ✅ Code signing"
    echo "   ✅ Notarization"
    echo "   ✅ Sparkle signing"
    echo "   ✅ XKeyIM bundled in XKey.app"
    [ "$ENABLE_GITHUB_RELEASE" = true ] && echo "   ✅ GitHub Release (auto-create)"
else
    echo "🔨 Development Build Mode"
    [ "$ENABLE_CODESIGN" = true ] && echo "   ✅ Code signing" || echo "   ⚠️  Code signing disabled"
    [ "$ENABLE_SPARKLE_SIGN" = true ] && echo "   ✅ Sparkle signing" || echo "   ⚠️  Sparkle signing disabled"
    [ "$ENABLE_XKEYIM_BUNDLE" = true ] && echo "   ✅ XKeyIM bundled in XKey.app" || echo "   ⏭️  XKeyIM separate build"
    [ "$ENABLE_GITHUB_RELEASE" = true ] && echo "   ✅ GitHub Release (auto-create)" || echo "   ⏭️  Manual release"
fi
echo ""

# Create Release directory
mkdir -p Release

# Provisioning profile resolution + signing-identity derivation helpers.
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
DEVID_PROFILE_NAME="XKey Developer ID Distribution"

# Newest installed provisioning profile whose Name matches DEVID_PROFILE_NAME.
# Xcode's "Download Manual Profiles" saves UUID-named files and an older pretty-named
# file may be stale, so newest-by-mtime wins.
resolve_devid_profile() {
    ls -t "$PROFILE_DIR"/*.provisionprofile 2>/dev/null | while IFS= read -r f; do
        name=$(security cms -D -i "$f" 2>/dev/null | grep -A1 "<key>Name</key>" | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
        [ "$name" = "$DEVID_PROFILE_NAME" ] && echo "$f" && break
    done
}

# SHA-1 of the signing identity to use: the certificate that is BOTH embedded in the
# given profile's DeveloperCertificates AND available in the keychain as a codesigning
# identity (i.e. has a private key). This guarantees the signing cert matches the embedded
# profile, which is exactly what amfid requires for restricted com.apple.developer.*
# entitlements (a mismatch causes -413 "No matching profile found" → SIGKILL at launch).
# Echoes nothing when it cannot determine one — the caller then falls back.
signing_sha_from_profile() {
    local profile="$1"
    [ -f "$profile" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    local profile_shas id_shas psha
    profile_shas=$(security cms -D -i "$profile" 2>/dev/null | python3 -c '
import sys, plistlib, hashlib
try:
    d = plistlib.loads(sys.stdin.buffer.read())
    for c in d.get("DeveloperCertificates", []):
        print(hashlib.sha1(bytes(c)).hexdigest().upper())
except Exception:
    pass') || return 0
    id_shas=$(security find-identity -v -p codesigning | grep -oE "[0-9A-F]{40}")
    for psha in $profile_shas; do
        echo "$id_shas" | grep -q "$psha" && { echo "$psha"; return 0; }
    done
}

# Detect Developer ID if code signing is enabled
if [ "$ENABLE_CODESIGN" = true ]; then
    echo "🔍 Detecting Developer ID certificate..."
    
    # Choose the signing identity by SHA-1, NOT by name: there can be multiple
    # "Developer ID Application: Luong Van Duc (7E6Z9B4F2H)" certs in the keychain and
    # signing by name then fails as "ambiguous". The cert MUST also be the one embedded in
    # the Developer ID provisioning profile's DeveloperCertificates list, otherwise amfid
    # rejects the restricted iCloud KVS entitlement at launch with
    #   Error -413 "No matching profile found"  →  SIGKILL (Code Signature Invalid).
    #
    # Resolution priority (self-healing — survives cert renewal / profile regeneration):
    #   1. CODESIGN_IDENTITY_SHA env override (manual escape hatch)
    #   2. cert derived from the embedded profile ∩ keychain identities (guarantees match)
    #   3. hardcoded fallback (last known-good cert, valid until Dec 2030)
    XKEY_DEVID_PROFILE="$(resolve_devid_profile)"
    DERIVED_SHA="$(signing_sha_from_profile "$XKEY_DEVID_PROFILE")"
    CODESIGN_IDENTITY_SHA=${CODESIGN_IDENTITY_SHA:-${DERIVED_SHA:-76E8032F7A72F9CD503461F7D395B829149742B5}}
    [ -n "$DERIVED_SHA" ] && echo "🔎 Signing cert derived from embedded profile" || echo "🔎 Using fallback/override signing cert (profile derivation unavailable)"

    IDENTITY_LINE=$(security find-identity -v -p codesigning | grep -i "$CODESIGN_IDENTITY_SHA" | head -1)
    if [ -z "$IDENTITY_LINE" ]; then
        echo "⚠️  Pinned signing identity $CODESIGN_IDENTITY_SHA not found in keychain"
        echo "   Available codesigning identities:"
        security find-identity -v -p codesigning
        echo ""
        echo "   Building without code signing..."
        ENABLE_CODESIGN=false
    else
        # codesign --sign accepts the SHA-1 hash and resolves it unambiguously.
        DEVELOPER_ID="$CODESIGN_IDENTITY_SHA"
        DEVELOPER_ID_NAME=$(echo "$IDENTITY_LINE" | sed -E 's/.*"(.*)"/\1/')
        echo "✅ Found: $DEVELOPER_ID_NAME"
        echo "✅ Signing identity (SHA-1): $CODESIGN_IDENTITY_SHA"

        # Extract Team ID from the certificate's friendly name
        TEAM_ID=$(echo "$DEVELOPER_ID_NAME" | sed -E 's/.*\(([A-Z0-9]+)\).*/\1/')
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
    # Build with AD-HOC signing (no provisioning validation), then re-sign below with
    # the Developer ID cert + embedded Developer ID profile (XKEY_DEVID_PROFILE).
    # We CANNOT use automatic signing here: XKeyRelease.entitlements declares the
    # restricted iCloud KVS entitlement (com.apple.developer.ubiquity-kvstore-identifier),
    # and Xcode's auto-managed "Mac Team Provisioning Profile" is not authorized for it,
    # so the automatic-signing pre-check fails. Ad-hoc signing applies the entitlements
    # without any profile check; the real Developer ID signature + the authorized
    # Developer ID profile are applied in the re-sign step further below.
    xcodebuild -project XKey.xcodeproj \
      -scheme XKey \
      -configuration Release \
      -derivedDataPath ./build \
      -arch x86_64 -arch arm64 \
      ONLY_ACTIVE_ARCH=NO \
      PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY="-" \
      PROVISIONING_PROFILE_SPECIFIER="" \
      DEVELOPMENT_TEAM="$TEAM_ID" \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGNING_ALLOWED=YES \
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

# Expand Xcode build variables in entitlements files for codesign re-sign steps.
# codesign does NOT expand $(TeamIdentifierPrefix) or $(CFBundleIdentifier) —
# passing raw .entitlements files with these placeholders produces a literal-string
# entitlement that macOS validates and rejects (SIGKILL / Code Signature Invalid).
XKEY_ENTITLEMENTS_EXPANDED="/tmp/xkey-release-expanded.entitlements"
XKEYIM_ENTITLEMENTS_EXPANDED="/tmp/xkeyim-release-expanded.entitlements"
sed "s/\$(TeamIdentifierPrefix)/${TEAM_ID}./g; s/\$(CFBundleIdentifier)/${BUNDLE_ID}/g" \
    "XKey/XKeyRelease.entitlements" > "$XKEY_ENTITLEMENTS_EXPANDED"
sed "s/\$(TeamIdentifierPrefix)/${TEAM_ID}./g; s/\$(CFBundleIdentifier)/com.codetay.inputmethod.XKey/g" \
    "XKeyIM/XKeyIMRelease.entitlements" > "$XKEYIM_ENTITLEMENTS_EXPANDED" 2>/dev/null || \
    cp "XKeyIM/XKeyIMRelease.entitlements" "$XKEYIM_ENTITLEMENTS_EXPANDED" 2>/dev/null || true

# Optionally strip the iCloud KVS entitlement from XKey entitlements (sync-disabled control build)
if [ "$ENABLE_ICLOUD_ENTITLEMENT" = false ]; then
    echo "⏭️  Stripping iCloud KVS entitlement from release entitlements (sync-disabled build)"
    # Primary key in use. The others are deleted defensively in case they were re-added.
    /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.ubiquity-kvstore-identifier" "$XKEY_ENTITLEMENTS_EXPANDED" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.icloud-services" "$XKEY_ENTITLEMENTS_EXPANDED" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.icloud-container-identifiers" "$XKEY_ENTITLEMENTS_EXPANDED" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.ubiquity-container-identifiers" "$XKEY_ENTITLEMENTS_EXPANDED" 2>/dev/null || true
fi

# Embed the Developer ID Distribution provisioning profile (REQUIRED for iCloud KVS).
# XKeyRelease.entitlements declares the restricted entitlement
# com.apple.developer.ubiquity-kvstore-identifier. amfid validates restricted
# com.apple.developer.* entitlements at runtime against the embedded provisioning profile.
# The profile must satisfy BOTH conditions or the app is SIGKILLed at launch
# ("Code Signature Invalid"):
#   1. It authorizes the entitlement (this profile lists ubiquity-kvstore-identifier=TEAM.*).
#   2. Its DeveloperCertificates list INCLUDES the exact Developer ID cert used to sign.
# Condition (2) is the one that previously failed: the app was signed with a Developer ID
# cert that was NOT in the profile, so amfid returned -413 "No matching profile found".
# That is why the signing identity is pinned by SHA-1 above to the cert this profile carries.
# This is the supported path for iCloud sync OUTSIDE the Mac App Store — NOT the old
# (disproven) "macOS 26 bans iCloud on Developer ID" theory.
# (XKEY_DEVID_PROFILE was already resolved during cert detection above.)
if [ "$ENABLE_CODESIGN" = true ] && [ "$ENABLE_PROFILE_EMBED" = true ]; then
    if [ -n "$XKEY_DEVID_PROFILE" ] && [ -f "$XKEY_DEVID_PROFILE" ]; then
        echo "🔐 Embedding Developer ID Distribution provisioning profile..."
        cp "$XKEY_DEVID_PROFILE" "Release/XKey.app/Contents/embedded.provisionprofile"
        echo "✅ Developer ID profile embedded"
    else
        echo "⚠️  WARNING: Developer ID Distribution profile not found!"
        echo "   Notarized builds without this profile will be rejected by amfid."
        echo "   Create it at: developer.apple.com/account/resources/profiles/add"
        echo "   Name it 'XKey Developer ID Distribution' and install via Xcode."
        # Remove dev profile to avoid cert-type mismatch (dev profile + Dev ID cert)
        rm -f "Release/XKey.app/Contents/embedded.provisionprofile"
    fi
elif [ "$ENABLE_CODESIGN" = true ]; then
    echo "⏭️  Skipping profile embedding (ENABLE_PROFILE_EMBED=false)"
    # Still strip any profile xcodebuild may have inserted to avoid cert-type mismatch
    rm -f "Release/XKey.app/Contents/embedded.provisionprofile"
fi

# Sign Sparkle framework's nested components (IMPORTANT: must be done before signing main app)
if [ "$ENABLE_CODESIGN" = true ] && [ "$ENABLE_SPARKLE_SIGN" = true ]; then
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
        --entitlements "$XKEY_ENTITLEMENTS_EXPANDED" \
        Release/XKey.app
    echo "✅ XKey.app re-signed"
else
    # Ad-hoc sign with correct identifier (required for Accessibility permissions)
    # IMPORTANT: Include entitlements to preserve App Group for data sharing
    echo "🔐 Ad-hoc signing with correct bundle identifier..."
    codesign --force --sign - --identifier "$BUNDLE_ID" --entitlements "$XKEY_ENTITLEMENTS_EXPANDED" Release/XKey.app
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

        # XKey and XKeyIM share one derived-data path (./build). The XKey clean
        # above only clears XKey's objects, so without this XKeyIM reuses stale
        # object files from earlier commits and silently ships an old compile.
        echo "🧹 Cleaning previous XKeyIM build..."
        xcodebuild -project XKey.xcodeproj -scheme XKeyIM -configuration Release -derivedDataPath ./build clean

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
            codesign --force --sign "$DEVELOPER_ID" --timestamp --options=runtime --entitlements "$XKEYIM_ENTITLEMENTS_EXPANDED" "Release/XKeyIM.app"
        else
            echo "🔐 Ad-hoc signing XKeyIM with entitlements..."
            codesign --force --sign - --identifier "$XKEYIM_BUNDLE_ID" --entitlements "$XKEYIM_ENTITLEMENTS_EXPANDED" Release/XKeyIM.app
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
            # IMPORTANT: Must include --entitlements to preserve App Group for data sharing
            echo "🔐 Re-signing XKey.app after embedding XKeyIM..."
            if [ "$ENABLE_CODESIGN" = true ]; then
                codesign --force --sign "$DEVELOPER_ID" --timestamp --options=runtime --entitlements "$XKEY_ENTITLEMENTS_EXPANDED" "Release/XKey.app"
            else
                codesign --force --sign - --identifier "$BUNDLE_ID" --entitlements "$XKEY_ENTITLEMENTS_EXPANDED" "Release/XKey.app"
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
    # NOTE: notarytool may return non-zero exit code on failure,
    # so we temporarily disable set -e to capture output and handle errors ourselves
    echo "⏳ Submitting to Apple for notarization (this may take several minutes)..."
    set +e
    NOTARIZE_OUTPUT=$(xcrun notarytool submit "$NOTARIZE_TARGET" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait 2>&1)
    NOTARIZE_EXIT=$?
    set -e
    
    echo "$NOTARIZE_OUTPUT"
    
    if [ $NOTARIZE_EXIT -ne 0 ] && ! echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
        echo ""
        echo "⚠️  notarytool exited with code $NOTARIZE_EXIT"
        
        # Check for 403 agreement error — no point continuing
        if echo "$NOTARIZE_OUTPUT" | grep -q "HTTP status code: 403"; then
            echo ""
            echo "❌ Apple Developer agreement expired or missing!"
            echo ""
            echo "💡 Fix: Go to https://developer.apple.com/account"
            echo "   and accept the updated agreement, then re-run this script."
            exit 1
        fi
    fi
    
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

# ============================================
# Sparkle Signing (for auto-update)
# ============================================
if [ "$ENABLE_SPARKLE_SIGN" = true ] && [ "$ENABLE_DMG" = true ] && [ -f "Release/$DMG_NAME" ]; then
    echo ""
    echo "🔐 Sparkle Signing for Auto-Update..."
    
    # Check if Sparkle signing tool exists. The directory may exist from a
    # previous failed/partial extraction, so validate the executable itself.
    if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
        echo "📥 Downloading Sparkle tools (v2.9.0)..."
        rm -rf /tmp/Sparkle-2.9.0 /tmp/Sparkle-2.9.0.tar.xz
        curl -fL https://github.com/sparkle-project/Sparkle/releases/download/2.9.0/Sparkle-2.9.0.tar.xz -o /tmp/Sparkle-2.9.0.tar.xz
        mkdir -p /tmp/Sparkle-2.9.0
        (
            cd /tmp/Sparkle-2.9.0
            tar -xf ../Sparkle-2.9.0.tar.xz
        )

        if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
            echo "❌ Error: Sparkle sign_update not found at $SPARKLE_BIN/sign_update"
            echo "   Contents of $SPARKLE_BIN:"
            ls -la "$SPARKLE_BIN" 2>/dev/null || true
            exit 1
        fi
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
    SPARKLE_KEY_FILE=$(mktemp)
    echo "$SPARKLE_PRIVATE_KEY" > "$SPARKLE_KEY_FILE"
    chmod 600 "$SPARKLE_KEY_FILE"
    set +e
    SPARKLE_OUTPUT=$("$SPARKLE_BIN/sign_update" "Release/$DMG_NAME" --ed-key-file "$SPARKLE_KEY_FILE" 2>&1)
    SPARKLE_EXIT=$?
    set -e
    rm -f "$SPARKLE_KEY_FILE"
    
    if [ $SPARKLE_EXIT -ne 0 ]; then
        echo "❌ Error: sign_update failed with exit code $SPARKLE_EXIT"
        echo "   Output:"
        echo "$SPARKLE_OUTPUT"
        exit 1
    fi
    
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

    # Sparkle EdDSA signatures are base64. Reject shell errors or malformed text
    # before they can be uploaded into appcast.xml.
    if ! echo "$SPARKLE_SIGNATURE" | grep -Eq '^[A-Za-z0-9+/=]{80,}$'; then
        echo "❌ Error: Invalid Sparkle signature format"
        echo "   Extracted value: $SPARKLE_SIGNATURE"
        echo "   Full sign_update output:"
        echo "$SPARKLE_OUTPUT"
        exit 1
    fi
    
    echo "✅ DMG signed with Sparkle EdDSA signature"
    echo "   Signature: ${SPARKLE_SIGNATURE:0:50}..."
    
    # Save signature to file for GitHub release upload
    echo "$SPARKLE_SIGNATURE" > "Release/signature.txt"
    echo "✅ Signature saved to: Release/signature.txt"
    echo "   ⚠️  IMPORTANT: Upload this file to GitHub Release along with XKey.dmg"
    
    # Export signature for reference
    export SPARKLE_SIGNATURE
fi


# ============================================
# GitHub Release (Automatic)
# ============================================
if [ "$ENABLE_GITHUB_RELEASE" = true ]; then
    echo ""
    echo "🚀 Creating GitHub Release..."

    # Check if gh CLI is installed
    if ! command -v gh &> /dev/null; then
        echo "❌ Error: GitHub CLI (gh) not found"
        echo "   Install with: brew install gh"
        echo "   Or skip with: ENABLE_GITHUB_RELEASE=false"
        exit 1
    fi

    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        echo "❌ Error: Not authenticated with GitHub"
        echo "   Run: gh auth login"
        echo "   Or skip with: ENABLE_GITHUB_RELEASE=false"
        exit 1
    fi

    # Version already read from Version.xcconfig at the top of the script
    RELEASE_TAG="v$CURRENT_VERSION-$BUILD_NUMBER"

    echo "📋 Release details:"
    echo "   Version: $CURRENT_VERSION"
    echo "   Build: $BUILD_NUMBER"
    echo "   Tag: $RELEASE_TAG"

    # Check if release already exists
    if gh release view "$RELEASE_TAG" &> /dev/null; then
        echo "⚠️  Release $RELEASE_TAG already exists"
        echo "   Options:"
        echo "   1. Delete existing release: gh release delete $RELEASE_TAG"
        echo "   2. Skip auto-release: ENABLE_GITHUB_RELEASE=false"
        echo "   3. Update version in Version.xcconfig"
        exit 1
    fi

    # Check if DMG exists
    if [ ! -f "Release/$DMG_NAME" ]; then
        echo "❌ Error: DMG not found at Release/$DMG_NAME"
        echo "   Enable DMG creation with: ENABLE_DMG=true"
        exit 1
    fi

    # Prepare release notes
    RELEASE_NOTES_FILE="Release/release_notes.md"

    # Check if user provided custom release notes
    if [ -f ".release_notes.md" ]; then
        echo "📝 Using custom release notes from .release_notes.md"
        cp ".release_notes.md" "$RELEASE_NOTES_FILE"
    else
        # Generate release notes from latest commit message
        echo "📝 Generating release notes from latest commit..."

        # Get latest commit message (subject + body)
        COMMIT_SUBJECT=$(git log -1 --pretty=format:"%s")
        COMMIT_BODY=$(git log -1 --pretty=format:"%b")

        # Create release notes header
        echo "## What's New" > "$RELEASE_NOTES_FILE"
        echo "" >> "$RELEASE_NOTES_FILE"

        # Add commit subject as main change
        echo "$COMMIT_SUBJECT" >> "$RELEASE_NOTES_FILE"

        # Add commit body if available (detailed description)
        if [ -n "$COMMIT_BODY" ]; then
            echo "" >> "$RELEASE_NOTES_FILE"
            echo "$COMMIT_BODY" >> "$RELEASE_NOTES_FILE"
        fi
    fi

    # Display release notes
    echo ""
    echo "📄 Release Notes:"
    cat "$RELEASE_NOTES_FILE"
    echo ""

    # Create version.json with version info for appcast generation
    echo "📝 Creating version.json..."
    cat > "Release/version.json" << EOF
{
    "version": "$CURRENT_VERSION",
    "build": "$BUILD_NUMBER",
    "tag": "$RELEASE_TAG"
}
EOF
    echo "✅ version.json created"

    # Create release with assets
    echo "📤 Creating GitHub release..."

    UPLOAD_FILES="Release/$DMG_NAME Release/version.json"

    # Add signature file if available
    if [ -f "Release/signature.txt" ]; then
        UPLOAD_FILES="$UPLOAD_FILES Release/signature.txt"
        echo "   Uploading: $DMG_NAME + version.json + signature.txt"
    else
        echo "   Uploading: $DMG_NAME + version.json"
    fi

    # Create release
    gh release create "$RELEASE_TAG" $UPLOAD_FILES \
        --title "XKey v$CURRENT_VERSION (Build $BUILD_NUMBER)" \
        --notes-file "$RELEASE_NOTES_FILE" \
        --repo "$REPO_URL"

    if [ $? -eq 0 ]; then
        echo "✅ GitHub Release created successfully!"
        echo "   URL: $REPO_URL/releases/tag/$RELEASE_TAG"
        echo ""
        echo "🔄 GitHub Actions will now:"
        echo "   1. Generate appcast.xml from releases"
        echo "   2. Deploy to GitHub Pages"
        echo "   3. Enable auto-update for users"
        echo ""
        echo "   Monitor at: $REPO_URL/actions"
    else
        echo "❌ Failed to create GitHub release"
        exit 1
    fi

    # Clean up
    rm -f "$RELEASE_NOTES_FILE"
    rm -f "Release/version.json"
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

if [ "$ENABLE_GITHUB_RELEASE" = true ]; then
    echo "🚀 GitHub Release: CREATED"
    echo "   Version: $CURRENT_VERSION"
    echo "   Build: $BUILD_NUMBER"
    echo "   Tag: v$CURRENT_VERSION-$BUILD_NUMBER"
    echo "   URL: $REPO_URL/releases/tag/v$CURRENT_VERSION-$BUILD_NUMBER"
fi

echo ""
echo "💡 Usage:"
echo "   Default (with code signing + DMG):    ./build_release.sh"
echo "   Without code signing:                 ENABLE_CODESIGN=false ./build_release.sh"
echo "   Without DMG:                          ENABLE_DMG=false ./build_release.sh"
echo "   Without XKeyIM:                       ENABLE_XKEYIM=false ./build_release.sh"
echo "   Separate XKeyIM build:                ENABLE_XKEYIM_BUNDLE=false ./build_release.sh"
echo "   With notarization (full release):     ENABLE_NOTARIZE=true ./build_release.sh"
echo "   Without Sparkle signing:              ENABLE_SPARKLE_SIGN=false ./build_release.sh"
echo "   With GitHub release:                  ENABLE_GITHUB_RELEASE=true ./build_release.sh"
echo ""
echo "📝 For notarization, create .env file with:"
echo "   APPLE_ID=your-apple-id@example.com"
echo "   APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx"
echo "   APPLE_TEAM_ID=XXXXXXXXXX"
echo ""
echo "🔐 For Sparkle auto-update, add to .env:"
echo "   SPARKLE_PRIVATE_KEY=your-private-key-here"
echo "   (Or it will be retrieved from Keychain automatically)"
if [ "$ENABLE_GITHUB_RELEASE" != true ]; then
    echo ""
    echo "📋 Next steps for manual release:"
    echo "   1. Create GitHub Release (include version.json + signature.txt for auto-update):"
    echo "      # Create version.json first:"
    echo "      echo '{\"version\": \"$CURRENT_VERSION\", \"build\": \"$BUILD_NUMBER\"}' > Release/version.json"
    echo ""
    echo "      gh release create v$CURRENT_VERSION-$BUILD_NUMBER Release/XKey.dmg Release/version.json Release/signature.txt \\"
    echo "         --title \"XKey v$CURRENT_VERSION (Build $BUILD_NUMBER)\" \\"
    echo "         --notes \"Your release notes here\""
    echo ""
    echo "   2. Or enable automatic release:"
    echo "      ENABLE_GITHUB_RELEASE=true ./build_release.sh"
    echo ""
    echo "   3. GitHub Actions will automatically:"
    echo "      - Generate appcast.xml with EdDSA signature"
    echo "      - Deploy to GitHub Pages for Sparkle auto-updates"
    echo "      - Users will receive update notification"
    echo ""
    echo "   ⚠️  IMPORTANT: signature.txt MUST be uploaded for updates to work!"
    echo ""
    echo "   📖 See .github/QUICK_SETUP.md for GitHub Pages setup"
else
    echo ""
    echo "✅ Release automation complete!"
    echo "   Monitor GitHub Actions for appcast generation"
    echo "   📖 See .github/QUICK_SETUP.md for GitHub Pages setup"
fi


