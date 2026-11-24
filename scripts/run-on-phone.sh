#!/usr/bin/env bash
# Pulls the latest changes, builds, installs and launches the app on the
# connected iPhone. Only changed code is recompiled, so repeat runs are quick.
#
#   scripts/run-on-phone.sh              build, install and launch (wakes the phone)
#   scripts/run-on-phone.sh --no-launch  build and install only: the phone stays
#                                        locked and asleep (Kevin, 2026-11-24: the
#                                        launch asked him to unlock it)
set -euo pipefail
cd "$(dirname "$0")/.."
git pull --ff-only --quiet || echo "(couldn't pull; building what's here)"
scripts/fetch-llama.sh   # llama.cpp's framework, which xtool.yml copies into the app
if [[ "${1:-}" == "--no-launch" ]]; then
    shift
    xtool dev build --ipa "$@"
    exec xtool install xtool/WorldEditor.ipa
fi
exec xtool dev "$@"
