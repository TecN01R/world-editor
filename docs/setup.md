# Building without a Mac

Everything builds on GitHub's Mac runners. Two workflows:

- **CI** (every push): tests the shared Swift package on Linux, builds the
  iOS app for the simulator and, when UI code changed, screenshots it on the
  iPhone Duo simulator (published to the `ci-screenshots` branch). Needs no
  setup.
- **TestFlight** (manual, or on a `v*` tag): archives, signs and uploads a
  build. Needs the one-time setup below.

## One-time TestFlight setup

You need a paid Apple Developer Program membership. Every step works from a
phone browser.

1. **Create the app record.** In App Store Connect → Apps → **+** → New App:
   platform iOS, name "World Editor", bundle ID `com.tecn01r.worldeditor` (or
   your own; register it first under Certificates, Identifiers & Profiles →
   Identifiers if it isn't offered). Enable the **Increased Memory Limit**
   capability on that identifier.
2. **Create an API key.** App Store Connect → Users and Access →
   Integrations → App Store Connect API → **+**. Role: **Admin** (needed for
   cloud-managed signing certificates). Download the `.p8` file once and note
   the **Key ID** and **Issuer ID**.
3. **Add to GitHub.** Repo → Settings → Environments → New environment
   `testflight`, then add:
   - Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_BASE64`
     (the `.p8` file's contents, base64-encoded)
   - Variables: `APPLE_TEAM_ID` (Membership details → Team ID),
     `BUNDLE_ID` (e.g. `com.tecn01r.worldeditor`)
4. **Run it.** Actions → TestFlight → Run workflow. The build appears in
   TestFlight after Apple finishes processing it.

Signing is cloud-managed: Xcode on the runner creates and fetches the
certificate and provisioning profile itself using the API key, so no
certificates are exported or stored in the repo.

## Cost

GitHub's macOS minutes count 10× against a private repository's free
allowance. Each iOS build takes a few minutes; the screenshot job uses a
second Mac, and only when UI code changed. The Linux test job is cheap.
