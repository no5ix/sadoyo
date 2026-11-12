# Sadoyo App Identity and Coexistence

Sadoyo is a fork of [Vorssaint](https://github.com/vorssaint/vorssaint-utils),
and it is meant to be installed on a Mac that also runs the original app. Both
installs sit in `/Applications`, both run at the same time, and each keeps its
own permissions, settings, login item, helper daemon, caches and notifications.

## The identity Sadoyo owns

| | Sadoyo Release | Sadoyo Developer | Original Vorssaint |
|---|---|---|---|
| Bundle identifier | `com.sadoyo.app` | `com.sadoyo.app.dev` | `com.vorssaint.utils` (unchanged) |
| Bundle / display name | `Sadoyo.app`, `Sadoyo` | `Sadoyo (Developer).app` | `Vorssaint.app` |
| Executable | `Sadoyo` | `SadoyoDeveloper` | `Vorssaint` |
| LaunchDaemon + Mach service | `com.sadoyo.app.fan-control` | `com.sadoyo.app.dev.fan-control` | `com.vorssaint.utils.fan-control` |
| Notification namespace | `com.sadoyo.notification…` | same | `com.vorssaint.notification…` |

Stated in exactly three places, which must stay in step:

- `Sources/Vorssaint/Core/AppIdentity.swift` — the runtime source of truth: the
  compiled bundle identifier, both Sadoyo variants, the upstream identifiers as
  *foreign* identifiers, the protected domains, the notification namespace and
  the fan helper derivation. It is Foundation-only so the launchd fan helper
  can compile it: that helper is a bare Mach-O whose own `Bundle.main` carries
  no identifier, so it has to be told which app it serves.
- `Resources/Info.plist` — the shipped `CFBundleIdentifier`, `CFBundleName`,
  `CFBundleDisplayName`, `CFBundleExecutable`, and the app name inside every
  permission prompt (plus the localized copies in `Resources/*.lproj/InfoPlist.strings`).
- `build.sh` — `APP_BUNDLE_ID`, `APP_NAME`, `EXECUTABLE` per variant, and
  `Resources/com.sadoyo.app.fan-control.plist` for the LaunchDaemon. The
  Developer variant rewrites the plist's `Label`, `BundleProgram` and
  `MachServices` at build time, so the two installs register two daemons.

`Tests/AppIdentityTests.swift` (`./build.sh --test-suite=app-identity`) checks
the source, the shipped plists and `build.sh` against each other, so they cannot
drift apart silently.

## Why the bundle identifier is the whole story

`UNUserNotificationCenter` is scoped to the **bundle identifier**, not to the
bundle file that called it. The notification store, the categories, the
authorization grant, and the click target of a posted banner all belong to the
identifier. Clicking a banner asks Launch Services for the app registered under
that identifier. While Sadoyo shipped as `com.vorssaint.utils`, two bundles were
registered under one identifier, Launch Services answered with the original
Vorssaint, and a banner posted by Sadoyo opened Vorssaint.

Clicking a notification is not a deep link: this app declares no URL scheme, and
the response handler in `AppDelegate` only reads the undo transaction id out of
the notification's `userInfo` and calls the organizer in-process. Nothing in the
click path opens an app by identifier, so the fix is the identity itself — and
keeping the click path free of any identifier, which the identity suite asserts.

TCC grants (Accessibility, Screen Recording, Microphone, …) are bound to the
identifier plus the signature, so they do **not** cross the identity split: after
moving to `com.sadoyo.app`, macOS asks for them again. `docs/TROUBLESHOOTING.md`
covers a stale grant that System Settings still shows as granted. The Developer
variant has always been separate in this respect.

## Neighbour rules

The upstream identifiers are kept in `AppIdentity` as the *neighbour's*
identifiers. Each of these is a coexistence rule with a test:

- **Dock click taps** (`DockClickSupport`) skip this app's tiles *and* the
  neighbour's: Vorssaint drives its own Dock tile with its own copy of the
  feature, and acting on it too would toggle its windows twice over.
- **Quit all** (`QuickTogglesSupport`) never targets this app and never targets
  the neighbour's running install.
- **Junk cleaner and uninstaller** (`CleanerSupport`, `CleanerPolicy`,
  `UninstallerSupport`) treat `com.sadoyo.*` and `com.vorssaint.*` as protected
  domains, so neither install's data is ever junk to the other.
- **App Updates** (`AppUpdatesService`) never lists a running bundle that owns
  its own updater: neither this app nor the neighbour.
- **The self-updater** (`UpdateInstallerSupport`) refuses any bundle whose
  `CFBundleIdentifier` is not the running app's, before it stages, copies,
  swaps, or relaunches anything. Without that gate, a release downloaded from
  the upstream feed would delete `Sadoyo.app`, install `Vorssaint.app` in its
  folder and relaunch Vorssaint. The update feed follows `AppInfo.repositoryURL`,
  which points at this fork, for the same reason.
- **`build.sh --install`** only sweeps a retired-name leftover when that leftover
  carries this build's identifier, so an install never removes the neighbour.
- **Data folders** are derived from the running bundle identifier
  (`PrivateFileStore`, caches, the wallpaper index, the shelf and recording
  scratch folders), so two installs never write the same file.

Existing Sadoyo settings survive the split: `Defaults.migrateIdentityPreferencesDomain`
copies the preferences from the domain this fork used before (`com.vorssaint.utils`,
`com.vorssaint.utils.dev` for the Developer variant) into the new one, once,
without overwriting anything already chosen and without touching the keys macOS
injects. The neighbour's domain is never deleted — uninstalling Sadoyo resets
Sadoyo's own permissions and preferences and leaves `com.vorssaint.utils` alone.

Deliberately **not** renamed: the `Sources/Vorssaint/` layout, the SwiftPM
target, module names, `com.vorssaint.*` dispatch-queue and pasteboard labels,
the internal `VorssaintBuildCommit`/`VorssaintFanControlHelperVersion` Info.plist
keys, the local signing identity name, the in-app copy in
`Sources/Vorssaint/Core/Localizations/`, the upstream community links in
`AppInfo`, the GPL copyright headers, and `BundleMigration` (which retires a
pre-2.5 `Vorssaint Utils.app` only when it carries the caller's own identifier,
so it is inert for Sadoyo by construction). Those name the source this fork is
built from, not the installed application.

## Verifying an install

```sh
./build.sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/stage/Sadoyo.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleName' build/stage/Sadoyo.app/Contents/Info.plist
codesign -dvv build/stage/Sadoyo.app 2>&1 | grep identifier
ls build/stage/Sadoyo.app/Contents/Library/LaunchDaemons
```

With both apps installed, Launch Services must resolve each identifier to its
own bundle:

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump \
    | grep -B2 -A1 'com.sadoyo.app\b'
```

The real banner click — post a notification from Sadoyo, click it, confirm
Sadoyo activates, then repeat from Vorssaint — needs a human at the Mac and is
recorded as manual verification in `docs/testing/`; a unit test cannot prove
Launch Services routing.
