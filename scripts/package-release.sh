#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
architecture="$(uname -m)"
release_root="${CHATLEDGER_RELEASE_OUTPUT:-$PWD/dist/release}"
app="$release_root/轻随.app"
mkdir -p "$release_root"
CHATLEDGER_APP_OUTPUT="$app" CHATLEDGER_BUNDLE_ID=local.binbin.chatledger zsh build.sh
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
codesign --verify --deep --strict "$app"
stage="$(mktemp -d "$PWD/.build/dmg-stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/轻随.app"
ln -s /Applications "$stage/Applications"
cp docs/安装说明.txt "$stage/安装说明.txt"
artifact="Qingsui-$version-macOS-$architecture"
hdiutil create -volname "轻随 $version" -srcfolder "$stage" -ov -format UDZO "$release_root/$artifact.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$release_root/$artifact.zip"
(cd "$release_root" && shasum -a 256 "$artifact.dmg" "$artifact.zip" > SHA256SUMS.txt)
printf '安装包已生成：%s\n' "$release_root/$artifact.dmg"
