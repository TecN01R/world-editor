# Handoff (21 Nov 2026)

For a new Claude session picking up from the long cloud session that built the
features below. Read `CLAUDE.md` first; this covers what isn't there.

## How Kevin wants to work

- **KISS: stock iOS and the HIG.** Default SwiftUI/UIKit components with their
  default look. Customise only when Kevin asks or a default breaks a stated
  rule, and say which parts are custom. Don't chase edge cases the stock
  controls don't handle on their own.
- **"Silky, buttery, modern", lowest cognitive load.** The app's aim is to
  reduce friction, writer's block and intimidation, hence the planned Socratic
  prompts. Don't copy other apps prescriptively.
- **Iteration speed matters most.** Lean tests where bugs have bitten.
  Screenshots only of the screens that changed, Duo only (folded and open),
  dark.
- **Throwaway experiments:** Kevin wants risky features provable without
  touching `main`. He approved one branch for this (below); he deletes it.

## The app today

- Pages with rich text, `@` links (Notes-style popover at the caret, links
  follow renames), Mentions sheet, Edit and Focus modes, a format bar pinned to
  the keyboard, and Spotlight search (Core Spotlight only; Kevin tests search
  on the device, CI can't).
- **Page types and fields** (`Packages/WriterKit/.../Fields.swift`,
  `App/Sources/PageFields.swift`): shared fields of kinds text, long text,
  number, date, choice, yes/no and page link. Stock controls, no Liquid Glass
  in the content (HIG). Rows stack via `ViewThatFits` when two columns don't
  fit. Clear buttons via UIKit appearance. A page field's menu ends with
  "New {Type}…", which creates a typed page and links it. The type line's
  menu has "Edit {Type} Fields…" (`TypeFieldsSheet`): stock list editing to
  remove a field from every page of the type (values kept), reorder, edit, or
  add one (Kevin, 2026-11-24: removing was only in a field name's long-press
  menu, which he couldn't find). Tapping a field's name edits the field;
  holding it opens the menu (Edit Field…, Remove from {Type}): a long press
  never deletes outright, as in iOS's own apps.
- **Filing from the companion** (`Guardrails/Filing.swift`, `FilingRecord`):
  what the author tells the companion becomes types, fields and linked pages
  on its own, in their words, with Undo in the conversation

## Open threads

1. **Suggested fields:** the experiment lives on the branch
   `experiment/suggested-fields`, logic only, with tests passing.
   - **What it does:** suggests values for a page's *empty, existing* fields
     from the author's own writing: an `@` link to a page that only one field
     takes, or one of a choice field's options named as a whole word. Never
     when ambiguous.
   - **Kevin's verdict:** undecided. He worried that without NLP it can't
     suggest new fields or types (true; that needs Apple's on-device model,
     testable only on the Duo).
   - **Next, if wanted:** dimmed suggestion rows in Edit mode with the source
     sentence and a tap to accept, behind a launch flag. Focus mode is never
     interrupted.
2. **Local loop (the way we work now):** Claude runs on the Fedora machine,
   tests WriterKit locally and installs with `scripts/run-on-phone.sh`; Kevin
   tries it on the Duo, then we push and CI stays the safety net. The
   autodeploy service is redundant with this, and it works in the same
   checkout and relaunches the app once CI passes, so Kevin may turn it off
   (`systemctl --user disable --now world-editor-autodeploy`). A weekly
   re-install isn't needed: every install re-signs, so the 7-day signature
   only lapses after a week without one.
3. **Later:** on-device art at the top of a page (with colour derived from it),
   the Socratic and continuity companion features, and possibly NLP-based field
   suggestions. All need the device. Tags and "book posture" were dropped:
   Apple's seated posture keeps documents in place, so there's nothing to do.
4. **A world's own calendar (Kevin, 2026-11-24):** eventually a custom date
   picker on a calendar the author defines (months, years, eras). Until then
   dates are text fields, filed in the author's words ("spring of 1214",
   "first day of Highsun, year 402"), so they can be read into that calendar
   when it exists.

## Device setup (Fedora, done)

- **Setup is one command:** `scripts/setup-fedora.sh`. Background installs
  (`scripts/autodeploy.sh`, a user service) are live.
  Logs: `journalctl --user -u world-editor-autodeploy -f`.
- **Wi-Fi installs** go through netmuxd, a system service. Until 21 Nov it
  never started: the setup installed its release *archive* as the program,
  in the home folder, where SELinux won't let a system service run anything.
  It now unpacks it into `/usr/local/bin`. With the cable plugged in, usbmuxd
  takes over.
- **Swift** is matched to the iOS SDK's own Swift version (read from the SDK),
  installed with swiftly as swift.org's UBI 9 build. swift.org's Fedora builds
  stopped at Fedora 39 and Swift 6.2.
- **Xcode 27.1 exactly:** 27.2 has no Duo SDK. The script finds the `.xip`
  itself.
- **xtool sign-in:** an Apple ID with **Advanced Data Protection** never gets a
  2FA code, because Apple refuses it on the older Mac that xtool emulates. Use
  a second Apple ID.
- **Patched xtool:** the setup installs our xtool build, published as the
  `xtool-patched` release by `.github/workflows/xtool.yml` from xtool's main
  plus `ci/xtool-2fa.patch`.
  - The patch reads Apple's 2FA mode from the login status, asks for a
    trusted-device code when the mode is unknown, and prints `[gsa]` lines
    when `XTOOL_DEBUG_GSA=1` (the setup sets this).
  - It turned out *not* to be the fix (ADP was), only harmless hardening plus
    diagnostics.
  - Once sign-in has worked a while, consider going back to stock xtool and
    deleting the patch, the workflow and the release.

## CI

- **Jobs:** Linux tests, an iOS build, and Duo simulator screenshots, chosen by
  the `Screenshots:` commit trailer. Only pushes take screenshots; pull
  requests (Dependabot, which Kevin said to ignore) don't.
- **Taps:** `axe` taps controls by VoiceOver label, for shots of open menus,
  with retries while the folded Duo settles.
- **Slow:** about 5.5 minutes to screenshots. Proposed fix, not done: build
  inside the screenshots job instead of handing the app over from a separate
  job, which saves roughly 2 minutes.
