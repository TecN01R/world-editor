#!/usr/bin/env bash
# Writes what this push needs to $GITHUB_OUTPUT:
#   changed: UI code changed, so take screenshots
#   focus:   Focus mode changed, so also take the fitting edge-case shots
#   layout:  manifest or file list changed, so check the xtool package builds
# Usage: ci/changes.sh <before-sha> <after-sha> <event-name>
set -euo pipefail
before="$1" after="$2" event="$3"

if [ "$event" != "push" ] || ! git cat-file -e "$before" 2>/dev/null; then
  printf 'changed=true\nfocus=true\nlayout=true\n' >> "$GITHUB_OUTPUT"; exit 0
fi
files=$(git diff --name-only "$before" "$after")
added=$(git diff --name-only --diff-filter=ADR "$before" "$after")
has() { grep -qE "$1" && echo true || echo false; }
{
  echo "changed=$(echo "$files" | has '^(App/|ci/|project\.yml|Package\.swift|Packages/WriterKit/Sources/FocusLayout/)')"
  echo "focus=$(echo "$files" | has '(Focus|TextKitMeasurer|ci/screenshots)')"
  echo "layout=$( (echo "$files" | grep -E '^(Package\.swift|xtool\.yml)$'; echo "$added" | grep '\.swift$') | has . )"
} >> "$GITHUB_OUTPUT"
cat "$GITHUB_OUTPUT"
