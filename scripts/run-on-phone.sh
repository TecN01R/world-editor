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
# Stops at once when the phone can't be reached (not on this network, not plugged
# in): xtool would otherwise wait for it indefinitely (Kevin, 2026-11-24, away from home).
reachable() {
    command -v pymobiledevice3 >/dev/null || return 0   # can't tell: let xtool try
    local devices
    if ! devices=$(timeout 15 pymobiledevice3 usbmux list 2>/dev/null); then
        echo "Can't reach the usbmux daemon (netmuxd down? USBMUXD_SOCKET_ADDRESS=${USBMUXD_SOCKET_ADDRESS:-default})." >&2
        exit 2
    fi
    devices=$(tr -d '[:space:]' <<<"$devices")
    [[ -n "$devices" && "$devices" != "[]" ]]
}
unreachable() {
    echo "The iPhone isn't reachable (not on this network or plugged in), so nothing was installed." >&2
    exit 2
}
if [[ "${1:-}" == "--no-launch" ]]; then
    shift
    xtool dev build --ipa "$@"
    reachable || unreachable   # built, ready for when it is
    exec timeout 600 xtool install xtool/WorldEditor.ipa
fi
reachable || unreachable
exec timeout 900 xtool dev "$@"   # never waits for a phone that drops out for good
