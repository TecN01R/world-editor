#!/usr/bin/env bash
# Launches the simulator build on the Duo simulator (see ci/pick_devices.py)
# and captures Edit and Focus mode with the software keyboard up, folded and,
# when hinge can open it, unfolded. Output: screenshots/jpg/*.jpg
set -euo pipefail

APP="${1:-build/Build/Products/Debug-iphonesimulator/WorldEditor.app}"
BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
OUT=screenshots
mkdir -p "$OUT"

# Show the on-screen keyboard instead of assuming a hardware keyboard.
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false

PAGES="First page.\\nSecond page.\\nThird page, where the caret is."
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
    xcrun simctl io "$UDID" screenshot ${DISPLAY_ID:+--display="$DISPLAY_ID"} "$OUT/$SLUG-$name.png" >/dev/null
    echo "   $name"
  }

  # Displays: the Duo has an outer (lowest id) and inner (highest id) one.
  DISPLAYS=$(xcrun simctl io "$UDID" screenshot "$OUT/probe.png" 2>&1 | sed -nE 's/.*--display=([0-9]+).*/\1/p' | sort -n)
  rm -f "$OUT/probe.png"
  OUTER=$(echo "$DISPLAYS" | head -1); INNER=$(echo "$DISPLAYS" | tail -1)

  # The same four screens folded and open: the pages list, Edit, and Focus
  # while writing and with its controls revealed.
  screens() {
    local p="$1"
    shoot "$p-pages"          -screenshotPages YES
    shoot "$p-edit"           -screenshotRich YES
    shoot "$p-focus"          -screenshotText "$PAGES" -startInFocus YES
    shoot "$p-focus-controls" -screenshotText "$PAGES" -startInFocus YES -focusControls YES
  }

  DISPLAY_ID="$OUTER"
  screens folded
  # Fitting edge cases, only when Focus mode itself changed.
  if [ "${FULL_SHOTS:-true}" = "true" ]; then
    shoot focus-empty -screenshotText EMPTY -startInFocus YES
    shoot focus-g     -screenshotText "g" -startInFocus YES
    shoot focus-long  -screenshotText "$LONG" -startInFocus YES
  fi
  # Open: `hinge` (installed by the workflow) sends the simulator the same
  # hinge event as Device Hub's Open button; simctl has no fold command.
  if command -v hinge >/dev/null && [ "$INNER" != "$OUTER" ]; then
    hinge -d "$UDID" open 2>&1 | sed 's/^/   hinge: /'
    sleep 3
    DISPLAY_ID="$INNER"
    screens open
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
