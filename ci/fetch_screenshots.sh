#!/usr/bin/env bash
# Copies the latest CI screenshots from the ci-screenshots branch into a directory
# (default build/shots/current, git-ignored), keeping the set that was there as
# <directory>/../previous for comparison. Never touches the working tree.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-build/shots/current}"
git fetch -q origin ci-screenshots
if [ -d "$out" ]; then rm -rf "$(dirname "$out")/previous" && mv "$out" "$(dirname "$out")/previous"; fi
mkdir -p "$out"
git archive FETCH_HEAD | tar -x -C "$out"
echo "Screenshots of $(cat "$out/SOURCE_COMMIT") in $out:"
find "$out" -name '*.jpg' | sort | sed "s|^$out/||" | tr '\n' ' '; echo
[ -s "$out/missing.txt" ] && { echo "MISSING:"; cat "$out/missing.txt"; } || true
