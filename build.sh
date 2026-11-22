#!/bin/zsh
# Builds Readscape.app (Apple Silicon, macOS 14+) into build/.
# Needs Xcode installed (the macOS 27 SDK implements SwiftUI's @State as a macro, which ships with Xcode only).
set -e
if [[ -z "$DEVELOPER_DIR" && -d /Applications/Xcode.app ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
cd "$(dirname "$0")"
APP=build/Readscape.app
VERSION=1.0
rm -rf "$APP" build/Readscape.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 Sources/*.swift -o "$APP/Contents/MacOS/Readscape"

swift Tools/make_icon.swift build/Readscape.iconset
iconutil -c icns build/Readscape.iconset -o "$APP/Contents/Resources/Readscape.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Readscape</string>
  <key>CFBundleDisplayName</key><string>Readscape</string>
  <key>CFBundleIdentifier</key><string>app.readscape.mac</string>
  <key>CFBundleExecutable</key><string>Readscape</string>
  <key>CFBundleIconFile</key><string>Readscape</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Readscape — a visual reading intelligence app</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"
