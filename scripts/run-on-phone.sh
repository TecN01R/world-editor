#!/usr/bin/env bash
# Pulls the latest changes, builds, installs and launches the app on the
# connected iPhone. Only changed code is recompiled, so repeat runs are quick.
set -euo pipefail
cd "$(dirname "$0")/.."
git pull --ff-only --quiet || echo "(couldn't pull; building what's here)"
exec xtool dev "$@"
