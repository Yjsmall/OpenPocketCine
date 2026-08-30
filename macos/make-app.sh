#!/bin/sh
# Assemble OpenPocketCine.app from the release build (personal/local use only).
# Non-sandboxed on purpose: CoreWLAN associate + SSID read are not App-Store paths.
set -eu
cd "$(dirname "$0")"

swift build -c release

APP="OpenPocketCine.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/OpenPocketCineMac "$APP/Contents/MacOS/OpenPocketCineMac"
cp Resources/*.cube "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>OpenPocketCineMac</string>
    <key>CFBundleIdentifier</key><string>com.opencapture.openpocketcine.macos</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>OpenPocketCine</string>
    <key>CFBundleDisplayName</key><string>OpenPocketCine</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>OpenPocketCine uses Bluetooth to find and pair with your DJI Osmo Pocket and hand off Wi-Fi.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>OpenPocketCine talks to your camera over its own Wi-Fi network to read status and video.</string>
    <key>NSLocationUsageDescription</key>
    <string>Location access lets OpenPocketCine confirm the Mac is on the camera Wi-Fi (OSMO-*).</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Location access lets OpenPocketCine confirm the Mac is on the camera Wi-Fi (OSMO-*).</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key><true/>
    </dict>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
