#!/usr/bin/env bash
# Writes what this push needs to $GITHUB_OUTPUT:
#   changed: UI code changed, so take screenshots
#   shots:   which screens to photograph (folded and open), for what changed;
#            a "Screenshots: edit focus" line in the commit message overrides
#   layout:  manifest or file list changed, so check the xtool package builds
# Usage: ci/changes.sh <before-sha> <after-sha> <event-name>
set -euo pipefail
before="$1" after="$2" event="$3"

if [ "$event" != "push" ] || ! git cat-file -e "$before" 2>/dev/null; then
  printf 'changed=true\nshots=pages edit focus focus-controls\nlayout=true\n' >> "$GITHUB_OUTPUT"; exit 0
fi
files=$(git diff --name-only "$before" "$after")
added=$(git diff --name-only --diff-filter=ADR "$before" "$after")
has() { grep -qE "$1" && echo true || echo false; }
{
  echo "changed=$(echo "$files" | has '^(App/|ci/|project\.yml|Package\.swift|Packages/WriterKit/Sources/FocusLayout/)')"
  shots=$(git log -1 --format=%B "$after" | sed -n 's/^Screenshots: *//p' | head -1)
  if [ -z "$shots" ]; then
    on() { echo "$files" | grep -qE "$1"; }
    on 'FocusEditor|FocusLayout/'          && shots="$shots focus focus-controls focus-edges"
    on 'PageEditor|RichText'               && shots="$shots edit mention"
    on 'RootView|WorldEditorApp|ModelsView' && shots="$shots pages edit focus-controls"
    on '^ci/'                              && shots="$shots edit focus"
    shots=$(echo $shots | tr ' ' '\n' | awk '!seen[$0]++' | tr '\n' ' ')
  fi
  echo "shots=${shots:-edit}"
  echo "layout=$( (echo "$files" | grep -E '^(Package\.swift|xtool\.yml)$'; echo "$added" | grep '\.swift$') | has . )"
} >> "$GITHUB_OUTPUT"
cat "$GITHUB_OUTPUT"
