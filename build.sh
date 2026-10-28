#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c release --cache-path .build/cache --config-path .build/config --security-path .build/security --disable-sandbox
APP="${CHATLEDGER_APP_OUTPUT:-$PWD/dist/轻随.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ChatLedger "$APP/Contents/MacOS/ChatLedger"
cp Assets/FloatingOrb.png "$APP/Contents/Resources/FloatingOrb.png"
xcrun swift scripts/MakeIcon.swift .build/AppIcon.iconset "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ChatLedger</string>
<key>CFBundleIdentifier</key><string>local.binbin.chatledger</string>
<key>CFBundleName</key><string>轻随</string>
<key>CFBundleDisplayName</key><string>轻随</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.7.0</string>
<key>CFBundleVersion</key><string>20</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
if [[ -n "${CHATLEDGER_BUNDLE_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $CHATLEDGER_BUNDLE_ID" "$APP/Contents/Info.plist"
fi
codesign --force --sign - "$APP"
printf '已构建：%s\n' "$APP"
