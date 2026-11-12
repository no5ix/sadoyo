# Architecture Guide

This document is a navigation map of the current repository, not a substitute for reading the implementation. Confirm paths and ownership against the branch being changed.

## Product and platform

Vorssaint is a native macOS application written primarily in Swift and SwiftUI/AppKit. The project targets macOS 14+ and Apple Silicon. It is organized as a source tree assembled by the repository's shell build system; it does not rely on an Xcode project for the authoritative build.

The installed application is **Sadoyo**, a fork that ships its own macOS
identity (`com.sadoyo.app`, Developer `com.sadoyo.app.dev`, display name and
executable `Sadoyo`) and is meant to be installed beside the original Vorssaint
(`com.vorssaint.utils`). The source tree, target and module names keep the
upstream naming; only the installed identity is Sadoyo's. See
[app identity](docs/app-identity.md) and
[ADR 0005](docs/decisions/0005-sadoyo-owns-its-bundle-identifier.md).

## Build and composition boundary

- `build.sh` is authoritative for source discovery, compiler flags, generated resources, helper/adapter compilation, app-bundle assembly, signing, staging, installation, and test execution.
- `Package.swift` provides Swift Package Manager/editor indexing support. It does not assemble or sign the production app bundle.
- `Sources/Vorssaint` contains the main app source.
- `NowPlayingAdapter` contains the separately compiled Now Playing adapter loaded by the app.
- `FanControlHelper` contains the privileged/helper-side fan-control executable.
- `Resources` contains app resources, metadata, signing entitlements, and bundled assets.
- `Tests` contains the project's custom test harness and behavior tests. The test executable compiles a selected source set; passing tests alone does not prove the complete app bundle builds.
- `Tools` contains development, generation, signing, and maintenance scripts. Inspect each tool before invoking it.

## Main source layers

The principal source folders are:

| Path | Responsibility |
|---|---|
| `Sources/Vorssaint/App` | Application lifecycle, AppDelegate, status-item orchestration, runtime wiring, and app-level coordination |
| `Sources/Vorssaint/Core` | Shared types, feature catalogs, preferences/defaults, localization, common extensions, and cross-feature value models |
| `Sources/Vorssaint/Services` | Stateful services, OS integrations, data acquisition, command execution, adapters, and feature behavior |
| `Sources/Vorssaint/UI` | SwiftUI/AppKit presentation, panels, settings, menus, and reusable UI |
| `Sources/Vorssaint/Support` | Diagnostics and supporting infrastructure; inspect the concrete subtree before assigning ownership |
| `Sources/HIDEventSystem`, `Sources/VMStatisticsCompat` | System-library compatibility/module boundaries used by the Swift target |

Feature-specific code may span Core, Services, UI, App, and Tests. A directory name alone does not establish ownership. Trace call sites and lifecycle wiring before changing a subsystem.

## Runtime and state flow

A common feature flow is:

1. A feature catalog or preference determines whether a capability is enabled and available.
2. App/runtime coordination wires the service and its lifecycle.
3. A service obtains system or application data and owns ongoing state or commands.
4. Support/model code expresses decisions that can be tested independently.
5. UI observes that state and sends user intent back through the owning service.
6. Permission and availability checks guard every relevant entry point, not just the visible button.

Not every feature follows exactly this sequence. Inspect the actual feature before imposing this pattern.

## Important cross-cutting boundaries

### Feature catalog and lifecycle
Feature availability, installation/enablement, preferences, and optional background work are coordinated through the feature catalog/runtime. New optional work should stop when its feature is disabled. Follow existing backup and migration patterns for preferences.

### Preferences and localization
Shared defaults and migrations live in Core. User-facing strings use the repository's localization conventions and locale collection. Update every required locale and its tests; do not hardcode visible copy in views.

### Application identity and coexistence

`Sources/Vorssaint/Core/AppIdentity.swift` owns the installed identity: this
build's bundle identifier, both Sadoyo variants, the neighbour identifiers of
the original Vorssaint, the protected domains, the notification namespace, and
the fan daemon identifier derivation. macOS scopes a notification's click
target, TCC grants, the preferences domain, the login item, a LaunchDaemon label
and the Launch Services registration to the bundle identifier, so the identity
is a cross-cutting boundary, not a resource: `Info.plist` and `build.sh` must
agree with it, and `Tests/AppIdentityTests.swift` fails when they drift. A
bundle identifier change orphans existing TCC grants.

