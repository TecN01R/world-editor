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
4. **Try it on the Duo first** (this Fedora machine): run the tests with
   `swift test --package-path Packages/WriterKit`, then `scripts/run-on-phone.sh`
   builds, installs and launches the app (seconds when little changed). Kevin
   tries it on the phone; iterate here, then push.
5. Push to `main`. CI runs the WriterKit tests on Linux on every push; check
   they passed before starting the next change. The Mac jobs (building the app
   with XcodeGen and the xtool package layout, and screenshots on the iPhone Duo
   simulator) run only on demand (`gh workflow run CI`), since the repo is
   private and Mac minutes are expensive. The simulator build uses Apple's
   model: llama.cpp's framework, the companion's engine, has no simulator
   build. Screenshots live only on the
   `ci-screenshots` branch: CI force-pushes the latest set there as a single
   orphan commit (never on `main`, never as artifacts). Kevin tests on the Duo
   himself, so don't run them or send screenshots by default; run them (then
   `ci/fetch_screenshots.sh`, delete local copies after) only when he asks or a
   change touches something he can't see on his phone (the other fold state,
   large Dynamic Type).

## Conventions

- Dark only (Kevin, 2026-11-27: "Let's stop offering a light mode I'll never use
  it"): Info.plist's `UIUserInterfaceStyle` is Dark, in iOS's softer dark grey (the
  elevated level). iOS's own colours: gruvbox was tried and reverted ("looks half assed").
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
- Naming: a note is a **page**; projects are **worlds**; the two ways to
  view a page are **Edit** and **Focus** mode.
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
