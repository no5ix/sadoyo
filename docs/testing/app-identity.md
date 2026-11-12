# App identity and coexistence — how to verify

Rules and rationale: [Sadoyo app identity](../app-identity.md),
[ADR 0005](../decisions/0005-sadoyo-owns-its-bundle-identifier.md).

## Automated

```sh
./build.sh --test-suite=app-identity     # identity, notification and installer contract
./build.sh --test                        # full suite, including the shell scripts below
```

- `Tests/AppIdentityTests.swift` — Sadoyo identifiers are Sadoyo's and disjoint
  from the neighbour's; the notification identifiers and the notification
  response handler name no foreign app; the shipped `Resources/Info.plist`,
  `Resources/com.sadoyo.app.fan-control.plist` and the localized permission
  prompts carry the Sadoyo identity; `build.sh` stamps it and gates its own
  leftover sweep; the cleaner, the sharing endpoints and the self-updater keep
  the neighbour out; preferences cross the identity split once and never again.
- `Tests/DeveloperInstallIsolationTests.sh` — runs the real `--install` block
  against disposable bundles: the original Vorssaint keeps its files and its
  processes, the Developer install touches nothing of the official one, and only
  a leftover carrying this build's identifier is swept.
- `Tests/UpdateFeatureTests.swift` — the installer script carries the identity
  gate, reads the staged `CFBundleIdentifier`, takes the expected identifier from
  its caller, and refuses an identity mismatch before it stages anything.
- `Tests/QuickTogglesQuitAllTests.swift`, `Tests/SwitcherModelFeatureTests.swift`,
  `Tests/AppManagementFeatureTests.swift` — Quit all, Dock click taps and the
  cleaner leave the neighbour install alone.

A passing run proves the shipped identity, the routing path and the sweep rules.
It does not prove Launch Services behaviour on a real Mac.

## The bundle that ships

```sh
./build.sh
plutil -p build/stage/Sadoyo.app/Contents/Info.plist \
    | grep -E 'CFBundleIdentifier|CFBundleName|CFBundleDisplayName|CFBundleExecutable'
codesign -dvv build/stage/Sadoyo.app 2>&1 | grep ^Identifier
ls build/stage/Sadoyo.app/Contents/Library/LaunchDaemons
plutil -p build/stage/Sadoyo.app/Contents/Library/LaunchDaemons/com.sadoyo.app.fan-control.plist
```

Expect `com.sadoyo.app`, `Sadoyo`, `Sadoyo`, `Sadoyo`, a bundle whose
`Identifier` is `com.sadoyo.app`, and one LaunchDaemon plist named
`com.sadoyo.app.fan-control`. Then `./build/Sadoyo --selftest`.

Do the same for `./build.sh --dev` and expect `com.sadoyo.app.dev` with a
`com.sadoyo.app.dev.fan-control` daemon.

## Two installs at once (manual)

Needs the original Vorssaint and Sadoyo both installed, at the Mac.

1. Launch Vorssaint, then Sadoyo. Confirm two processes and two menu bar items:
   `pgrep -xl Vorssaint; pgrep -xl Sadoyo`
2. Confirm Launch Services resolves each identifier to its own bundle:
   `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -A3 'bundle id:.*com.sadoyo.app'`
3. From Sadoyo, trigger a notification (the WhatsApp organizer's undo banner is
   the one with an action). Click the banner: **Sadoyo** activates. Confirm the
   frontmost app: `lsappinfo info -only name "$(lsappinfo front)"`
4. From Vorssaint, post a notification and click it: **Vorssaint** activates.
5. Open Sadoyo's Settings → Advanced. Confirm its Accessibility and Screen
   Recording grants are listed for Sadoyo and Vorssaint's grants are untouched.
6. In Sadoyo: enable the fan control daemon, then
   `sudo launchctl print system/com.sadoyo.app.fan-control` and
   `sudo launchctl print system/com.vorssaint.utils.fan-control`. Each install
   must own its own service.
7. In Sadoyo, turn on Dock click taps and click Vorssaint's Dock icon: Sadoyo
   must not minimise, hide, or cycle Vorssaint's windows.
8. In Sadoyo, run Quit all: Vorssaint must stay running.
9. In Sadoyo's Cleaner, scan junk: no `com.vorssaint.*` entry may be offered.
10. Check Sadoyo's updater against a release published from this fork: it
    installs. Point it at an upstream Vorssaint release: it must report the
    install failure and leave both bundles in place.

Record the macOS version, Mac model, both bundle paths and the observed frontmost
app for each step. A notification click cannot be driven from the test harness:
`UNUserNotificationCenter` needs a bundled, registered app, and the click is
performed by the system's NotificationCenter, not by this process.
