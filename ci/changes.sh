#!/usr/bin/env bash
# Writes what this push needs to $GITHUB_OUTPUT:
#   changed: the app, or what it is built from, changed: build it and render its scenes
#   tier:    core (the quick set in ci/scenes.txt) or full (all of them: a manual run, or
#            the design system, ci/ or the manifests changed)
#   only:    just these scenes: a "Screenshots: edit focus" line in the commit message
#   layout:  manifest or file list changed, so check the xtool package layout builds
# Usage: ci/changes.sh <before-sha> <after-sha> <event-name>
set -euo pipefail
before="$1" after="$2" event="$3"
out() { echo "$1" >> "$GITHUB_OUTPUT"; }

only=$(git log -1 --format=%B "$after" | sed -n 's/^Screenshots: *//p' | head -1)
out "only=$only"
if [ "$event" = pull_request ]; then
  # A pull request only runs the Linux tests: it can't publish to ci-screenshots.
  out "changed=false"; out "tier=core"; out "layout=false"
elif [ "$event" != push ] || ! git cat-file -e "$before" 2>/dev/null; then
  out "changed=true"; out "tier=full"; out "layout=true"
else
  files=$(git diff --name-only "$before" "$after")
  added=$(git diff --name-only --diff-filter=ADR "$before" "$after")
  has() { grep -qE "$1" && echo true || echo false; }
  out "changed=$(echo "$files" | has '^(App/|ci/|\.github/workflows/|project\.yml|Package\.swift|Packages/WriterKit/(Sources/|Package\.swift))')"
  full=$(echo "$files" | has '^(App/Sources/Design/|Packages/WriterKit/Sources/DesignTokens/|ci/|\.github/workflows/|project\.yml|Package\.swift)')
  out "tier=$([ "$full" = true ] && echo full || echo core)"
  out "layout=$( (echo "$files" | grep -E '^(Package\.swift|xtool\.yml)$'; echo "$added" | grep '\.swift$') | has . )"
fi
cat "$GITHUB_OUTPUT"
