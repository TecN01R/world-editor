#!/usr/bin/env bash
# One-time setup on Fedora: installs xtool and what it needs, then runs
# xtool's own setup (Apple ID sign-in + Xcode SDK import).
# Safe to re-run; finished steps are skipped.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
case ":$PATH:" in *":$BIN:"*) ;; *) export PATH="$BIN:$PATH"
  grep -q 'local/bin' "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc";;
esac

say "Installing system packages (needs your password)"
# usbmuxd + libimobiledevice: talk to the iPhone. fuse-libs: run AppImages.
sudo dnf install -y usbmuxd libimobiledevice-utils fuse-libs curl git unzip

say "Swift toolchain"
if ! command -v swift >/dev/null 2>&1; then
  tmp=$(mktemp -d)
  curl -fsSL "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz" -o "$tmp/swiftly.tar.gz"
  tar -xzf "$tmp/swiftly.tar.gz" -C "$tmp"
  "$tmp/swiftly" init --assume-yes --quiet-shell-followup
  # shellcheck disable=SC1091
  . "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
fi
swift --version

say "xtool"
if ! command -v xtool >/dev/null 2>&1; then
  curl -fL "https://github.com/xtool-org/xtool/releases/latest/download/xtool-$(uname -m).AppImage" -o "$BIN/xtool"
  chmod +x "$BIN/xtool"
fi
xtool --help >/dev/null && echo "xtool installed"

say "Apple ID and Xcode SDK"
cat <<'EOF'
xtool needs Apple's iOS SDK, which only ships inside Xcode.
  1. On any device, sign in at https://developer.apple.com/download/all/
     with your Apple ID and download the latest Xcode .xip (about 3 GB).
  2. Put it on this machine (e.g. ~/Downloads).
xtool will now ask you to sign in with your Apple ID and for the .xip path.
EOF
xtool setup

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
sudo dnf install -y python3-pip avahi nss-mdns
pip install --user --quiet pymobiledevice3
pymobiledevice3 lockdown wifi-connections --state on || echo "(couldn't enable Wi-Fi connections; installs will need the cable)"
if ! command -v netmuxd >/dev/null 2>&1; then
  url=$(curl -fsSL https://api.github.com/repos/jkcoxson/netmuxd/releases/latest \
        | python3 -c 'import json,sys,platform; a=platform.machine(); print(next(x["browser_download_url"] for x in json.load(sys.stdin)["assets"] if a in x["name"] and "linux" in x["name"].lower()))')
  curl -fL "$url" -o "$BIN/netmuxd" && chmod +x "$BIN/netmuxd"
fi
sudo systemctl enable --now avahi-daemon
# netmuxd and usbmuxd share one socket. Plugging the phone in starts usbmuxd
# (udev); netmuxd keeps retrying and takes over again once it exits.
sudo tee /etc/systemd/system/netmuxd.service >/dev/null <<UNIT
[Unit]
Description=netmuxd (iPhone over Wi-Fi)
After=network-online.target avahi-daemon.service
[Service]
ExecStart=$BIN/netmuxd
Restart=always
RestartSec=15
[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now netmuxd
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
sudo loginctl enable-linger "$USER"

say "Done"
echo "New builds now install on the iPhone by themselves once CI passes."
echo "To install right now by hand:  scripts/run-on-phone.sh"
