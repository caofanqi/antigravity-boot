#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mode=${1:-auto}
if [[ "$mode" == auto ]]; then
  if [[ -d Media/Presets ]]; then mode=demo; else mode=public; fi
fi
case "$mode" in
  public|demo) ;;
  *) echo "Usage: ./build.sh [public|demo]" >&2; exit 2 ;;
esac
out="build/Antigravity Boot.app"
if [[ "$mode" == public ]]; then out="build/public/Antigravity Boot.app"; fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
app="$tmp/Antigravity Boot.app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
for arch in arm64 x86_64; do
  xcrun swiftc -O -target "${arch}-apple-macos13.0" -module-cache-path "${TMPDIR:-/tmp}/antigravity-boot-swift-cache" main.swift -o "$tmp/Boot-$arch"
done
xcrun lipo -create "$tmp/Boot-arm64" "$tmp/Boot-x86_64" -output "$contents/MacOS/Boot"
cp Info.plist "$contents/"
cp Boot.icns LICENSE "$contents/Resources/"
if [[ "$mode" == demo ]]; then
  for name in gemini-classic gemini-watercolor gemini-neon gemini-switch-team; do
    cp "Media/Presets/$name.mp4" "$contents/Resources/"
  done
else
  cp Media/orbit.mp4 "$contents/Resources/"
fi
codesign --force --sign - "$app"
codesign --verify --strict --all-architectures "$app"
mkdir -p "$out"
rsync -a --delete "$app/" "$out/"
codesign --verify --strict --all-architectures "$out"
