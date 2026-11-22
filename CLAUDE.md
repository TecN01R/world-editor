# Working on World Editor

Target: iPhone Duo only, native Swift/SwiftUI with TextKit. No cross-platform
UI frameworks. Fedora is only the xtool build machine.

## Workflow for every change

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
5. Push to `main`. CI runs the WriterKit tests on Linux, builds the app (XcodeGen and
   the xtool package layout), and screenshots it on the iPhone Duo simulator.
   Screenshots live only on the `ci-screenshots` branch: CI force-pushes the
   latest set there as a single orphan commit (never on `main`, never as
   artifacts). Fetch them with `ci/fetch_screenshots.sh`, look at them
   before reporting a UI change as done, send them to the user in chat, then
   delete local copies.

## Conventions

- Dark mode first: design and review UI in dark appearance (CI screenshots
  are dark); light mode must still work.
- iOS defaults first: use stock components and take their default look and
  placement (titles, toolbars, sidebar, keyboard bar). Customise only where
  Kevin asks or a default clearly fails a stated rule, and say which is which.
- Accessibility is not optional: Dynamic Type for all text (Focus mode
  sizes itself to the page), VoiceOver labels on every control, standard
  controls over custom ones.
- Naming: a note is a **page**; the two ways to view one are **Edit** and
  **Focus** mode.
- Push straight to `main`. Don't create branches: this environment can't
  delete them, so they pile up.

## Rules that are not negotiable

- The AI never authors content or edits the user's writing. See
  `docs/ai-charter.md`; enforcement lives in `Provenance` and `Guardrails`.
- All inference on device. Never use server-backed Foundation Models.
- Focus mode never scrolls; the last line stays clear of the keyboard. See
  `docs/focus-mode.md`.
