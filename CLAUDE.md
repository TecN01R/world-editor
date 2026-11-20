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
4. Push to `main`. CI runs Linux and macOS tests, builds the app (XcodeGen and
   the xtool package layout), and screenshots it on the iPhone Duo simulator.
   Screenshots are a temporary CI artifact (kept one day), never committed.
   Download them, look at them before reporting a UI change as done, send them
   to the user in chat, then delete the local copies.

## Conventions

- Dark mode first: design and review UI in dark appearance (CI screenshots
  are dark); light mode must still work.
- Push straight to `main`. Don't create branches: this environment can't
  delete them, so they pile up.

## Rules that are not negotiable

- The AI never authors content or edits the user's writing. See
  `docs/ai-charter.md`; enforcement lives in `Provenance` and `Guardrails`.
- All inference on device. Never use server-backed Foundation Models.
- Focus mode never scrolls; the last line stays clear of the keyboard. See
  `docs/focus-mode.md`.
