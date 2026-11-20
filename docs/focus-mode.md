# Focus mode behaviour

Settled through the web prototype (`prototypes/focus-writer/index.html`).
The native app implements the same rules in `FitEngine` (shared, tested) and
`FocusEditor` (UIKit).

## Layout

- One paragraph per page. Return splits at the caret onto a new page;
  Backspace at the very start joins with the previous page.
- The paragraph is set as large as the page allows. The page ends at the
  keyboard (`keyboardLayoutGuide`), so there's nothing to estimate.
- Size changes in discrete steps of ~2.2%.
- Words never break mid-word unless one word can't fit at the minimum size.
- Fit the **ink** at the top: the tallest letters touch the top of the page,
  not the empty space above them.
- The **last line box stays inside the page** (only deep descenders may hang
  below), because iOS draws the caret the full line height. A caret near the
  keyboard makes iOS scroll; the page must never scroll.
- The block is centred between the top of the screen and the keyboard. This
  only moves the text; it never changes size or wrapping.
- Text is left-aligned within the block.
- After fitting, the real text view is checked; if it's taller than predicted,
  step down until it fits.

## Typing

- While writing forward, the size only grows for a clear win (≥ 4.5%), so the
  page doesn't bounce as words wrap. Deleting, resizing, folding/unfolding
  and changing pages let it grow freely.
- Size changes animate briefly.
- Inline predictive text is off in Focus mode (it adds unmeasured text).

## Navigation

- Vertical dots, one per paragraph; drag or tap to move. Current page is a
  pill; empty pages are hollow.
- Swipe up/down to move between pages. VoiceOver can adjust the dots.
- Switching between page view and Focus mode keeps the caret position.
