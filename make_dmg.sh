#!/bin/zsh
# Builds Readscape (Apple Silicon) and packages it into a drag-to-install DMG.
set -e
cd "$(dirname "$0")"
./build.sh
APP=build/Readscape.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/Readscape-${VERSION}-AppleSilicon.dmg"
STAGE=build/dmg-stage

ARCHS=$(lipo -archs "$APP/Contents/MacOS/Readscape")
[[ "$ARCHS" == "arm64" ]] || { echo "Expected arm64-only binary, got: $ARCHS"; exit 1; }

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "Installer/How to Install.txt" "$STAGE/"
hdiutil create -volname "Readscape" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
codesign --force --sign - "$DMG"
rm -rf "$STAGE"
echo "Created $DMG"

# Ship the DMG and the install guide (also inside the DMG) in dist/.
mkdir -p dist
cp "$DMG" dist/
cp "Installer/How to Install.txt" "dist/How to Install.txt"
echo "Copied to dist/: $(basename "$DMG"), How to Install.txt"
