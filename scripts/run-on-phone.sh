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
# The private netmuxd (docs/fedora.md) when it runs: the system one loses the phone, and a
# shell without USBMUXD_SOCKET_ADDRESS set reported it unreachable while it was on the Wi-Fi.
if [[ -z "${USBMUXD_SOCKET_ADDRESS:-}" ]] && pgrep -u "$USER" -f "netmuxd .*-p 27099" >/dev/null; then
    export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27099
fi
scripts/fetch-llama.sh   # the companion's engine, llama.cpp's framework, which Package.swift links
scripts/fetch-turbo-fieldfare.sh   # the 26B's engine, on trial in debug builds
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
# The private netmuxd (USBMUXD_SOCKET_ADDRESS=127.0.0.1:27099, docs/fedora.md) loses the
# phone after a while though it's still on the Wi-Fi (2026-11-24, several times): when the
# phone still announces itself on the network, restart that netmuxd once and look again.
revive() {
    [[ "${USBMUXD_SOCKET_ADDRESS:-}" == "127.0.0.1:27099" ]] || return 1
    timeout 8 avahi-browse -tp _apple-mobdev2._tcp 2>/dev/null | grep -q . || return 1
    echo "The phone is on the network but netmuxd lost it: restarting netmuxd." >&2
    # Only this one: other projects' sessions run their own netmuxd on other ports (2026-11-25).
    for pid in $(pgrep -u "$USER" -x netmuxd); do
        tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q -- '-p 27099' && kill "$pid"
    done
    sleep 1
    nohup setsid /usr/local/bin/netmuxd --disable-usb --disable-unix --host 127.0.0.1 -p 27099 \
        --plist-storage /var/lib/lockdown >/dev/null 2>&1 </dev/null &
    sleep 6
    reachable
}
# Signs and installs with xtool-duo where it's installed: a patched xtool that asks Apple for the
# increased-memory-limit entitlement on a free team, which stock xtool drops (the app then gets
# about 3.4 GB on the Duo instead of 5.8; Kevin, 2026-11-25). Stock xtool otherwise.
installer=$(command -v xtool-duo || echo xtool)
if [[ "${1:-}" == "--no-launch" ]]; then
    shift
    xtool dev build --ipa "$@"
    reachable || revive || unreachable   # built, ready for when it is
    exec timeout 600 "$installer" install xtool/WorldEditor.ipa
fi
reachable || revive || unreachable
exec timeout 900 "$installer" dev "$@"   # never waits for a phone that drops out for good
