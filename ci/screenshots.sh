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
[ -s devices.txt ] || python3 ci/pick_devices.py > devices.txt
cat devices.txt

while IFS='|' read -r UDID NAME; do
  [ -n "$UDID" ] || continue
  SLUG="$(echo "$NAME" | tr ' ' '-' | tr -cd '[:alnum:]-')"
  echo "== $NAME ($UDID)"
  xcrun simctl boot "$UDID" || true
  xcrun simctl bootstatus "$UDID" -b
  xcrun simctl ui "$UDID" appearance dark   # dark mode first
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryLevel 100 --cellularBars 4 || true
  xcrun simctl install "$UDID" "$APP"
  # Skip the one-time "slide to type" keyboard tip.
  xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true || true
  # Discover how this Xcode exposes fold control, so unfolded screenshots can follow.
  xcrun simctl help 2>&1 | grep -iE "fold|hinge|posture|display" || echo "   (no fold commands listed in simctl help)"
  xcrun simctl io "$UDID" help 2>&1 | grep -iE "fold|hinge|posture" || true

  shoot() {
    local name="$1"; shift
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
    sleep 5
    # Foldables expose several displays; capture each one that exists.
    local err
    if ! err=$(xcrun simctl io "$UDID" screenshot "$OUT/$SLUG-$name.png" 2>&1 >/dev/null); then
      for d in $(echo "$err" | sed -nE 's/.*--display=([0-9]+).*/\1/p'); do
        xcrun simctl io "$UDID" screenshot --display="$d" "$OUT/$SLUG-display$d-$name.png" >/dev/null
      done
    fi
    echo "   $name"
  }

  shoot page        -screenshotText "First paragraph in page view.\\nSecond one, a little longer so it wraps onto another line."
  shoot focus-empty -screenshotText EMPTY -startInFocus YES
  shoot focus-g     -screenshotText "g" -startInFocus YES
  shoot focus-short -screenshotText "Hi. This" -startInFocus YES
  shoot focus-long  -screenshotText "$LONG" -startInFocus YES
  shoot focus-pages -screenshotText "First page.\\nSecond page.\\nThird page, where the caret is." -startInFocus YES

  xcrun simctl shutdown "$UDID" || true
done < devices.txt

ls -l "$OUT"
