#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/TNL.app"
DMG="$DIR/TNL.dmg"

rm -rf "$APP" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Compile universal binary (Intel + Apple Silicon)
swiftc "$DIR/tnl.swift" -o "$APP/Contents/MacOS/tnl" -framework Cocoa \
    -target arm64-apple-macosx12.0 -O
swiftc "$DIR/tnl.swift" -o "$APP/Contents/MacOS/tnl-x86" -framework Cocoa \
    -target x86_64-apple-macosx12.0 -O
lipo -create "$APP/Contents/MacOS/tnl" "$APP/Contents/MacOS/tnl-x86" \
    -output "$APP/Contents/MacOS/tnl-universal"
mv "$APP/Contents/MacOS/tnl-universal" "$APP/Contents/MacOS/tnl"
rm "$APP/Contents/MacOS/tnl-x86"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>TNL</string>
    <key>CFBundleDisplayName</key>
    <string>TNL</string>
    <key>CFBundleIdentifier</key>
    <string>com.dan.tnl</string>
    <key>CFBundleExecutable</key>
    <string>tnl</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
</dict>
</plist>
PLIST

# Ad-hoc code sign with entitlements
codesign --force --deep --sign - --entitlements "$DIR/tnl.entitlements" "$APP"

echo "Built: $APP"

# Create DMG
STAGING="$DIR/.dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "TNL" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "DMG: $DMG"
