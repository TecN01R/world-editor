#!/usr/bin/env bash
# Turns what ci/screenshots.sh saved (shots/<pose>/*.png and *.json) into what gets
# published on the ci-screenshots branch, in publish/:
#
#   <pose>/<scene>.jpg     each screen, at most 1400 px on its long side
#   crops/<pose>-<scene>.png   the middle of each reading screen at full resolution, to judge type
#   sheets/<pose>.jpg      every screen of a pose side by side: the same title, buttons,
#                          margins, headings and rows should show on every one
#   trees/<pose>/<scene>.json  each screen's accessibility tree (what ci/check_ui.py read)
#   checks.txt             what the checks found
#   missing.txt            shots that should exist and don't (empty when all are there)
#
# Runs on Linux (ImageMagick). Usage: ci/publish_shots.sh <commit>
set -euo pipefail
commit="${1:?the commit these are of}"
rm -rf publish && mkdir -p publish/crops publish/sheets
echo "$commit" > publish/SOURCE_COMMIT
: > publish/missing.txt

# Screens whose type is judged up close.
READING='^(edit|fields|page-|talk|focus)'

for dir in shots/*/; do
  pose=$(basename "$dir")
  mkdir -p "publish/$pose" "publish/trees/$pose"
  while read -r name; do
    [ -n "$name" ] || continue
    png="$dir$name.png"
    if [ ! -s "$png" ]; then echo "$pose/$name" >> publish/missing.txt; continue; fi
    convert "$png" -resize '1400x1400>' -quality 82 "publish/$pose/$name.jpg"
    [ -s "$dir$name.json" ] && cp "$dir$name.json" "publish/trees/$pose/$name.json"
    [ -s "$dir$name.settle" ] && cp "$dir$name.settle" "publish/trees/$pose/$name.settle"   # how long it took to settle
    if [[ "$name" =~ $READING ]]; then
      # The upper middle of the screen, as large as it was drawn.
      convert "$png" -gravity North -crop '1400x1000+0+120' +repage "publish/crops/$pose-$name.png" || true
    fi
  done < "$dir/expected.txt"
  [ -s "${dir}axe-errors.txt" ] && cp "${dir}axe-errors.txt" "publish/trees/$pose/axe-errors.txt"   # why a tree couldn't be read
  # A contact sheet: every screen of this pose, labelled, on the page's own grey.
  if ls "publish/$pose"/*.jpg >/dev/null 2>&1; then
    montage -label '%t' "publish/$pose"/*.jpg -tile 6x -geometry '330x480>+10+10' \
      -background '#101012' -fill '#c2c2c7' -pointsize 15 "publish/sheets/$pose.jpg"
  fi
done

if [ -f ci/check_ui.py ]; then
  python3 ci/check_ui.py publish/trees > publish/checks.txt 2>&1 || echo "(checks reported problems)" >> publish/checks.txt
else
  echo "no checks yet" > publish/checks.txt
fi

echo "published: $(find publish -name '*.jpg' | wc -l) pictures, $(wc -l < publish/missing.txt) missing"
cat publish/missing.txt
tail -30 publish/checks.txt
