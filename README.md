# World Editor

A personal writing and knowledge app for the iPhone Duo (folded and
unfolded), later a laptop. Features are developed by trying them first, then
building them natively.

- **Page view:** the whole document, ordinary editing.
- **Focus mode:** one paragraph per page, set as large as the screen allows,
  resizing as you write. See [docs/focus-mode.md](docs/focus-mode.md).
- **On-device AI that never authors:** search by meaning, a writing
  companion that questions and critiques but never supplies content,
  source-traceable continuity, and illustrations that leave unknowns
  unknown. See [docs/ai-charter.md](docs/ai-charter.md) and
  [docs/models.md](docs/models.md).

## Layout

```
App/                    iOS app (SwiftUI + UIKit text views)
Packages/WriterKit/     Shared, Foundation-only logic; tested on Linux and macOS
  WriterCore            documents and paragraphs, storage
  FocusLayout           Focus-mode sizing rules
  Provenance            facts with verified sources; unknown stays unknown
  Guardrails            companion checks, creative-request handling, illustration plans
  ModelCatalog          models, licences, download/unload policy
docs/                   behaviour specs, AI rules, model choices, setup
project.yml             XcodeGen spec (the Xcode project is generated)
```

## Building

No Mac is required.

- **On your phone from Fedora:** `scripts/setup-fedora.sh` once, then
  `scripts/run-on-phone.sh`. See [docs/fedora.md](docs/fedora.md).
- **CI and TestFlight:** GitHub Actions builds, tests, screenshots the app on
  the iPhone Duo simulator, and ships to TestFlight. See [docs/setup.md](docs/setup.md).
