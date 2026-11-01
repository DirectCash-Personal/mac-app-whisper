#!/bin/bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════╗
# ║  SuperWhisper Release Script                                 ║
# ║  Usage: ./scripts/release.sh 1.1.0                          ║
# ╚══════════════════════════════════════════════════════════════╝

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get script directory (where release.sh lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Validate arguments ───────────────────────────────────────
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo -e "${RED}❌ Usage: ./scripts/release.sh <version>${NC}"
    echo -e "   Example: ./scripts/release.sh 1.1.0"
    exit 1
fi

# Validate version format (semver)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}❌ Invalid version format. Use semver: X.Y.Z${NC}"
    exit 1
fi

echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  🚀 SuperWhisper Release v${VERSION}                  ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"

# ─── Paths ─────────────────────────────────────────────────────
APP_NAME="SuperWhisper"
SCHEME="SuperWhisper"
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/Release/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/${DMG_NAME}"
APPCAST_PATH="$PROJECT_DIR/appcast.xml"

# ─── Step 1: Update version in project.yml and Info.plist ──────
echo -e "\n${YELLOW}📝 Step 1: Updating version to ${VERSION}...${NC}"

# Update project.yml
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"${VERSION}\"/" "$PROJECT_DIR/project.yml"
echo -e "   ✅ project.yml updated"

# Update Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PROJECT_DIR/SuperWhisper/Info.plist"
echo -e "   ✅ Info.plist updated"

# Increment build number (use timestamp for uniqueness)
BUILD_NUMBER=$(date +%Y%m%d%H%M)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$PROJECT_DIR/SuperWhisper/Info.plist"
sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"${BUILD_NUMBER}\"/" "$PROJECT_DIR/project.yml"
echo -e "   ✅ Build number: ${BUILD_NUMBER}"

# ─── Step 2: Clean and build Release ───────────────────────────
echo -e "\n${YELLOW}🔨 Step 2: Building Release...${NC}"
cd "$PROJECT_DIR"

# Clean previous build
rm -rf "$BUILD_DIR"

# Build release (without code signing — we sign manually after to avoid Sparkle framework conflicts)
xcodebuild \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -destination "platform=macOS" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR/Release" \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    clean build 2>&1 | tail -5

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ Build failed — ${APP_PATH} not found${NC}"
    exit 1
fi

# ─── Signing: Developer ID Application, inside-out, hardened runtime, secure timestamp ───
# Gatekeeper only opens a downloaded (quarantined) app signed with Developer ID AND notarized; Apple Development
# makes macOS refuse every DMG downloaded from the browser. Sparkle's helpers are signed one by one (no --deep).
echo -e "   ${YELLOW}🔐 Signing with Developer ID Application...${NC}"
xattr -rc "$APP_PATH" 2>/dev/null
DEVELOPER_ID_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}' || true)
if [ -z "$DEVELOPER_ID_IDENTITY" ]; then
    echo -e "${RED}❌ 'Developer ID Application' certificate not found in the Keychain (only the Account Holder can create it).${NC}"
    exit 1
fi
SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/B"
sign_with_developer_id() {
    codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID_IDENTITY" "$@"
}
sign_with_developer_id "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
sign_with_developer_id --preserve-metadata=entitlements "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
sign_with_developer_id "$SPARKLE_VERSION_DIR/Autoupdate"
sign_with_developer_id "$SPARKLE_VERSION_DIR/Updater.app"
sign_with_developer_id "$SPARKLE_FRAMEWORK"
sign_with_developer_id --entitlements "$PROJECT_DIR/SuperWhisper/SuperWhisper.entitlements" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo -e "   ${GREEN}✅ Signed with Developer ID${NC}"

# ─── Notarization of the app, then staple it (works offline after install) ───
# Credential: App Store Connect API key (~/.config/superwhisper/credencial-app-store-connect: ASC_ID_DA_CHAVE,
# ASC_ID_DO_EMISSOR, ASC_CAMINHO_DA_CHAVE_P8).
NOTARY_CREDENTIAL_FILE="$HOME/.config/superwhisper/credencial-app-store-connect"
if [ ! -f "$NOTARY_CREDENTIAL_FILE" ]; then
    echo -e "${RED}❌ Notarization credential not found: $NOTARY_CREDENTIAL_FILE${NC}"
    exit 1
fi
# shellcheck disable=SC1090
. "$NOTARY_CREDENTIAL_FILE"
notarize_and_wait() {
    xcrun notarytool submit "$1" --key "$ASC_CAMINHO_DA_CHAVE_P8" --key-id "$ASC_ID_DA_CHAVE" \
        --issuer "$ASC_ID_DO_EMISSOR" --wait --output-format json > "$BUILD_DIR/notarizacao-$(basename "$1").json"
    if ! grep -q '"status" *: *"Accepted"' "$BUILD_DIR/notarizacao-$(basename "$1").json"; then
        echo -e "${RED}❌ Notarization rejected for $(basename "$1"): see $BUILD_DIR/notarizacao-$(basename "$1").json and 'xcrun notarytool log'${NC}"
        exit 1
    fi
}
echo -e "   ${YELLOW}📮 Notarizing the app...${NC}"
APP_ZIP_FOR_NOTARIZATION="$BUILD_DIR/${APP_NAME}-notarizacao.zip"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP_FOR_NOTARIZATION"
notarize_and_wait "$APP_ZIP_FOR_NOTARIZATION"
xcrun stapler staple "$APP_PATH"
rm -f "$APP_ZIP_FOR_NOTARIZATION"
echo -e "   ${GREEN}✅ App notarized and stapled${NC}"

