# 0013. The page the island draws is the page it is sized for

- Status: accepted
- Date: 2026-11-22
- Context: The island's one page lies under every page the island opens, so the way
  back from a section, a detail, the gallery - and from a capture preview - is one
  click to the page a person started from (`NotchService.showDashboard`). Going
  there does not close the page it came from: a capture preview stays open behind
  the dashboard, because the preview is the page the display was opened on
  ([0009](0009-a-capture-preview-opens-on-the-display-it-was-taken-on.md)) and the
  dashboard is the page under it ([0002](0002-one-island-per-display-one-page.md)).
  [0010](0010-the-island-that-shows-a-capture-preview-is-in-the-picture.md) plans a
  preview's page from its picture (350 points) and its row of actions, and the
  island takes that measure as its width. That measure was applied whenever a
  preview was open, so the page on screen after the way back - the dashboard - was
  measured, laid out and drawn at the preview's width: on a built-in display whose
  preset offers 560 points the page came back 519 points wide, its cards narrower
  and its content width 463 rather than 504. A reading's detail, the app panel and
  the gallery were already excluded by the same reasoning; the dashboard was not.
- Decision: The island is sized for the page it draws, and for nothing behind it.
  `NotchService.expandedGeometry` keeps the two facts apart:
  - `capturePageIsOpen` - the island holds a preview page, with no detail, app panel
    or gallery in front of it - decides the shape of the header's row, which is the
    row the island draws: it wraps a camera where the island draws one and spans the
    whole top where it draws none ([0011](0011-a-capture-previews-row-sits-at-the-top-of-the-island.md)).
  - `showsCapturePreviewPage` - a preview page is open **and** the island's one page
    is not on screen - alone decides the preview's measure, `capturePreviewPageWidth`
    and `capturePreviewRowWidth`, and so the island's width.
  The preview's page is unchanged: on the display its capture was taken on it stays
  as wide as its picture and its row, inside the preset and inside a width set by
  hand, which stay the limit.
- Consequences: The way back from a preview returns the page a person is looking at
  at its own width, with its own row beside the camera, and the preview behind it
  sizes nothing. A page's height already followed the page on screen (the dashboard
  measures its own sections), so width and height now answer the same question.
  - A preview left open behind the page is still open: its pointer, its keyboard and
    its dismissal are untouched by this, only its measure.
  - The contract that read a preview's page as a full row below the camera
    (`Tests/NotchPresentationRefreshTests.swift`, red on `main`) states 0011's rule
    now: the row wraps the camera and the camera keeps its place as the island's door.
- Testing: `Tests/NotchPresentationRefreshTests.swift` measures the page a preview is
  behind against the same page with no preview open, on a display that draws no
  camera where a preview's row is the whole of the island's top and so is planned
  short of the preset's width in every language, and keeps the row beside a camera on
  a display that draws one. `Tests/NotchMirrorTests.swift`
  (`capturePreviewPageGeometryContracts`) keeps the preview's own measure and the
  header rule.
  - Measured on the Release app (`build/stage/Sadoyo.app`, `com.sadoyo.app`, macOS on
    Apple M4 Max; built-in 1728x1117 with a camera, two external 1920x1080): the
    dashboard 584,0 560x364; a capture preview 604,0 519x278; the dashboard after the
    way back 584,0 560x364 - before this change the last was 604,0 519 wide.
- Related code: `Sources/Vorssaint/Services/Notch/NotchService.swift`
  (`expandedGeometry`, `showDashboard`, `showsDashboard`),
  `Sources/Vorssaint/Services/Notch/NotchSupport.swift`
  (`capturePreviewPageWidth`, `capturePreviewRowWidth`, `expandedWidth`,
  `dashboardSize`, `dashboardContentWidth` - through `NotchService`).
- Related decisions: [0002](0002-one-island-per-display-one-page.md),
  [0009](0009-a-capture-preview-opens-on-the-display-it-was-taken-on.md),
  [0010](0010-the-island-that-shows-a-capture-preview-is-in-the-picture.md),
  [0011](0011-a-capture-previews-row-sits-at-the-top-of-the-island.md),
  [0008](0008-every-expanded-page-collapses-on-pointer-exit.md).
