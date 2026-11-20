#!/usr/bin/env bash
# Launches the simulator build on a few iPhone simulators (including any
# foldable "Duo" device the installed runtimes offer) and captures page view
# and Focus mode with the software keyboard up. Output: screenshots/*.png
set -euo pipefail

APP="${1:-build/Build/Products/Debug-iphonesimulator/WorldEditor.app}"
BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
OUT=screenshots
mkdir -p "$OUT"

# Show the on-screen keyboard instead of assuming a hardware keyboard.
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false

LONG="Hi. This is exactly what I wanted. Can we keep this design while vertically centering?"
python3 ci/pick_devices.py > devices.txt
cat devices.txt

while IFS='|' read -r UDID NAME; do
  [ -n "$UDID" ] || continue
  SLUG="$(echo "$NAME" | tr ' ' '-' | tr -cd '[:alnum:]-')"
  echo "== $NAME ($UDID)"
  xcrun simctl boot "$UDID" || true
  xcrun simctl bootstatus "$UDID" -b
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryLevel 100 --cellularBars 4 || true
  xcrun simctl install "$UDID" "$APP"

  shoot() {
    local name="$1"; shift
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
    sleep 5
    xcrun simctl io "$UDID" screenshot "$OUT/$SLUG-$name.png" >/dev/null
    echo "   $name"
  }

  shoot page        -screenshotText "First paragraph in page view.\\nSecond one, a little longer so it wraps onto another line."
  shoot focus-empty -screenshotText EMPTY -startInFocus YES
  shoot focus-g     -screenshotText "g" -startInFocus YES
  shoot focus-short -screenshotText "Hi. This" -startInFocus YES
  shoot focus-long  -screenshotText "$LONG" -startInFocus YES

  xcrun simctl shutdown "$UDID" || true
done < devices.txt

ls -l "$OUT"
