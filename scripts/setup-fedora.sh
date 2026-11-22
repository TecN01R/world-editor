#!/usr/bin/env bash
# One-time setup on Fedora: installs xtool and what it needs, then runs
# xtool's own setup (Apple ID sign-in + Xcode SDK import).
# Safe to re-run; finished steps are skipped.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
# Installs only the packages that are missing, so a re-run doesn't ask for
# your password (or fingerprint) when there's nothing to do.
install_packages() {
  local missing=()
  for p in "$@"; do rpm -q "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if [ ${#missing[@]} -gt 0 ]; then sudo dnf install -y "${missing[@]}"; else echo "Already installed."; fi
}
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
case ":$PATH:" in *":$BIN:"*) ;; *) export PATH="$BIN:$PATH"
  grep -q 'local/bin' "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc";;
esac

say "System packages"
# usbmuxd + libimobiledevice: talk to the iPhone. fuse-libs: run AppImages.
install_packages usbmuxd libimobiledevice-utils fuse-libs curl git unzip
# What swift.org's toolchains need to compile and link.
install_packages binutils gcc libcurl-devel libedit-devel libicu-devel sqlite-devel libuuid-devel libxml2-devel python3 python3-devel

say "xtool"
# Our build of xtool, with the fix for Apple ID sign-in codes never arriving
# (ci/xtool-2fa.patch); replaces any other xtool. Refetched each run.
curl -fL --retry 5 "https://github.com/TecN01R/world-editor/releases/download/xtool-patched/xtool-$(uname -m).AppImage" -o "$BIN/xtool.new"
chmod +x "$BIN/xtool.new" && mv -f "$BIN/xtool.new" "$BIN/xtool"
xtool --help >/dev/null && echo "xtool installed"

say "Xcode SDK"
# Apple's iOS SDK only ships inside Xcode's .xip. The script finds it under
# your home folder; only if there's none does it ask (with Tab completion).
if xtool sdk status | grep -q "is installed"; then
  echo "Already installed."
