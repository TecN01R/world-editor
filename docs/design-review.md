# Design review

How a screen is checked before it reaches Kevin's phone (CLAUDE.md, "Workflow"). The specification is docs/design.md; this is the checklist that holds a rendered screen against it.

## How

1. Push. CI renders every scene in `ci/scenes.txt` on the Duo simulator and publishes them on the `ci-screenshots` branch, with each screen's accessibility tree and what `ci/check_ui.py` found.
2. `ci/fetch_screenshots.sh` copies them into `build/shots/current` and keeps the set before as `build/shots/previous`.
3. Look in this order: `missing.txt` and `checks.txt`; the contact sheets (`sheets/`), where differences between screens show; each screen; the type crops (`crops/`); the large-text shots; then the previous set, for anything that changed and wasn't meant to.
4. Write each finding as: the scene, the place on it, the rule's number, and how bad (blocker, major, minor). A finding that can't name a rule is dropped or becomes a new rule here first. Sizes and positions come from the accessibility tree, not from the eye.
5. A second reviewer who hasn't seen the change repeats step 3.
6. No blocker or major finding left: record the pass (`ci/review_gate.sh pass`), and the install script lets the build through.

A picture is only a first pass at motion and behaviour: what a still can't show (a push, a swipe back, a fold) is in the last section.

## Rules

**The same everywhere** (contact sheets)
1. The same kind of screen has the same bar: Back first, at most one pinned action, the rest in iOS's own •••. No hand-made ⋯ or Back.
2. One title treatment per kind of screen: a list's title large; a page's own title as its first line, none in the bar.
3. Content starts at the same left edge on every screen, text and controls alike, and nothing touches the screen's edge, the side column, the Dynamic Island or the fold.
4. The same role looks the same everywhere: a heading, a page's row (name, then one line), a note under a reply, an empty state.
5. One symbol per meaning; outline, one colour.
6. Grey and white only. Red only on a delete. No other hue.

**Each screen**
7. What the screen is for is the first and largest thing on it; one pinned action at most.
8. Nothing clipped, overlapping, or cut off mid-word; nothing under the keyboard.
9. Every control is at least 44 pt in both directions (inline links aside).
10. Every control has a VoiceOver label; an icon button has a title.
11. An empty screen names what's missing and says how it fills: by talking.
12. His words are in `ink`; the app's small text in `ink2`; nothing under 24 pt in `faint`.

**Reading** (crops and the reported measurements)
13. Line height is 1.40 times the type size folded and 1.47 unfolded (1.30 on very short lines).
14. A line holds about 36 to 40 characters folded and 60 to 66 unfolded, never over 68.
15. Ragged right; no stack of three hyphens; no single short word alone on a last line where pushing out could avoid it.
16. Punctuation as print sets it: curly quotes, true dashes, ellipses.
17. Read and Edit agree: the title, kind and first line sit within 1 pt of each other, and every line breaks at the same word.
18. His words are New York and the app's are San Francisco, never mixed within one role.

**Large text and contrast**
19. At the accessibility size nothing is clipped; rows wrap instead of truncating; the bars still work.
20. With Increase Contrast, text brightens and nothing disappears.

**Folded and unfolded**
21. The same content in the same order in both. Unfolded may show one more level beside it, never a different arrangement.
22. No text column sits under the fold.

**Against the last set**
23. Nothing changed that wasn't meant to.

## What a still can't show

Checked by hand in the simulator's run or on the phone, and by UI tests as they are added:
- Back and the swipe back return to where he was, with its scroll position.
- Each tab keeps its place when switching; the app reopens where he left off.
- Folding, unfolding and rotating keep the text, the scroll position and the keyboard.
- A reply that is still being written doesn't jump the conversation about.
- Undo takes back exactly what its line says.
