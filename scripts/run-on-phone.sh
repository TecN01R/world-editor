#!/usr/bin/env bash
# Pulls the latest changes, builds, installs and launches the app on the
# connected iPhone. Only changed code is recompiled, so repeat runs are quick.
set -euo pipefail
cd "$(dirname "$0")/.."
git pull --ff-only --quiet || echo "(couldn't pull; building what's here)"
scripts/fetch-llama.sh   # llama.cpp's framework, which xtool.yml copies into the app
exec xtool dev "$@"
