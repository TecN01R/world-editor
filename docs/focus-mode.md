# Focus mode behaviour

TextKit measures, `FocusFit` (shared, tested) holds the two sizing rules,
`FocusEditor` (UIKit) does the rest.

## Layout

- **The goal:** the text takes the most screen it can, always, folded or
  open, so a blank page never feels small. Everything below serves that.

- One paragraph per page. Return splits at the caret onto a new page;
  Backspace at the very start joins with the previous page.
- The paragraph is set as large as the page allows, to half a point. What
  must fit is from the top of the tallest letter to the bottom of the last
  line box: the caret spans the box and must stay clear of the keyboard, but
  the empty space above lowercase letters may run into the top margin, so a
  lone "g" fills the page. The page
  runs from near the top of the screen to just above the keyboard
  (`keyboardLayoutGuide`), so there's nothing to estimate.
- Natural line spacing: TextKit's line boxes hold every glyph, so nothing is
  clipped and its measurement is the layout. The text view has the final
  say: if its layout is ever taller than the page, the size steps down.
- Words never break mid-word unless one word can't fit at the minimum size.
- The block is centred on the page by its drawn letters (Core Text glyph
  outlines), not its line boxes. A single line is centred across the page;
  once it wraps it's left-aligned (the switch comes with the size change). The line boxes (and caret)
  still stay clear of the keyboard.
- The page ignores the safe area: revealed controls draw over it, so showing
  or hiding them never reflows the text.

## Typing

- While writing forward, the size only grows for a clear win (≥ 4.5%), so the
  page doesn't bounce as words wrap. Deleting, the keyboard appearing,
  folding/unfolding and changing pages let it grow freely.
- Size changes animate briefly.
- Inline predictive text is off in Focus mode (it adds unmeasured text).

## Navigation

- Vertical dots, one per paragraph, centred on the page; drag or tap to move.
  Shown whenever the page has more than one paragraph, dimmed while writing. Current page is a pill; empty pages are
  hollow.
- Everything else (bars, status, home indicator, pages list) hides while
  writing. A tap outside the text shows a close button for a few seconds;
  typing hides it. VoiceOver users always keep it.
- Swipe up/down to move between pages. VoiceOver can adjust the dots.
- Switching between Edit mode and Focus mode keeps the caret position.
