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

  # Every screen, for one posture and appearance (prefix names them).
  screens() {
    local p="$1"
    shoot "$p-pages"          -screenshotPages YES
    shoot "$p-models"         -screenshotPages YES -screenshotModels YES
    shoot "$p-edit"           -screenshotRich YES
    shoot "$p-edit-new"       -screenshotNewPage YES
    shoot "$p-focus"          -screenshotText "$PAGES" -startInFocus YES
    shoot "$p-focus-controls" -screenshotText "$PAGES" -startInFocus YES -focusControls YES
    shoot "$p-focus-rich"     -screenshotRich YES -startInFocus YES
    shoot "$p-focus-empty"    -screenshotText EMPTY -startInFocus YES
    shoot "$p-focus-g"        -screenshotText "g" -startInFocus YES
    shoot "$p-focus-long"     -screenshotText "$LONG" -startInFocus YES
  }

  # Displays: the Duo has an outer (lowest id) and inner (highest id) one.
  DISPLAYS=$(xcrun simctl io "$UDID" screenshot "$OUT/probe.png" 2>&1 | sed -nE 's/.*--display=([0-9]+).*/\1/p' | sort -n)
  rm -f "$OUT/probe.png"
  OUTER=$(echo "$DISPLAYS" | head -1); INNER=$(echo "$DISPLAYS" | tail -1)
  # `hinge` (installed by the workflow) sends the simulator the same hinge
  # event as Device Hub's pose buttons; simctl has no fold command.
  pose() { command -v hinge >/dev/null && hinge -d "$UDID" "$@" 2>&1 | sed 's/^/   hinge: /'; sleep 3; }

  if [ "${GALLERY:-false}" = "true" ]; then
    # Everything: each screen folded, open (landscape and portrait) and half
    # open like a book, in dark and light.
    for look in dark light; do
      xcrun simctl ui "$UDID" appearance "$look"
      pose close;  DISPLAY_ID="$OUTER"; screens "$look-folded"
      pose open;   DISPLAY_ID="$INNER"
      pose orient landscape-left; screens "$look-open-landscape"
      pose orient portrait;       screens "$look-open-portrait"
      pose half;                  screens "$look-book"
      pose orient landscape-left
    done
  else
    DISPLAY_ID="$OUTER"
    shoot edit           -screenshotRich YES
    shoot pages          -screenshotPages YES
    shoot focus-pages    -screenshotText "$PAGES" -startInFocus YES
    shoot focus-controls -screenshotText "$PAGES" -startInFocus YES -focusControls YES
    # Fitting edge cases, only when Focus mode itself changed.
    if [ "${FULL_SHOTS:-true}" = "true" ]; then
      shoot focus-empty -screenshotText EMPTY -startInFocus YES
      shoot focus-g     -screenshotText "g" -startInFocus YES
      shoot focus-short -screenshotText "Hi. This" -startInFocus YES
      shoot focus-long  -screenshotText "$LONG" -startInFocus YES
    fi
    if command -v hinge >/dev/null && [ "$INNER" != "$OUTER" ]; then
      pose open; DISPLAY_ID="$INNER"
      shoot unfolded-edit       -screenshotRich YES
      shoot unfolded-focus-long -screenshotText "$LONG" -startInFocus YES
    fi
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
