#!/usr/bin/env bash
# Keeps the app on your iPhone up to date: whenever a new commit lands on main
# and GitHub CI has passed for it, pulls it, builds only what changed and
# installs it on the phone (over Wi-Fi via netmuxd, or USB if plugged in).
#
# setup-fedora.sh installs this as a background service; to run it by hand:
#   scripts/autodeploy.sh
set -uo pipefail
cd "$(dirname "$0")/.."
REPO=TecN01R/world-editor
INTERVAL=${INTERVAL:-60}

log() { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*"; }

# "success", "failure" or "pending" for a commit's CI (public API, no login).
ci_state() {
  curl -fsS "https://api.github.com/repos/$REPO/commits/$1/check-runs" 2>/dev/null | python3 -c '
import json, sys
runs = json.load(sys.stdin).get("check_runs", [])
if not runs or any(r["status"] != "completed" for r in runs): print("pending")
elif all(r["conclusion"] in ("success", "skipped") for r in runs): print("success")
else: print("failure")' 2>/dev/null || echo pending
}

deployed=""
while true; do
  if git fetch --quiet origin main; then
    head=$(git rev-parse origin/main)
    if [ "$head" != "$deployed" ]; then
      case "$(ci_state "$head")" in
        success)
          log "Installing ${head:0:7}: $(git log -1 --format=%s "$head")"
          git merge --ff-only --quiet origin/main
          if timeout 900 xtool dev; then deployed="$head"; log "Installed."
          else log "Install failed (is the phone awake and on the same Wi-Fi?); retrying next round."; fi ;;
        failure) log "Skipping ${head:0:7}: CI failed."; deployed="$head" ;;
        pending) ;;   # wait for CI
      esac
    fi
  fi
  sleep "$INTERVAL"
done
