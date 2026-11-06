# Architecture Guide

This document is a navigation map of the current repository, not a substitute for reading the implementation. Confirm paths and ownership against the branch being changed.

## Product and platform

Vorssaint is a native macOS application written primarily in Swift and SwiftUI/AppKit. The project targets macOS 14+ and Apple Silicon. It is organized as a source tree assembled by the repository's shell build system; it does not rely on an Xcode project for the authoritative build.

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

### macOS permissions and signing
Permissions are tied to bundle identity and signing state. Release and Developer variants have different bundle identifiers and separate TCC grants. Consult `docs/PERMISSIONS.md`, `CONTRIBUTING.md`, and `docs/TROUBLESHOOTING.md` before changing entitlements, prompts, signing, or permission detection.

### System and hardware integrations
Services wrap macOS APIs, IOKit/CoreAudio/Accessibility/Apple Events and other low-level interfaces as needed. Keep unsafe or privileged operations behind the existing service/helper boundaries. Include model and environment evidence for sensor/hardware changes.

### Now Playing and external applications
The Now Playing adapter and app-side services form a distinct boundary. Player identity, metadata, playback state, and command routing are separate concerns. Do not assume the system-wide Now Playing session represents every active player. Keep player identity stable and route commands to the specific source. Check the adapter and its tests before changing player discovery or control.

### Dynamic Island / Notch
The Dynamic Island spans service state, geometry, compact activity selection, dashboard composition, menu-bar entry points, and individual detail pages. Treat these as one navigation and sizing system: trace the request from its entry point through service routing to the rendered destination. Dynamic content must be measured consistently with the containing window. Preserve independent activity state and metric-detail routing.

### Menu bar and app panel
Status items and AppDelegate coordinate multiple presentation destinations. A metric click is not equivalent to opening the general app panel. Preserve the requested metric identity through fallback paths and verify the actual Release interaction where possible.

## Change workflow

Before changing a subsystem:
- Find its owning service and state model.
- Find all callers and other UI entry points.
- Find tests and any source-generation/build inclusion rules.
- Identify permission, lifecycle, preference, localization, and privacy implications.
- Update architecture decisions when a cross-cutting ownership or data-flow rule changes.

This guide is intentionally high-level. The implementation and feature-specific documentation remain authoritative.
