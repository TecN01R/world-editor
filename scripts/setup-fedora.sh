#!/usr/bin/env bash
# One-time setup on Fedora: installs xtool and what it needs, then runs
# xtool's own setup (Apple ID sign-in + Xcode SDK import).
# Safe to re-run; finished steps are skipped.
set -euo pipefail

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

say "Done"
echo "From the repository folder, run:  scripts/run-on-phone.sh"
