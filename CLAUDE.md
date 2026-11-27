# Working on World Editor

Target: iPhone Duo only, native Swift/SwiftUI with TextKit. No cross-platform
UI frameworks. Fedora is only the xtool build machine.

**The goal is frictionless.** It's for people like Kevin, with a head full of
ideas and a fear of blank pages and of structure, to get it onto the page.
Every feature, and the AI above all, is judged by whether it lowers that
friction: no forms to fill first, no prompts to answer, no setup before
writing. Structure grows out of the writing, never ahead of it.

## Workflow for every change

The to-do list is `docs/todo.md`: work from it, keep it current, and delete an item
only once it's on Kevin's phone and checked, or he has answered it.

1. Make the change. Keep `Packages/WriterKit` Foundation-only (it is tested on Linux).
2. **Simplify before committing:** run the `code-simplifier` agent on the files
   you changed. If that agent isn't available in the session, do the same pass
   by hand: remove dead code and leftovers from experiments, merge duplicated
   logic, tighten names, keep comments accurate. Never change behaviour in
   this pass.
3. Add or update tests in `Packages/WriterKit/Tests` for logic changes.
4. Run the tests (`swift test --package-path Packages/WriterKit`) and the design lint
   (`ci/lint_design.sh`), then push to `main`. CI runs both on Linux on every push; check
   they passed before starting the next change.
5. **Anything that changes a screen is looked at before it's installed** (Kevin,
   2026-11-27, after a day of patch installs: "This is not at all reaching any of the
   goals of frictionless use, consistency, or professional development that I desire of
   this app"). On every push that touches the app, CI's Macs build it and render its
   scenes (`ci/scenes.txt`) on the iPhone Duo simulator, folded, unfolded and at large
   text; the repo is public, so they cost nothing. Fetch them
   (`ci/fetch_screenshots.sh`), review them against `docs/design.md` by
   `docs/design-review.md`, and only then install: `scripts/run-on-phone.sh` builds and
   installs (seconds when little changed). The simulator build uses Apple's model:
   llama.cpp's framework, the companion's engine, has no simulator build. Screenshots
   live only on the `ci-screenshots` branch: CI force-pushes the latest set there as a
   single orphan commit (never on `main`). They are Claude's check: don't send them to
   Kevin unless he asks. A change no screen shows (the companion's engine) is checked by
   its tests and the phone's log instead.
6. Few, complete installs: an install is a finished step Kevin can use, not a patch for
   what he just pointed at. When he reports something, trace its cause in the code and
   the phone's log before changing anything.

## Conventions

- The design has a specification, `docs/design.md`, and it comes first: a screen is
  specified there, then built only from the design system (`App/Sources/Design/`, with
  its numbers in WriterKit's `DesignTokens`). Nothing outside it sets a font, colour,
  spacing, duration, bar or symbol of its own; `ci/lint_design.sh` fails the push.
- Dark only (Kevin, 2026-11-27: "Let's stop offering a light mode I'll never use
  it"): Info.plist's `UIUserInterfaceStyle` is Dark. One look (`Look`), grey and white
  only, as ChatGPT has it: iOS's own elevated greys and text colours, every control
  white, no accent colour, red only to delete ("All the mixture of cool and warm colors
  and random icon colors just seems unprofessional"). No themes. Kevin doesn't choose
  between design options: decide from research and successful apps, ship one, adjust.
- iOS defaults first: use stock components and take their default look and
  placement (titles, toolbars, sidebar, keyboard bar). Customise only where
  Kevin asks or a default clearly fails a stated rule, and say which is which.
  Every place the app differs from stock is listed in `docs/stock-deviations.md`
  with why; a new one gets a line there and is named to Kevin when it ships.
- Accessibility is not optional: Dynamic Type for all text (Focus mode
  sizes itself to the page), VoiceOver labels on every control, standard
  controls over custom ones.
- Type: what the user writes is New York (their writing, page titles,
  world, field values), wherever it's shown; all other UI is San Francisco,
  including type and field names, which are the app's labels (Kevin,
  2026-11-24). System-drawn text (menus, alerts, iOS's own
  navigation titles, as the unfolded pages list's) keeps the system font:
  iOS ignores the app's fonts there.
- Naming: a note is a **page**; projects are **worlds**; the app's two places are
  **Talk** and **World**; a page is read, or in **Edit** or **Focus** mode.
- Push straight to `main`. Don't create branches: this environment can't
  delete them, so they pile up.

## Rules that are not negotiable

- The AI never authors content. It never rewrites the user's writing; it may put
  their own words from the conversation into a page, tidied only in capitalisation
  and punctuation, marked as placed, with Undo (Kevin, 2026-11-24: "I actually fully
  desire it to fill my pages as long as it uses my own words"). When the user corrects
  something in the conversation, their new words replace the sentence they contradict,
  even one the user typed, marked as changed, with Undo bringing the old one back
  (Kevin, 2026-11-27: "a"). See
  `docs/ai-charter.md`; enforcement lives in `Provenance` and `Guardrails`.
- All inference on device. Never use server-backed Foundation Models.
- Focus mode never scrolls; the last line stays clear of the keyboard. See
  `docs/focus-mode.md`.
