#!/usr/bin/env bash
# Renders the app's scenes (ci/scenes.txt) on the Duo simulator in one pose and saves, for
# each, a screenshot and the screen's accessibility tree (what ci/check_ui.py reads: every
# control's label, kind and frame).
#
#   ci/screenshots.sh <WorldEditor.app> <closed|open>
#
#   TIER=core|full    which scenes (default full); core is the quick set
#   ONLY="a b c"      only these scenes, whatever their tier
#
# Output: shots/<pose>/<scene>[-<variant>].png and .json, and shots/<pose>/expected.txt
# (every shot that should exist, so a missing one is noticed).
#
# A shot is taken when the screen has stopped changing, not after a fixed wait: on a busy
# runner the app can take longer than any fixed wait to draw its first frame, and the shot
# was then of the black launch screen (2026-11-27: five of eight).
set -euo pipefail

APP="${1:?the built app}"
POSE="${2:?closed or open}"
TIER="${TIER:-full}"
ONLY="${ONLY:-}"
BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
OUT="shots/$POSE"
mkdir -p "$OUT"
: > "$OUT/expected.txt"

# Show the on-screen keyboard instead of assuming a hardware keyboard.
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false

[ -s devices.txt ] || python3 ci/pick_devices.py > devices.txt
IFS='|' read -r UDID NAME < devices.txt
echo "== $NAME ($UDID), $POSE, tier $TIER${ONLY:+, only: $ONLY}"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance dark   # as the app, which is dark only
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryLevel 100 --cellularBars 4 || true
xcrun simctl install "$UDID" "$APP"
# Skip the one-time "slide to type" keyboard tip.
xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true || true

# Displays: the Duo has an outer (lowest id) and an inner (highest id) one. Asking for one
# screenshot of a device with two fails, listing them.
DISPLAYS=$( (xcrun simctl io "$UDID" screenshot "$OUT/probe.png" 2>&1 || true) | sed -nE 's/.*--display=([0-9]+).*/\1/p' | sort -n)
rm -f "$OUT/probe.png"
OUTER=$(echo "$DISPLAYS" | head -1); INNER=$(echo "$DISPLAYS" | tail -1)
DISPLAY_ID="$OUTER"
if [ "$POSE" = open ]; then
  # `hinge` (installed by the workflow) unfolds the simulator; simctl has no fold command.
  command -v hinge >/dev/null || { echo "no hinge: can't unfold"; exit 1; }
  [ -n "$INNER" ] && [ "$INNER" != "$OUTER" ] || { echo "no inner display on $NAME"; exit 1; }
  hinge -d "$UDID" open 2>&1 | sed 's/^/   hinge: /'
  sleep 3
  DISPLAY_ID="$INNER"
fi

# The screen's accessibility tree, as JSON with its keys in order: axe writes them in no
# fixed order, so two dumps of the same screen differed byte for byte. Folded, axe can
# first see the Duo's displays mid-change ("inconsistent screen layout. Try again."), so
# it is asked again; what it said when it failed is kept in axe-errors.txt.
tree() {
  local tries=0
  until axe describe-ui --udid "$UDID" 2> "$OUT/axe.err" \
        | python3 -c 'import json, sys; json.dump(json.load(sys.stdin), sys.stdout, sort_keys=True, indent=1)' > "$1" 2>/dev/null \
        && [ -s "$1" ]; do
    if (( ++tries >= ${2:-3} )); then
      { echo "== $1"; cat "$OUT/axe.err"; } >> "$OUT/axe-errors.txt"; rm -f "$1"
      return 1
    fi
    sleep 1
  done
}

# Whether axe can read this pose's tree at all (it couldn't when folded, 2026-11-27): if
# not, a shot settles by its picture instead, and has no tree to check.
TREES=unknown

