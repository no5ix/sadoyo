# Source map

A map of where a change usually belongs. It names real files, so an agent can
find the existing owner of a behaviour instead of writing a new one.
[CONTRIBUTING.md](../CONTRIBUTING.md) keeps the rules; this file is the index.

## Entry point and app shell

| Path | Role |
| --- | --- |
| `Sources/Vorssaint/main.swift` | Command-line modes (`--selftest`, `--sensors`, `--uninstall`, backup commands, the dev-only presentation probes), then `NSApplication` + `AppDelegate`. |
| `App/AppDelegate.swift` | Lifecycle, the menu-bar status items, the popover panel, and the choice of island or popover for a click. |
| `App/StatusItemController.swift`, `App/MenuBarRenderer.swift` | Menu-bar icons and text: what each metric shows and where a click goes. |
| `App/FeatureRuntime.swift` | Brings feature services to life or tears them down as availability changes. |
| `Core/FeatureCatalog.swift` | `AppFeature`: every feature, its availability key and its permission needs. Above each feature's own enable switch. |
| `Core/Defaults.swift` | `DefaultsKey`, `Defaults.registeredDefaults` (registered at launch). |
| `Core/Localization.swift`, `Core/Localizations/`, `Core/*Strings.swift` | Strings. `FeatureStrings.<area>(language)` reads a catalog; every `AppLanguage.allCases` locale must be complete. |
| `Core/SettingsBackupSupport.swift`, `Services/SettingsBackup.swift` | Which preferences travel in a backup, and the backup file itself. |
| `Support/` | Diagnostics: `SelfTest.swift`, `Uninstaller.swift`, and the dev-only `NotchPresentationProbe.swift` / `NotchMediaPresentationProbe.swift`. |

## A feature's usual three parts

- `Services/<Area>/<Feature>Service.swift` — the live object: state, timers,
  permission checks, `ObservableObject` for its views.
- `Services/<Area>/<Feature>Support.swift` — the decisions that need no live
  state: preference reading, formatting, geometry, selection rules. It takes a
  `UserDefaults` parameter (defaulting to `.standard`) so a test can hand it a
  disposable domain.
- `UI/<Area>/…` — SwiftUI/AppKit views only; keep decisions out of them so they
  stay testable.

`Tests/<Feature>FeatureTests.swift` holds the behaviour contracts that go with them.

## The Dynamic Island

The island is called "notch" in the code.

| Path | Role |
| --- | --- |
| `Services/Notch/NotchService.swift` | All presentation state and the actions that change it: `open`, `collapse`, `select`, `toggleSections`, `showMetric`, notices, hover, displays. Views observe it; they do not own island state. |
| `Services/Notch/NotchSupport.swift` | `NotchModule` (the sections), `NotchLayout` (every measured height), `NotchGeometry` (the island's sizes on a display), the controls, quick buttons and activity choices. |
| `Services/Notch/NotchIslandSections.swift` | The stacked surface: which parts the open island shows and in what order — Now Playing, a running timer, one monitoring detail, then Explore. |
| `Services/Notch/NotchWindowHost.swift` | The panel, its backdrop, silhouette and motion. |
| `Services/Notch/Notch<Area>Support.swift` / `Notch<Area>Service.swift` | One per island feature: timer, music, calendar, downloads, agents, watch, lyrics, clipboard, files, lock screen, accessories. |
| `UI/Notch/NotchView.swift` | The island's surface: compact strip, notice, or the open page. It draws the stacked parts and the top row. |
| `UI/Notch/NotchSectionsView.swift` | The Explore gallery: tiles, search, row paging. |
| `UI/Notch/NotchMusicView.swift`, `NotchTimerView.swift`, `NotchCapsuleViews.swift`, … | The pages and compact strips. A page hands the island's top row its controls with `.notchBand`. |
| `UI/Notch/NotchComponents.swift` | Shared island buttons, meters, sliders, the band preference. |

Sizes are computed twice on purpose: `NotchGeometry` decides the island's frame,
and the page lays itself out inside it. Change both sides of a measurement
together, or the page and its silhouette disagree.

## Menu-bar metrics, the panel and the island

- `Services/SystemMonitor/SystemMonitor.swift` samples everything (CPU, GPU,
  memory, disk, network, power, fans, devices) on one plan: `currentPlan` reads
  what each visible surface asked for. `setNotchDetailNeeds` and
  `setMenuPanelNeeds` are how a surface says "keep reading this".
- `Services/Metrics/` holds the samplers and the formatting (`MetricFormat`).
  Sampling intervals stay in `MonitorSamplingPolicy`.
- `UI/MenuPanel/MetricDetailView.swift` owns `MetricDetailKind`, maps a
  `MenuBarMetric` to its detail, and draws the detail used by both the popover
  panel and the island.
- `UI/MenuPanel/MenuPanelView.swift` is the popover panel the menu bar opens when
  the island is off; `UI/MenuBarMetricsPreview.swift` is the Settings preview.
- A click on a metric indicator reaches `AppDelegate.showMetricPanel`, which
  routes to `NotchService.showMetric` when the island is on, and to the popover
  otherwise. The detail is a part of the island's stack, so it shows with the
  running activities and Explore rather than instead of them.

## Tests

- `Tests/TestSuite.swift` — the assertions; every check has a sentence naming the
  behaviour it protects.
- `Tests/MetricsTests.swift` — `@main`, the named groups behind `--list-tests`
  and `--test-suite=<name>`.
- The test executable compiles `Tests/*.swift` plus a *selected* list of
  production files (`TEST_SOURCES` in `build.sh`). A new pure-support file that
  tests need has to be added there.
- `Tests/generate_sources.py` recompiles chosen production methods verbatim
  against fixtures (`build/generated-tests/`). The declaration text is a
  contract: if a method moves or changes shape, generation fails and both sides
  need updating.
- `Tests/*Contract*.swift` name that style. Preference tests use a throwaway
  `UserDefaults(suiteName:)` domain, never the real one.

## Build

`./build.sh` (release, what CI checks), `--dev` (a separate
`Vorssaint (Developer).app` with its own preferences, permissions and probe
modes), `--install`, `--test`, `--test-suite=`, `--list-tests`. `Package.swift`
is for editor indexing only; it does not bundle or sign.
