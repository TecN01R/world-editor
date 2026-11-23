#!/usr/bin/env bash
# Puts llama.cpp's prebuilt Apple framework (pinned build, checksum verified) in
# Vendor/llama.xcframework, and its device framework in Vendor/Frameworks, which
# xtool.yml copies into the app: the same build as AnyLanguageModel's llama.swift
# (keep the two in step).
set -euo pipefail
build=b12359
sum=25eebedbbdef004c2da2bf4fd8daa77324d6db91bbff24d19d9da0942cbfd1b9
cd "$(dirname "$0")/.."
[ -d Vendor/llama.xcframework ] && [ "$(cat Vendor/llama.build 2>/dev/null)" = "$build" ] && [ -d Vendor/Frameworks/llama.framework ] && exit 0
cache="${XDG_CACHE_HOME:-$HOME/.cache}/llama-xcframework"
zip="$cache/llama-$build-xcframework.zip"
mkdir -p "$cache" Vendor
[ -f "$zip" ] || curl -fsSL --retry 3 -o "$zip" "https://github.com/ggml-org/llama.cpp/releases/download/$build/llama-$build-xcframework.zip"
if command -v sha256sum >/dev/null; then echo "$sum  $zip" | sha256sum -c --quiet
else echo "$sum  $zip" | shasum -a 256 -c >/dev/null; fi   # macOS (CI's Macs)
rm -rf Vendor/llama.xcframework "$cache/x" && unzip -q "$zip" -d "$cache/x"
mv "$cache/x/build-apple/llama.xcframework" Vendor/ && echo "$build" > Vendor/llama.build
# The device framework, in a Frameworks folder that xtool.yml copies into the app
# (a real copy: xtool copies symlinks as links).
rm -rf Vendor/Frameworks && mkdir -p Vendor/Frameworks
cp -R Vendor/llama.xcframework/ios-arm64/llama.framework Vendor/Frameworks/
