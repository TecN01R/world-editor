# Building on Fedora with xtool

[xtool](https://github.com/xtool-org/xtool) builds, signs and installs the
app from Linux. The repository root is a Swift package (`Package.swift` +
`xtool.yml`) for exactly this; GitHub CI checks that it builds for iOS whenever
the manifest changes or Swift files are added.

## One-time setup (about 20 minutes, mostly downloading)

```bash
git clone https://github.com/TecN01R/world-editor.git
cd world-editor
scripts/setup-fedora.sh
```

The script:

1. installs `usbmuxd`, `libimobiledevice-utils` and `fuse-libs` with `dnf`
   (the phone connection, plus what AppImages need)
2. installs the Swift toolchain with `swiftly`, if you don't have one
3. installs the xtool AppImage to `~/.local/bin`
4. runs `xtool setup`, which signs you in with your Apple ID and imports
   Apple's iOS SDK from an Xcode `.xip`. Download the `.xip` first from
   <https://developer.apple.com/download/all/> with the same Apple ID.
5. pairs the iPhone over USB (tap **Trust** on the phone)

On the iPhone, the first install also needs **Settings → Privacy & Security →
Developer Mode** turned on, and possibly trusting your developer certificate
under **Settings → General → VPN & Device Management**.

It then sets up two things that run in the background:

6. **Wireless installs.** It turns on Wi-Fi connections for the pairing
   (`pymobiledevice3`) and runs `netmuxd`, which finds the iPhone on your
   network and stands in for `usbmuxd`, so the cable is only needed once.
7. **Automatic updates.** A user service (`world-editor-autodeploy`) checks
   GitHub every minute; when a new commit on `main` has passed CI it pulls,
   rebuilds only what changed and installs it on the phone. Failed CI is
   skipped. Watch it with `journalctl --user -u world-editor-autodeploy -f`.

## Installing by hand

```bash
scripts/run-on-phone.sh
```

Pulls, rebuilds what changed, installs and launches. Handy if the service is
stopped or you want it immediately.

## Limits to know about

- **Free Apple ID:** apps expire after 7 days. The service reinstalls on the
  next commit, but with no new commits you'd run the script by hand. A paid
  Developer Program membership removes this, and also enables TestFlight.
- **Wireless** relies on `netmuxd` and Wi-Fi pairing, which xtool doesn't
  officially document. The phone must be on the same network and awake
  enough to answer; if it can't be reached the install is retried next round.
  To re-pair over USB: `sudo systemctl stop netmuxd`, plug in, `idevicepair
  pair`, then `sudo systemctl start netmuxd`.
- **Untested here:** these steps were written without access to a Fedora
  machine or a Duo. If a step fails, send the error and the script gets fixed.
