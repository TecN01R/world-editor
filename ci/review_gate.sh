#!/usr/bin/env bash
# The gate before an install (docs/design-review.md): what goes on Kevin's phone has been
# rendered by CI and reviewed.
#
#   ci/review_gate.sh pass "what was reviewed"   record that the screens CI rendered for
#                                                this code passed review
#   ci/review_gate.sh check                      succeed only if this code is what was
#                                                rendered and reviewed
#
# "This code" is everything a screen is built from (PATHS below), as committed: the same
# files reviewed are the files installed, whatever else has been committed since.
# The record is .git/ui-review: local, never pushed. scripts/run-on-phone.sh runs `check`;
# its --unreviewed flag skips it, for a build Kevin asked for as it is.
set -euo pipefail
cd "$(dirname "$0")/.."

PATHS=(App Packages/WriterKit/Sources Package.swift project.yml)
RECORD=.git/ui-review

# One hash for the committed state of everything a screen is built from, at a commit.
built() { git ls-tree "$1" -- "${PATHS[@]}" | git hash-object --stdin; }

# The commit CI last rendered, and whether any shot was missing; fails if it can't tell.
rendered() {
  git fetch -q origin ci-screenshots 2>/dev/null || { echo "can't fetch ci-screenshots" >&2; return 1; }
  RENDERED=$(git show FETCH_HEAD:SOURCE_COMMIT 2>/dev/null | tr -d '[:space:]') || true
  [ -n "${RENDERED:-}" ] && git cat-file -e "$RENDERED^{commit}" 2>/dev/null \
    || { echo "ci-screenshots names no commit this clone has" >&2; return 1; }
  MISSING=$(git show FETCH_HEAD:missing.txt 2>/dev/null | grep -c . || true)
}

problems() {
  local now; now=$(built HEAD)
  if ! git diff --quiet HEAD -- "${PATHS[@]}"; then
    echo "uncommitted changes to the app: commit and push them, so CI renders what will be installed"
  fi
  if rendered; then
    [ "$(built "$RENDERED")" = "$now" ] || echo "CI's screenshots are of ${RENDERED:0:7}, whose app code differs from HEAD's: wait for CI, then ci/fetch_screenshots.sh"
    [ "$MISSING" -eq 0 ] || echo "$MISSING shots are missing from CI's set (missing.txt)"
  else
    echo "couldn't read CI's screenshots"
  fi
  if [ "${1:-}" = recorded ]; then
    [ -f "$RECORD" ] && [ "$(sed -n 1p "$RECORD")" = "$now" ] \
      || echo "no review recorded for this code: review the screenshots (docs/design-review.md), then ci/review_gate.sh pass \"…\""
  fi
}

case "${1:-}" in
  pass)
    found=$(problems)
    if [ -n "$found" ]; then echo "Can't record a pass:"; echo "$found" | sed 's/^/  - /'; exit 1; fi
    { built HEAD; git rev-parse HEAD; date -u +%Y-%m-%dT%H:%M:%SZ; echo "${2:-}"; } > "$RECORD"
    echo "Recorded: $(git rev-parse --short HEAD) reviewed${2:+ ($2)}."
    ;;
  check)
    found=$(problems recorded)
    if [ -n "$found" ]; then echo "Not installing:"; echo "$found" | sed 's/^/  - /'; exit 1; fi
    echo "Reviewed: $(sed -n 4p "$RECORD") ($(sed -n 3p "$RECORD"))."
    ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
