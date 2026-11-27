#!/usr/bin/env bash
# The design lint (docs/design.md): a screen is built only from the design system in
# App/Sources/Design/, so nothing outside it sets a font, colour, spacing, duration, bar
# or symbol of its own. Runs on every push (the Linux job) and before every install
# (scripts/run-on-phone.sh).
#
# - ci/design-lint-baseline.txt lists the files not yet moved onto the design system;
#   their findings are counted, not failed. A listed file with no findings fails, so the
#   list only shrinks.
# - One line may be let through with a comment on it or on the line above:
#       // design-lint: allow(space) why this one is different
#   More than MAX_ALLOWED of those fails.
#
# Usage: ci/lint_design.sh [--all]      --all also prints the baseline files' findings
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCES=App/Sources
BASELINE=ci/design-lint-baseline.txt
MAX_ALLOWED=12
[ "${1:-}" = "--all" ] && ALL=1 || ALL=0

# rule|pattern (extended regex, GNU grep)
RULES=(
  'font|\.font\(|\b(UI)?Font\.(system|custom|systemFont|preferredFont)\b|\.fontDesign\(|\.fontWeight\(|UIFont\(descriptor'
  'color|foregroundStyle\(\.(primary|secondary|tertiary|quaternary)\b|\.tint\(|\b(UI)?Color\.(red|orange|gray|white|black|system[A-Z]\w*|\w*[lL]abel)\b|\b(UI)?Color\((red|white|hue)|\)\.opacity\(0?\.[0-9]'
  'space|\.padding\(([^)]*[ (,])?[1-9]|\bspacing: *[1-9]|cornerRadius: *[0-9]|EdgeInsets\([^)]*[1-9]|constant: *-?[1-9]|([wW]idth|[hH]eight): *[1-9]'
  'motion|duration: *[0-9.]|\.delay\([0-9.]'
  'chrome|\.toolbar *[({]|ToolbarItem|navigationTitle\(|navigationBarTitleDisplayMode\(|toolbarVerticalBehavior\(|presentationDetents\(|containerBackground\(|listRowSeparator\(|listRowInsets\('
  'glass|glassEffect\(|UIGlassEffect|GlassEffectContainer'
  'symbol|system(Image|Name): *"'
)

# The findings in one file, as "file:line: rule: source line".
findings() {
  local file="$1" entry rule pattern
  for entry in "${RULES[@]}"; do
    rule="${entry%%|*}"; pattern="${entry#*|}"
    { grep -nE -- "$pattern" "$file" || true; } | awk -v file="$file" -v rule="$rule" '
      BEGIN {
        # Lines let through: the one carrying the comment, and the one under it.
        marker = "design-lint: allow(" rule ")"
        while ((getline line < file) > 0) { n++; if (index(line, marker)) { allowed[n] = 1; allowed[n + 1] = 1 } }
        close(file)
      }
      {
        number = $0; sub(/:.*/, "", number)
        text = $0; sub(/^[0-9]+:/, "", text)
        if (text ~ /^[[:space:]]*\/\//) next          # a comment line
        if (number in allowed) next
        sub(/^[[:space:]]+/, "", text)
        printf "%s:%s: %s: %s\n", file, number, rule, text
      }'
  done
}

mapfile -t FILES < <(find "$SOURCES" -name '*.swift' \
  -not -path "$SOURCES/Design/*" -not -path "$SOURCES/Scenes/*" -not -path "$SOURCES/AI/*" | sort)
mapfile -t LISTED < <(grep -vE '^\s*(#|$)' "$BASELINE" 2>/dev/null || true)
listed() { local f; for f in "${LISTED[@]}"; do [ "$f" = "$1" ] && return 0; done; return 1; }

failed=0 tolerated=0
for file in "${FILES[@]}"; do
  found="$(findings "$file" | sort -t: -k2,2n -u)"
  count=$(printf '%s' "$found" | grep -c . || true)
  if listed "$file"; then
    if [ "$count" -eq 0 ]; then
      echo "error: $file has no findings left: remove it from $BASELINE"; failed=1
    else
      tolerated=$((tolerated + count))
      [ "$ALL" -eq 1 ] && printf '%s\n' "$found"
    fi
  elif [ "$count" -gt 0 ]; then
    printf '%s\n' "$found" | sed 's/^/error: /'; failed=1
  fi
done

# A file in the list that is gone should leave the list too.
for file in "${LISTED[@]}"; do
  [ -f "$file" ] || { echo "error: $file is in $BASELINE but no longer exists"; failed=1; }
done

allows=$(grep -rn --include='*.swift' 'design-lint: allow(' "$SOURCES" | grep -vc "^$SOURCES/\(Design\|Scenes\|AI\)/" || true)
if [ "$allows" -gt "$MAX_ALLOWED" ]; then
  echo "error: $allows lines are let through with design-lint: allow, more than $MAX_ALLOWED"; failed=1
fi

echo "design lint: ${#FILES[@]} files, ${#LISTED[@]} still on the baseline with $tolerated findings, $allows let through"
exit "$failed"
