# Focus mode behaviour

TextKit measures; `FocusLayout` (shared, tested) holds the size search
(`FocusFit`), where words may break (`FocusBreaks`) and what makes a page
(`FocusPages`); `FocusEditor` and
`FocusLines` (UIKit) do the rest.

## Layout

- **The goal:** the text takes the most screen it can, always, folded or
  open, so a blank page never feels small. Everything below serves that.

- One paragraph per page; blank lines in a row (spacing in Edit mode) make one
  empty page, not one each. Return splits at the caret onto a new page;
  Backspace at the very start joins with the previous page.
- The paragraph is set as large as the page allows, to half a point. What
  must fit is the letters as drawn, from the top of the tallest to the bottom
  of the lowest, so a lone "H" fills the page. The empty space a line box
  keeps above and below the letters (for accents, and for tails like "g")
  may run off the page, and the caret is cut off at the page's bottom. So the
  first letter with a tail shrinks the text a step. Across, the drawn
  letters stay on the page as well: a big serif W's ink reaches past the
  width lines wrap by, so it's the ink that must fit. An empty page is sized
  as if it held an "M". The page runs from the top of
  the screen to the keyboard (`keyboardLayoutGuide`), with the same margin
  above, below and at the side, so there's nothing to estimate. Tall
  letters may sit under the camera; avoiding just the cutout would mean
  hard-coding its shape.
- Natural line spacing: TextKit's line boxes hold every glyph, so nothing is
  clipped. `FocusLines` lays the text out off screen as the text view does
  (TextKit 1, same hyphenation); Core Text gives the letters' outlines.
- Words break across lines only at a hyphen, where the language allows one,
  and never the paragraph's last word (usually the one being typed, which
  would split and rejoin under the caret). A word is cut without a hyphen
  only when it can't fit at the minimum size. (Lines still break after a
  hyphen, dash or slash, and between the characters of scripts written
  without spaces, such as Chinese or Thai.)
- The block is centred on the page by its drawn letters (Core Text glyph
  outlines), not its line boxes. A single line is centred across the page;
  once it wraps it's left-aligned (the switch comes with the size change).
  A centred line with room to spare is centred on the screen rather than
  the page, which keeps a strip clear on the right for the dots; wrapped
  text keeps to the left margin.
  The letters and the caret stay clear of the keyboard.
- The page ignores the safe area: revealed controls draw over it, so showing
  or hiding them never reflows the text.

## Typing

- Every keystroke takes the largest size that fits, growing as well as
  shrinking. (A rule that only grew for a 4.5% win, to stop bouncing as
  words wrap, was tried and dropped: it left the text smaller than it
  could be.)
- Size changes animate briefly, as a zoom: the letters scale where they
  are rather than snapping to the new size and sliding into place. The
  first letter is the fixed point, so a centred line doesn't jump sideways
  when a letter is added.
- Inline predictive text is off in Focus mode (it adds unmeasured text).

## Navigation

- Vertical dots, one per paragraph, centred on the page; drag or tap to move.
  Shown whenever the page has more than one paragraph, dimmed while writing. Current page is a pill; empty pages are
  hollow.
- Everything else (bars, status, home indicator, pages list) hides while
  writing. A tap anywhere shows them, with a close button, for a few
  seconds (a tap on the writing still places the caret); typing hides them.
  VoiceOver users always keep them.
- Swipe up/down anywhere to move between pages, except on the caret or a
  selection handle, where a drag moves them. VoiceOver can adjust the dots.
- Switching between Edit mode and Focus mode keeps the caret position.
