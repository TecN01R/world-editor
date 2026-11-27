#!/usr/bin/env bash
# Puts llama.cpp's prebuilt Apple framework (MIT; a pinned release, its checksum checked) in
# Vendor/llama.xcframework, for Package.swift and project.yml.
set -euo pipefail
build=b12633
sum=d0b199082096fc63c875ef55c4675de09b3d42fa25a0b8d2dba736938c9c9bc6
cd "$(dirname "$0")/.."
[ -d Vendor/llama.xcframework ] && [ "$(cat Vendor/llama.build 2>/dev/null)" = "$build" ] && exit 0
cache="${XDG_CACHE_HOME:-$HOME/.cache}/llama-xcframework"
zip="$cache/llama-$build-xcframework.zip"
mkdir -p "$cache" Vendor
[ -f "$zip" ] || curl -fsSL --retry 3 -o "$zip" "https://github.com/ggml-org/llama.cpp/releases/download/$build/llama-$build-xcframework.zip"
# Compared by hand: macOS's sha256sum (CI's Macs) has no --quiet, and older ones have only shasum.
actual=$( (sha256sum "$zip" 2>/dev/null || shasum -a 256 "$zip") | cut -d' ' -f1)
[ "$actual" = "$sum" ] || { echo "llama.cpp's framework failed its checksum: $zip" >&2; exit 1; }
rm -rf Vendor/llama.xcframework "$cache/x" && unzip -q "$zip" -d "$cache/x"
mv "$cache/x/build-apple/llama.xcframework" Vendor/ && rm -rf "$cache/x" && echo "$build" > Vendor/llama.build
