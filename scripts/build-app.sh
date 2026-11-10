#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product DesktopPet
bin_dir=$(swift build -c release --show-bin-path)
app_dir="$PWD/build/LocalDesktopPet.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/DesktopPet" "$app_dir/Contents/MacOS/DesktopPet"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>DesktopPet</string>
  <key>CFBundleIdentifier</key><string>local.desktop.pet</string>
  <key>CFBundleName</key><string>小狗的角落</string>
  <key>CFBundleDisplayName</key><string>小狗的角落</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
printf '%s\n' "$app_dir"
