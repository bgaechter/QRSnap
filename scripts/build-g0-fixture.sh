#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture_app="$PWD/.build/G0Fixture.app"
mkdir -p "$fixture_app/Contents/MacOS" "$fixture_app/Contents/Resources" .build/clang-module-cache
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path "$PWD/.build/clang-module-cache" scripts/g0-fixture.swift \
    -o "$fixture_app/Contents/MacOS/G0Fixture"
cp QRSnapTests/Fixtures/https.png "$fixture_app/Contents/Resources/https.png"
cat > "$fixture_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.benny.QRSnap.G0Fixture</string>
<key>CFBundleExecutable</key><string>G0Fixture</string>
<key>CFBundleName</key><string>G0 Synthetic Fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - --options runtime --entitlements QRSnap/App/QRSnap.entitlements "$fixture_app"
codesign --verify --strict "$fixture_app"
echo "Built $fixture_app. It displays synthetic pixels only; it never captures the screen."
