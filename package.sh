#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mode=${1:-public}
case "$mode" in
  public) app="build/public/Antigravity Boot.app" ;;
  demo) app="build/Antigravity Boot.app" ;;
  *) echo "Usage: ./package.sh [public|demo]" >&2; exit 2 ;;
esac
./build.sh "$mode"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/image" dist
ditto "$app" "$tmp/image/Antigravity Boot.app"
ln -s /Applications "$tmp/image/Applications"
volume="Antigravity Boot"
hdiutil create -quiet -format UDZO -fs HFS+ -volname "$volume" -srcfolder "$tmp/image" "$tmp/installer.dmg"
hdiutil verify -quiet "$tmp/installer.dmg"
mv "$tmp/installer.dmg" "dist/Antigravity-Boot-$version-$mode-universal.dmg"