Every feature that enumerates running apps, cleans Library data, or installs a
new bundle checks the identity before acting: Dock click taps, Quit all, the
junk cleaner, the uninstaller, App Updates, the self-updater (which refuses a
bundle whose `CFBundleIdentifier` is not the running app's) and
`build.sh --install`.

### macOS permissions and signing
Permissions are tied to bundle identity and signing state. Release and Developer variants have different bundle identifiers and separate TCC grants. Consult `docs/PERMISSIONS.md`, `CONTRIBUTING.md`, and `docs/TROUBLESHOOTING.md` before changing entitlements, prompts, signing, or permission detection.

### System and hardware integrations
Services wrap macOS APIs, IOKit/CoreAudio/Accessibility/Apple Events and other low-level interfaces as needed. Keep unsafe or privileged operations behind the existing service/helper boundaries. Include model and environment evidence for sensor/hardware changes.

### Now Playing and external applications
The Now Playing adapter and app-side services form a distinct boundary. Player identity, metadata, playback state, and command routing are separate concerns. Do not assume the system-wide Now Playing session represents every active player. Keep player identity stable and route commands to the specific source. Check the adapter and its tests before changing player discovery or control.

### Dynamic Island / Notch
The Dynamic Island spans service state, geometry, compact activity selection, dashboard composition, menu-bar entry points, and individual detail pages. Treat these as one navigation and sizing system: trace the request from its entry point through service routing to the rendered destination. Dynamic content must be measured consistently with the containing window. Preserve independent activity state and metric-detail routing.

With the island on every display, each display owns a persistent island window and answers the pointer on its own display, and the open dashboard is one page in the whole system, drawn by the window of the display whose island was opened. Deliberate hover and click open the page on that display and close it where it was; passive pointer-following keeps its own restrictive gate and belongs to the pointer display choice alone. A page that display's *hover* opened closes when that pointer leaves, at the close delay the person chose; a page its *click* opened stays, as it stays on the island's own strip, and a page another display carries is not this display's to close. Each island answers the same hover preference: the whole dashboard, or the peek of the page's name, drawn at that display's own measure. Never move an island window between displays to change the page, and treat a page whose display has no window as closed. See [0002](docs/decisions/0002-one-island-per-display-one-page.md).

The hover lifecycle is one rule for every island window, stated once in `NotchIslandHover` and asked by `NotchService.syncHoverExitMonitoring` (the island's own window) and `NotchService.syncMirrorExitMonitoring` (each copy's) alike. The rule answers when an island follows the pointer's moves, and it starts at the island's own *entry* - while a hover's deadline is waiting, while a press's suppression is held, while the island carries the open page, and while it shows the page's name. The following may never start from an exit report: an opening grows the island's surface under a pointer that has not moved, and a tracking area replaced under a stationary pointer reports no leaving at all, which is exactly the exit that closes a page. Leaving is measured against the whole interactive surface - `NotchWindowHost.containsHover` asks the window's *destination* bounds, so the expanded panel and a peek are part of the region the pointer is inside, and a pointer that moves from the compact strip into the open page is not leaving. One copy's monitors ask about one copy's island, and a display that goes away takes its deadline, its pointer state and its followed moves with it.

What the closed island shows is answered once, in `NotchService.stripContent` (`NotchStripContent`): the pair of activities, and whether the song is named between the wings. Every window of the island draws that content - `NotchView`, `NotchMirrorView`, and the strips - and no window's answer to the pointer and no display's width picks a different arrangement of it. `interactive` gates what a surface *does* under a pointer (its hover, its play and pause, its naming), never what it shows. Geometry, window frame, pointer state, and which window holds the one open page stay per display. See [0002](docs/decisions/0002-one-island-per-display-one-page.md).

The page's display is carried by the window that draws it, not by the pointer. Each island window names its own display to everything it draws - `NotchMirrorModel.displayID`, `NotchView(hostDisplayID:)`, and `EnvironmentValues.notchPageDisplay` - and every page-opening request names the display of the view that started it: the secondary-click menu, the header's way to the gallery, a dashboard card, a gallery tile, a strip, a page's own control, and the wheel. The island's menu is answered by `islandMenuActions(on:)`, which decides the display where the menu is built, so an item chosen after the pointer has travelled to another display still opens its page on the island the menu was opened on. `NotchService.destinationDisplay` resolves a request in one order: the display named, the display already carrying the page, the island's own. A keyboard move, a global shortcut, a service, or a notification that names no display therefore leaves the page where the person left it, and the primary display takes a page only when its own island was used. A new island view that opens a page must pass `on: pageDisplay`. See [0004](docs/decisions/0004-a-page-opens-on-the-display-whose-island-was-used.md).

The Splash strip on the closed island shows only a throughput the engine is measuring in the reading that answers work in hand. A last batch's rate and the lifetime averages are figures of what the engine has done: they belong to the Complete Dashboard, and are never drawn in the closed island. See [0003](docs/decisions/0003-splash-strip-throughput-only-when-at-work.md).

### Menu bar and app panel
Status items and AppDelegate coordinate multiple presentation destinations. A metric click is not equivalent to opening the general app panel. Preserve the requested metric identity through fallback paths and verify the actual Release interaction where possible.

## Change workflow

Before changing a subsystem:
- Read the file itself. The source is the record; a path, a comment, or a document is a summary of it, not authority. No index, annotation layer, or generated metadata is consulted, and none is required to build, test, or contribute.
- Find its owning service and state model.
- Find all callers and other UI entry points.
- Find tests and any source-generation/build inclusion rules.
- Identify permission, lifecycle, preference, localization, and privacy implications.
- Read `docs/decisions/` when the change touches an ownership, navigation, permission, or data-flow boundary, and update it when such a rule changes.

This guide is intentionally high-level. The implementation and feature-specific documentation remain authoritative.
