#!/bin/zsh
# Build BatteryLive.app (universal arm64 + x86_64) from source.
# Usage: ./build.sh            → builds build/BatteryLive.app
#        SIGN_ID="Developer ID Application: NAME (TEAM)" ./build.sh   → also codesigns
set -e
cd "$(dirname "$0")"

APP="build/BatteryLive.app"
rm -rf build; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ Compiling universal binary…"
xcrun swiftc -O -target arm64-apple-macos11  -o build/BL_arm Sources/BatteryLive.swift -framework Cocoa -framework WebKit
xcrun swiftc -O -target x86_64-apple-macos11 -o build/BL_x86 Sources/BatteryLive.swift -framework Cocoa -framework WebKit
lipo -create build/BL_arm build/BL_x86 -output "$APP/Contents/MacOS/BatteryLive"
chmod +x "$APP/Contents/MacOS/BatteryLive"

echo "→ Copying resources…"
cp Resources/chart.py Resources/stats.sh Resources/closesims.sh Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/Resources/"*.sh
rm -f build/BL_arm build/BL_x86

if [ -n "$SIGN_ID" ]; then
  echo "→ Codesigning with: $SIGN_ID"
  xattr -cr "$APP"
  codesign --force --options runtime --timestamp -s "$SIGN_ID" "$APP/Contents/MacOS/BatteryLive"
  codesign --force --options runtime --timestamp -s "$SIGN_ID" "$APP"
  codesign --verify --strict "$APP" && echo "  ✓ signed"
fi

echo "✓ Built: $APP"
echo "  Install: cp -R $APP /Applications/ && open /Applications/BatteryLive.app"
