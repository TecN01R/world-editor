#!/usr/bin/env bash
# Copies the latest CI screenshots from the ci-screenshots branch into a
# directory (default /tmp/shots) without touching the working tree.
set -euo pipefail
out="${1:-/tmp/shots}"
git fetch -q origin ci-screenshots
rm -rf "$out" && mkdir -p "$out"
git archive FETCH_HEAD | tar -x -C "$out"
echo "Screenshots of $(cat "$out/SOURCE_COMMIT"):"; ls "$out"/*.jpg
