#!/usr/bin/env bash
# Launches the simulator build on a few iPhone simulators (including any
# foldable "Duo" device the installed runtimes offer) and captures page view
# and Focus mode with the software keyboard up. Output: screenshots/jpg/*.jpg
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
  DISPLAY_ID=""
  SLUG="$(echo "$NAME" | tr ' ' '-' | tr -cd '[:alnum:]-')"
  echo "== $NAME ($UDID)"
  xcrun simctl boot "$UDID" || true
  xcrun simctl bootstatus "$UDID" -b
  xcrun simctl ui "$UDID" appearance dark   # dark mode first
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryLevel 100 --cellularBars 4 || true
  xcrun simctl install "$UDID" "$APP"
  # Skip the one-time "slide to type" keyboard tip.
  xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true || true

  shoot() {
    local name="$1"; shift
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "$@" >/dev/null
    sleep 3   # launch, layout and keyboard animation
    # Foldables expose several displays. Only the first (the outer screen)
    # is captured: the simulator boots folded, so the inner one is black.
    if [ -z "${DISPLAY_ID:-}" ] && ! err=$(xcrun simctl io "$UDID" screenshot "$OUT/$SLUG-$name.png" 2>&1 >/dev/null); then
      DISPLAY_ID=$(echo "$err" | sed -nE 's/.*--display=([0-9]+).*/\1/p' | sort -n | head -1)
    fi
    if [ -n "${DISPLAY_ID:-}" ]; then
      xcrun simctl io "$UDID" screenshot --display="$DISPLAY_ID" "$OUT/$SLUG-display$DISPLAY_ID-$name.png" >/dev/null
    fi
    echo "   $name"
  }

  shoot page        -screenshotText "First paragraph in page view.\\nSecond one, a little longer so it wraps onto another line."
  shoot focus-pages -screenshotText "First page.\\nSecond page.\\nThird page, where the caret is." -startInFocus YES
  # Fitting edge cases, only when Focus mode itself changed.
  if [ "${FULL_SHOTS:-true}" = "true" ]; then
    shoot focus-empty -screenshotText EMPTY -startInFocus YES
    shoot focus-g     -screenshotText "g" -startInFocus YES
    shoot focus-short -screenshotText "Hi. This" -startInFocus YES
    shoot focus-long  -screenshotText "$LONG" -startInFocus YES
  fi
done < devices.txt

ls -l "$OUT"

# Leaving the simulator running makes the runner's cleanup take ~45 s.
pkill -9 -f CoreSimulator || true

# JPEGs for the ci-screenshots branch (the workflow publishes $OUT/jpg).
mkdir -p "$OUT/jpg"
for f in "$OUT"/*.png; do
  sips -s format jpeg -s formatOptions 72 -Z 1400 "$f" --out "$OUT/jpg/$(basename "${f%.png}").jpg" >/dev/null
done
ls "$OUT/jpg"
