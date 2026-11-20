# Building on Fedora with xtool

[xtool](https://github.com/xtool-org/xtool) builds, signs and installs the
app from Linux. The repository root is a Swift package (`Package.swift` +
`xtool.yml`) for exactly this; GitHub CI checks that it builds for iOS on every
push.

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

## Every change after that

```bash
scripts/run-on-phone.sh
```

It pulls the latest commits, rebuilds only what changed, installs and
launches the app.

## Limits to know about

- **Free Apple ID:** apps expire after 7 days and need reinstalling (run the
  script again). A paid Developer Program membership removes this, and also
  enables TestFlight.
- **Wireless install** isn't documented by xtool. USB is the supported path.
- **Untested here:** these steps were written without access to a Fedora
  machine. If a step fails, send the error and the script gets fixed.