# Waits, for at most 25 s, until the app has drawn and has stopped changing: the same tree
# twice running with more in it than a launch screen has; or, without trees, the same
# picture twice running that is more than a black screen.
settle() {
  local shot="$1" previous="" start=$SECONDS size sum
  if [ "$TREES" = unknown ]; then
    sleep 2
    if tree "$shot.tmp" 6; then TREES=yes; else TREES=no; echo "   (no accessibility trees in this pose: see axe-errors.txt)"; fi
  fi
  while (( SECONDS - start < 25 )); do
    if [ "$TREES" = yes ]; then
      tree "$shot.tmp" 2 || { sleep 0.5; continue; }
      size=$(grep -c '"role":' "$shot.tmp" || true)
      sum=$(shasum "$shot.tmp" | cut -d' ' -f1)
      min=${MIN_ELEMENTS:-6}
    else
      xcrun simctl io "$UDID" screenshot --display="$DISPLAY_ID" "$shot.tmp" >/dev/null 2>&1 || { sleep 0.5; continue; }
      size=$(wc -c < "$shot.tmp" | tr -d ' ')
      sum=$(shasum "$shot.tmp" | cut -d' ' -f1)
      min=${MIN_PICTURE:-60000}
    fi
    echo "$((SECONDS - start)) $size $sum" >> "$shot.settle"
    if [ "$size" -ge "$min" ] && [ "$sum" = "$previous" ]; then rm -f "$shot.tmp"; return 0; fi
    previous="$sum"
    sleep 0.5
  done
  rm -f "$shot.tmp"
  return 1
}

# One shot: launch with the scene's arguments, wait for the screen to settle, tap a control
# by its label if the scene asks (for an open menu), then the picture and the tree.
shoot() {
  local name="$1" tap="$2"; shift 2
  local shot="$OUT/$name"
  echo "$name" >> "$OUT/expected.txt"
  local began=$SECONDS
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "$@" >/dev/null
  if ! settle "$shot"; then echo "   $name: never settled (see $name.settle)"; fi
  if [ -n "$tap" ]; then
    local tries=0
    until axe tap --label "$tap" --udid "$UDID" >/dev/null 2>&1; do
      (( ++tries < 4 )) || { echo "   $name: couldn't tap “$tap”"; break; }
      sleep 1
    done
    sleep 1   # the menu's animation
  fi
  sleep 0.7   # the last animation (the keyboard, a push)
  xcrun simctl io "$UDID" screenshot --display="$DISPLAY_ID" "$shot.png" >/dev/null 2>&1 || echo "   $name: no screenshot"
  if [ "$TREES" = yes ]; then tree "$shot.json" || echo "   $name: no tree"; fi
  echo "   $name ($((SECONDS - began)) s)"
}

wanted() {   # scene tier
  if [ -n "$ONLY" ]; then [[ " $ONLY " == *" $1 "* ]]; else [ "$TIER" = full ] || [ "$2" = core ]; fi
}

trim() { sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$1"; }

# name | tier | poses | variants | launch arguments | tap
while IFS='|' read -r name tier poses variants arguments tap; do
  name=$(trim "$name"); [[ -z "$name" || "$name" == \#* ]] && continue
  tier=$(trim "$tier"); poses=$(trim "$poses"); variants=$(trim "$variants"); tap=$(trim "${tap:-}")
  [[ " $poses " == *" $POSE "* ]] || continue
  wanted "$name" "$tier" || continue
  eval "args=($arguments)"   # the file is this repository's own
  for variant in $variants; do
    case "$variant" in
      default)  shoot "$name" "$tap" "${args[@]}" ;;
      large)    xcrun simctl ui "$UDID" content_size accessibility-large
                shoot "$name-large" "$tap" "${args[@]}"
                xcrun simctl ui "$UDID" content_size large ;;
      contrast) xcrun simctl ui "$UDID" increase_contrast enabled
                shoot "$name-contrast" "$tap" "${args[@]}"
                xcrun simctl ui "$UDID" increase_contrast disabled ;;
      *)        echo "   $name: unknown variant $variant" ;;
    esac
  done
done < ci/scenes.txt

ls -l "$OUT" | tail -n +2 | awk '{print $5, $9}' | grep -v settle || true

# Leaving the simulator running makes the runner's cleanup take ~45 s.
pkill -9 -f CoreSimulator || true