else
  xip=$(find "$HOME" -maxdepth 3 -iname 'Xcode*27.1*.xip' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
  if [ -z "$xip" ]; then
    echo "Download Xcode 27.1's .xip (about 3 GB) from https://developer.apple.com/download/all/"
    echo "(sign in with your Apple ID). Not 27.2: only 27.1 has the iPhone Duo SDK."
    read -e -r -p "Path to the .xip (Tab completes): " xip
    xip="${xip/#\~/$HOME}"
  fi
  echo "Using $xip"
  xtool sdk install "$xip"
fi

say "Swift toolchain"
# The compiler must match the Swift that built the iOS SDK (Xcode 27.1:
# Swift 6.4), so the version is read from the SDK itself and a new Xcode
# brings its Swift along. Toolchains come from swift.org via swiftly, as its
# RHEL 9 (UBI 9) builds: they run on any newer Fedora and get every release,
# while swift.org's Fedora builds stopped at Fedora 39 and Swift 6.2.
# Downloads (about 1 GB) are retried; a re-run carries on from an earlier one.
SWIFTLY_HOME="${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}"
interface=$(ls "$HOME"/.swiftpm/swift-sdks/darwin.artifactbundle/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk/usr/lib/swift/Swift.swiftmodule/arm64e-apple-ios.swiftinterface 2>/dev/null | tail -1)
want=$(sed -n 's/^\/\/ swift-compiler-version: Apple Swift version \([0-9]*\.[0-9]*\).*/\1/p' "$interface" 2>/dev/null | head -1)
want=${want:-6.4}
echo "The iOS SDK needs Swift $want."
# An earlier setup used swiftly's Fedora 39 builds; start swiftly over on UBI 9.
if [ -d "$SWIFTLY_HOME" ] && ! grep -q '"ubi9"' "$SWIFTLY_HOME/config.json" 2>/dev/null; then
  rm -rf "$SWIFTLY_HOME"
fi
if [ ! -f "$SWIFTLY_HOME/env.sh" ]; then
  tmp=$(mktemp -d)
  curl -fsSL --retry 5 "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz" -o "$tmp/swiftly.tar.gz"
  tar -xzf "$tmp/swiftly.tar.gz" -C "$tmp"
  "$tmp/swiftly" init --assume-yes --quiet-shell-followup --skip-install --platform ubi9 \
    || "$tmp/swiftly" init --assume-yes --quiet-shell-followup --platform ubi9 || true
fi
# shellcheck disable=SC1091
. "$SWIFTLY_HOME/env.sh"
for attempt in 1 2 3 4 5; do
  swift --version 2>/dev/null | grep -q "Swift version $want" && break
  [ "$attempt" = 1 ] || { echo "Download failed; retrying ($attempt of 5)…"; sleep 10; }
  swiftly install "$want" --use --assume-yes || true
  hash -r
done
swift --version

say "Apple ID"
echo "Sign in with the Apple ID that signs the app (one without Advanced Data Protection)."
# XTOOL_DEBUG_GSA prints Apple's answers during the 2FA step ([gsa] lines).
XTOOL_DEBUG_GSA=1 xtool setup

say "Pair your iPhone"
echo "Plug the iPhone in with a cable, unlock it, and tap Trust when asked."
read -r -p "Press Return when it's plugged in and unlocked… " _
idevicepair pair || true
xtool devices || true

say "Wireless installs"
# iOS only offers a paired iPhone over Wi-Fi once "Wi-Fi connections" is on
# for that pairing; pymobiledevice3 sets it (iTunes' "Show this iPhone when
# on Wi-Fi"). netmuxd then finds the phone on the network and stands in for
# usbmuxd, so xtool reaches it without a cable.
install_packages python3-pip avahi nss-mdns
pip install --user --quiet pymobiledevice3
pymobiledevice3 lockdown wifi-connections on || echo "(couldn't enable Wi-Fi connections; installs will need the cable)"
# It lives in /usr/local/bin because SELinux won't let a system service run a
# program from your home folder (it fails with "Permission denied").
NETMUXD=/usr/local/bin/netmuxd
rm -f "$BIN/netmuxd"   # where earlier versions of this script put it
# Releases are .tar.gz archives; an earlier version of this script installed
# the archive itself, so replace anything that isn't a program (ELF).
if ! head -c 4 "$NETMUXD" 2>/dev/null | grep -q ELF; then
  tmp=$(mktemp -d)
  curl -fL --retry 5 "https://github.com/jkcoxson/netmuxd/releases/latest/download/netmuxd-$(uname -m)-unknown-linux-gnu.tar.gz" \
    | tar -xz -C "$tmp" netmuxd
  sudo install -m 755 "$tmp/netmuxd" "$NETMUXD" && sudo restorecon "$NETMUXD"
  rm -rf "$tmp"
  sudo systemctl try-restart netmuxd
fi
systemctl is-enabled --quiet avahi-daemon && systemctl is-active --quiet avahi-daemon \
  || sudo systemctl enable --now avahi-daemon
# netmuxd and usbmuxd share one socket. Plugging the phone in starts usbmuxd
# (udev); netmuxd keeps retrying and takes over again once it exits.
unit=$(cat <<UNIT
[Unit]
Description=netmuxd (iPhone over Wi-Fi)
After=network-online.target avahi-daemon.service
[Service]
ExecStart=$NETMUXD
Restart=always
RestartSec=15
[Install]
WantedBy=multi-user.target
UNIT
)
if [ "$unit" != "$(cat /etc/systemd/system/netmuxd.service 2>/dev/null)" ]; then
  echo "$unit" | sudo tee /etc/systemd/system/netmuxd.service >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl restart netmuxd
fi
systemctl is-enabled --quiet netmuxd && systemctl is-active --quiet netmuxd \
  || sudo systemctl enable --now netmuxd
xtool devices || true

say "Automatic updates"
# Installs every commit that passes CI, from the background, even when you're
# not logged in (lingering). Logs: journalctl --user -u world-editor-autodeploy -f
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/world-editor-autodeploy.service" <<UNIT
[Unit]
Description=Install new World Editor builds on the iPhone
After=network-online.target
[Service]
ExecStart=$REPO_DIR/scripts/autodeploy.sh
Environment=PATH=$BIN:${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/bin:/usr/local/bin:/usr/bin:/bin
Restart=always
[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now world-editor-autodeploy
[ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" = yes ] || sudo loginctl enable-linger "$USER"

say "Done"
echo "New builds now install on the iPhone by themselves once CI passes."
echo "To install right now by hand:  scripts/run-on-phone.sh"
