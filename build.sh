#!/bin/bash
# Builds Riftborn.app (native arm64, optimized) from Sources/.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Riftborn.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -wmo -target arm64-apple-macos13 \
  -framework AppKit -framework SpriteKit -framework AVFoundation -framework GameController \
  Sources/*.swift -o "$APP/Contents/MacOS/Riftborn"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Riftborn</string>
  <key>CFBundleIdentifier</key><string>local.riftborn.game</string>
  <key>CFBundleExecutable</key><string>Riftborn</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>GCSupportsControllerUserInteraction</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.action-games</string>
</dict></plist>
EOF
codesign --force --sign - "$APP" 2>/dev/null || true
echo "Built $(pwd)/$APP"
