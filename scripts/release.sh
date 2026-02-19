#!/bin/bash
set -euo pipefail

# ─── Config ───────────────────────────────────────
APP_NAME="HappyKeyTone"
SCHEME="HappyKeyTone"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
SPARKLE_BIN="/Users/studiodog/Projects/projects/Sparkle-2.8.1/bin"
KEYCHAIN_PROFILE="AC_PASSWORD"
EXPORT_OPTIONS="$PROJECT_DIR/scripts/ExportOptions.plist"

# ─── Version ──────────────────────────────────────
VERSION=$(defaults read "$PROJECT_DIR/HappyKeyTone/Info.plist" CFBundleShortVersionString)
BUILD=$(defaults read "$PROJECT_DIR/HappyKeyTone/Info.plist" CFBundleVersion)
echo "📦 Releasing $APP_NAME v$VERSION (build $BUILD)"

# ─── Regenerate Xcode Project ─────────────────────
echo ""
echo "⚙️  Step 0: Regenerate Xcode project..."
(cd "$PROJECT_DIR" && xcodegen generate 2>&1)
echo "✅ Project regenerated"

# ─── Archive ──────────────────────────────────────
echo ""
echo "🔨 Step 1: Archive..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"

xcodebuild archive \
  -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  2>&1 | tail -5

if [ ! -d "$ARCHIVE_PATH" ]; then
  echo "❌ Archive failed"
  exit 1
fi
echo "✅ Archive succeeded"

# ─── Export ───────────────────────────────────────
echo ""
echo "📤 Step 2: Export archive (Developer ID)..."
EXPORT_PATH="$BUILD_DIR/export"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  2>&1 | tail -5

APP_PATH="$EXPORT_PATH/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
  echo "❌ Export failed"
  exit 1
fi
echo "✅ Export succeeded"

# ─── Verify Signing ──────────────────────────────
echo ""
echo "🔏 Step 3: Verify code signing..."
codesign --verify --deep --strict "$APP_PATH" 2>&1
# Check for timestamp
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -i "timestamp"
echo "✅ Code signing valid"

# ─── Notarize App ─────────────────────────────────
echo ""
echo "📮 Step 4: Notarize app..."
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait 2>&1

echo "✅ Notarization complete"

# ─── Staple ───────────────────────────────────────
echo ""
echo "📎 Step 5: Staple notarization ticket..."
xcrun stapler staple "$APP_PATH" 2>&1
echo "✅ Stapled"

# ─── Create DMG ──────────────────────────────────
echo ""
echo "💿 Step 6: Create DMG..."
DMG_PATH="$BUILD_DIR/$APP_NAME-v$VERSION.dmg"

DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH" 2>&1

rm -rf "$DMG_STAGING"
echo "✅ DMG created: $DMG_PATH"

# ─── Notarize DMG ────────────────────────────────
echo ""
echo "📮 Step 7: Notarize DMG..."
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait 2>&1

xcrun stapler staple "$DMG_PATH" 2>&1
echo "✅ DMG notarized and stapled"

# ─── Sparkle Signature ───────────────────────────
echo ""
echo "🔑 Step 8: Generate Sparkle EdDSA signature..."

# Re-create ZIP from stapled app for Sparkle distribution
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

SIGNATURE=$("$SPARKLE_BIN/sign_update" "$ZIP_PATH" 2>&1)
echo "Signature: $SIGNATURE"
echo "✅ Sparkle signature generated"

# ─── Summary ──────────────────────────────────────
FILE_SIZE=$(stat -f%z "$ZIP_PATH")
echo ""
echo "═══════════════════════════════════════════════"
echo "🎉 Release v$VERSION ready!"
echo "═══════════════════════════════════════════════"
echo ""
echo "Artifacts:"
echo "  DMG: $DMG_PATH"
echo "  ZIP: $ZIP_PATH"
echo ""
echo "📝 Next steps:"
echo "  1. Upload DMG to GitHub Releases as v$VERSION"
echo "  2. Update appcast.xml with:"
echo "     - Version: $VERSION"
echo "     - $SIGNATURE"
echo "     - Length: $FILE_SIZE"
echo ""
