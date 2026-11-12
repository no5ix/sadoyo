# 0005. Sadoyo owns its bundle identifier

- Status: accepted
- Date: 2026-11-12
- Affects: `AppIdentity`, `build.sh`, `Resources/Info.plist`, notifications, fan LaunchDaemon, Dock click taps, Quit all, Cleaner, Uninstaller, App Updates, the self-updater, `Tools/uninstall.sh`

## Context

Sadoyo is a fork of Vorssaint and was shipped with the upstream `CFBundleIdentifier`
(`com.vorssaint.utils`). Both apps installed side by side registered as one
application, and a banner posted by Sadoyo opened Vorssaint when clicked.

macOS scopes a lot of behaviour to the bundle identifier rather than to the
bundle file:

- `UNUserNotificationCenter` is scoped to the identifier: its store, categories,
  authorization grant, and — the visible symptom — the click target of a posted
  banner. Clicking a banner resolves the identifier through Launch Services, and
  with two bundles registered under one identifier, the resolver answers with
  one of them (in practice the original app).
- TCC grants, the preferences domain, the login item, a LaunchDaemon label and
  Mach service, and Launch Services registration all key off the identifier too.

The click path itself carries no identifier: the app declares no URL scheme, and
`AppDelegate`'s `UNUserNotificationCenterDelegate` handler only reads the undo
transaction id from the notification's `userInfo` and calls the organizer
in-process. So no notification-payload change can route the click correctly;
only a distinct identity can.

## Decision

Give the installed application its own identity, and keep the neighbour's
identifiers in the source as *foreign* identifiers.

- `com.sadoyo.app` (Release), `com.sadoyo.app.dev` (Developer). Display name and
  executable `Sadoyo` / `SadoyoDeveloper`. Fan daemon `com.sadoyo.app.fan-control`
  per variant, notification namespace `com.sadoyo.notification`.
- One source of truth: `Sources/Vorssaint/Core/AppIdentity.swift`, Foundation-only
  so the launchd fan helper compiles it (that helper has no bundle of its own and
  must be told which app it serves). `Resources/Info.plist` and `build.sh` carry
  the same values, and `Tests/AppIdentityTests.swift` fails if they drift.
- The upstream identifiers are kept, deliberately, as a set of *neighbour* rules
  with a test each: Dock click taps, Quit all, the junk cleaner and uninstaller,
  App Updates, `build.sh --install` and the self-updater all refuse to act on a
  bundle that is not this app. The self-updater reads the staged bundle's
  `CFBundleIdentifier` and refuses a mismatch before it stages, copies, swaps or
  relaunches anything; `--install` only sweeps a retired-name leftover that
  carries this build's identifier.
- A Sadoyo install keeps its settings across the split:
  `Defaults.migrateIdentityPreferencesDomain` copies the old domain in once,
  without overwriting anything chosen since. The neighbour's domain is never
  written, deleted, cleaned, reset, or uninstalled by this app.
- Source-level naming stays: the `Sources/Vorssaint/` layout, SwiftPM target,
  module names, queue and pasteboard labels, internal Info.plist keys, the local
  signing identity name, in-app copy, GPL headers and upstream community links.
  They name the code this fork is built from, not the installed application.

## Consequences

- A Sadoyo install on a Mac that had it under the old identifier must grant TCC
  permissions again; they are bound to the identifier and the signature. The
  first launch after the change says so in System Settings, and
  `docs/TROUBLESHOOTING.md` covers a stale grant that still reads as granted.
- The self-updater installs only bundles carrying Sadoyo's identifier, published
  from this fork's releases (`AppInfo.repositoryURL`), and it requires a
  notarized bundle. Upstream Vorssaint releases are refused by design.
- The two installs share one closed-lid sudoers rule
  (`/etc/sudoers.d/vorssaint-clamshell`): it grants a per-user power privilege,
  not an identity, and each app rewrites it when its own feature needs it.
- The real banner click — Sadoyo's notification opens Sadoyo — can only be
  confirmed by a person at the Mac. See `docs/testing/app-identity.md`.
