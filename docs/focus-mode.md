# Focus mode behaviour

Settled through the web prototype (`prototypes/focus-writer/index.html`), then
rebuilt native-first: TextKit measures, `FocusFit` (shared, tested) holds the
two sizing rules, `FocusEditor` (UIKit) does the rest.

## Layout

- One paragraph per page. Return splits at the caret onto a new page;
  Backspace at the very start joins with the previous page.
- The paragraph is set as large as the page allows, to half a point. The page
  runs from near the top of the screen to just above the keyboard
  (`keyboardLayoutGuide`), so there's nothing to estimate.
- Natural line spacing: TextKit's line boxes hold every glyph, so nothing is
  clipped and its measurement is the layout. The text view has the final
  say: if its layout is ever taller than the page, the size steps down.
- Words never break mid-word unless one word can't fit at the minimum size.
- The block is centred on the page and left-aligned within it.
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
  Always shown, dimmed while writing. Current page is a pill; empty pages are
  hollow.
- Everything else (bars, status, home indicator, pages list) hides while
  writing. A tap outside the text shows a close button for a few seconds;
  typing hides it. VoiceOver users always keep it.
- Swipe up/down to move between pages. VoiceOver can adjust the dots.
- Switching between Edit mode and Focus mode keeps the caret position.
