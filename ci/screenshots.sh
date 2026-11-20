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

  shoot() {
    local name="$1"; shift
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "$@" >/dev/null
    sleep 3   # launch, layout and keyboard animation
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

# Print each screenshot into the job log as base64 JPEG between markers, so the
# Claude session can read them from the log (it can't reach artifact storage).
# Inner display shots are skipped while the simulator boots folded (all black).
for f in "$OUT"/*.png; do
  case "$f" in *display3*) continue;; esac
  name="$(basename "${f%.png}")"
  sips -s format jpeg -s formatOptions 72 -Z 1400 "$f" --out "/tmp/$name.jpg" >/dev/null
  echo "=====BEGIN-SCREENSHOT $name.jpg"
  base64 -b 76 -i "/tmp/$name.jpg"
  echo "=====END-SCREENSHOT"
done