# ─── Step 3: Create DMG ───────────────────────────────────────
echo -e "\n${YELLOW}📦 Step 3: Creating DMG...${NC}"

# Create a temporary folder for DMG contents
DMG_TEMP="$BUILD_DIR/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy .app to temp folder
cp -R "$APP_PATH" "$DMG_TEMP/"

# Create symlink to Applications folder
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$DMG_PATH" > /dev/null 2>&1

rm -rf "$DMG_TEMP"

if [ ! -f "$DMG_PATH" ]; then
    echo -e "${RED}❌ DMG creation failed${NC}"
    exit 1
fi

# The DMG itself is signed, notarized and stapled too; the appcast signature (Step 4) is generated only after the
# staple, because stapling changes the file and an earlier edSignature would make Sparkle refuse the update.
codesign --force --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$DMG_PATH"
echo -e "   ${YELLOW}📮 Notarizing the DMG...${NC}"
notarize_and_wait "$DMG_PATH"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH"
spctl -a -vvv -t exec "$APP_PATH"
echo -e "   ${GREEN}✅ DMG signed, notarized and stapled${NC}"

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1 | xargs)
echo -e "   ${GREEN}✅ DMG created: ${DMG_NAME} (${DMG_SIZE})${NC}"

# ─── Step 4: Generate appcast.xml ──────────────────────────────
echo -e "\n${YELLOW}📡 Step 4: Generating appcast.xml...${NC}"

# Check if Sparkle's generate_appcast is available
SPARKLE_BIN=""
# Check common locations
# EdDSA key lives in the Keychain under the "superwhisper" account (backup: ~/.config/superwhisper/sparkle-eddsa-chave-privada).
# The original key was lost in 2026: 1.0.x installs cannot verify updates and need one manual install of 1.1.2+.
SPARKLE_KEY_ACCOUNT="superwhisper"
if [ -x "$HOME/.local/share/superwhisper-sparkle/bin/generate_appcast" ]; then
    SPARKLE_BIN="$HOME/.local/share/superwhisper-sparkle/bin/generate_appcast"
elif command -v generate_appcast &> /dev/null; then
    SPARKLE_BIN="generate_appcast"
elif [ -f "$BUILD_DIR/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" ]; then
    SPARKLE_BIN="$BUILD_DIR/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
elif [ -f "$HOME/Library/Developer/Xcode/DerivedData/SuperWhisper-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" ]; then
    SPARKLE_BIN=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/artifacts/sparkle/Sparkle/bin/generate_appcast" -type f 2>/dev/null | head -1)
fi

if [ -n "$SPARKLE_BIN" ] && [ -f "$SPARKLE_BIN" ]; then
    # generate_appcast will scan the build directory for DMGs and create/update appcast.xml
    # It uses the EdDSA key from the Keychain or environment variable
    "$SPARKLE_BIN" --account "$SPARKLE_KEY_ACCOUNT" "$BUILD_DIR" --download-url-prefix "https://github.com/DirectCash-Personal/mac-app-whisper/releases/download/v${VERSION}/" -o "$APPCAST_PATH"
    echo -e "   ${GREEN}✅ appcast.xml generated with Sparkle signatures${NC}"
else
    echo -e "   ${YELLOW}⚠️  generate_appcast not found. Generating appcast manually...${NC}"
    
    # Get file size and date
    FILE_SIZE=$(stat -f%z "$DMG_PATH")
    PUB_DATE=$(date -R)
    
    # Generate a basic appcast.xml (without EdDSA signature)
    cat > "$APPCAST_PATH" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>SuperWhisper Updates</title>
        <description>Most recent changes with links to updates.</description>
        <language>en</language>
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="https://github.com/DirectCash-Personal/mac-app-whisper/releases/download/v${VERSION}/${DMG_NAME}"
                length="${FILE_SIZE}"
                type="application/octet-stream" />
        </item>
    </channel>
</rss>
EOF
    echo -e "   ${GREEN}✅ appcast.xml created (manual mode — no EdDSA signature)${NC}"
    echo -e "   ${YELLOW}💡 For signed updates, run: generate_appcast ${BUILD_DIR}${NC}"
fi

# ─── Step 5: Summary ──────────────────────────────────────────
echo -e "\n${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ Release v${VERSION} ready!                        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📁 Files:${NC}"
echo -e "   DMG:     ${DMG_PATH}"
echo -e "   Appcast: ${APPCAST_PATH}"
echo ""
echo -e "${CYAN}📋 Next steps:${NC}"
echo -e "   1. ${YELLOW}git add -A && git commit -m \"release: v${VERSION}\"${NC}"
echo -e "   2. ${YELLOW}git tag v${VERSION}${NC}"
echo -e "   3. ${YELLOW}git push origin main --tags${NC}"
echo -e "   4. Go to: ${YELLOW}https://github.com/DirectCash-Personal/mac-app-whisper/releases/new${NC}"
echo -e "   5. Select tag ${YELLOW}v${VERSION}${NC}"
echo -e "   6. Upload ${YELLOW}${DMG_PATH}${NC}"
echo -e "   7. Publish release 🎉"
echo ""
echo -e "${GREEN}Users will be notified on their next app launch! ✨${NC}"
