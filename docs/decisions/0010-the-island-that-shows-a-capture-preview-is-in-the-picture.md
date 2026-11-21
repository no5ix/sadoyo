# 0010. The island that shows a capture preview is in the picture

- Status: accepted
- Date: 2026-11-21
- Context: Sadoyo's own screenshot tool photographs a display first and then shows
  that photograph frozen behind its selection surface, so what is excluded from a
  capture is visible in the freeze screen itself
  (`ScreenshotSelectionController`: every display is photographed, and each panel
  draws its own display's image). The island has excluded itself from a capture while
  it is the tool taking the capture (issue #2501), and the exclusion is a set of
  window identifiers for the whole capture, never a rule per display. A finished
  preview of a capture was counted as that tool:
  `NotchService.captureVisibleWindowIDs` asked `isCaptureVisible(id:)` beside the
  capture controls, so an island open on a preview dropped its own window from the
  photograph. Because the exclusion names the island's main window, the asymmetry was
  on the screen: a preview drawn by a copy of the island stayed in the freeze screen,
  while the same preview drawn by the island's own display vanished from it, at the
  moment a person was pointing the tool at it. The compact preview page made the
  difference plainer still: its row of actions runs under a physical camera, and at
  the top of an island that draws none, and the page was planned from the preview's
  picture alone, so on the display with a camera the row spent the page's name.
- Decision: A capture preview is a page like any other page. The island that draws one
  is a subject of the picture, not the tool taking it; only the capture controls, the
  chrome a person is aiming with, keep the island's own window out of a capture.
  - `ScreenshotCapturePolicy.islandCaptureWindowIDs` answers the island's windows
    whenever the island shows in captures and is not drawing the controls. Its
    parameter is named for what it decides, `showsCaptureControls`.
  - `NotchService.captureVisibleWindowIDs` passes `captureControls != nil` alone.
    `isCaptureVisible(id:)` keeps its work for the preview's keyboard, pointer and
    collapse, which are per-display questions, and answers no exclusion.
  - The rule stays per window, so it says the same thing on every display: the
    island's own window and every copy's window are in the picture alike, which is
    what [0009](0009-a-capture-preview-opens-on-the-display-it-was-taken-on.md) needs
    of a page a copy draws for its own display.
  - A capture preview's page is planned from its row of actions as well as from its
    picture. `NotchLayout.capturePreviewRowWidth(titleWidth:)` counts the actions the
    toolbar can carry in their 28-point slots, the page's way back and its name;
    `expandedWidth` takes the greater of that row and the preview's picture, inside
    the preset's limit, which stays the limit.
- Consequences: An island open on a capture preview is in the freeze screen, in the
  photograph, in a recording and in a share, on the display that took the capture and
  on every copy. `notchShowInCaptures` off still hides the island everywhere, and
  `screenshotHideVorssaintWindows` still hides the app's windows: neither reads this
  rule.
  - Issue #2501 is untouched: while the area, window, full-screen or colour chooser,
    a countdown, the recorder's controls, or the scrolling capture is up, the island's
    own window stays out of the picture.
  - A preview's page is wider than the 350-point picture by its row, up to the
    compact preset's 480 points; a page width set by hand below the row's measure
    keeps a truncated page name, by the rule that a width set by hand is the island's
    width on every page.
  - The measure counts the most actions the row can carry, so a capture that
    recognises a code, or one with sharing switched off, does not change the island's
    width mid-preview.
  - `Tests/ScreenshotFeatureTests.swift` (`islandCaptureChecks`: the policy per
    window, what `NotchService` protects, the preference off) and
    `Tests/NotchMirrorTests.swift` (`capturePreviewPageGeometryContracts`: equal page
    width on a display with a camera and on one without, the row keeping the page's
    name, the island's shape kept, a width set by hand kept as the limit) state the
    rule, with `Tests/mutation_checks.py` watching the policy's guard.
  - Not verified here, and needing the Release app with Screen Recording granted: the
    real freeze screen on a built-in display with the preview in it, the preview in a
    real photograph and a real recording, and the row as drawn under a real camera.
- Related code: `Sources/Vorssaint/Services/QuickTools/ScreenshotCapturePolicy.swift`
  (`islandCaptureWindowIDs`, `protectedWindowIDs`, `excludedWindowIDs`),
  `Sources/Vorssaint/Services/Notch/NotchService.swift`
  (`captureVisibleWindowIDs`, `protectedWindowIDs`, `islandWindowIDs`,
  `isCaptureVisible(id:)`, `expandedGeometry`),
  `Sources/Vorssaint/Services/Notch/NotchSupport.swift`
  (`capturePreviewPageWidth`, `capturePreviewRowWidth`, `expandedWidth`,
  `headerCameraGap`, `headerTopInset`),
  `Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift`,
  `Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift`,
  `Tests/ScreenshotFeatureTests.swift`, `Tests/NotchMirrorTests.swift`.
- Related decisions: [0002](0002-one-island-per-display-one-page.md) (one island
  window per display, one page),
  [0009](0009-a-capture-preview-opens-on-the-display-it-was-taken-on.md) (a capture
  preview opens on the display it was taken on, which this record completes: the page
  a copy draws is drawn by a window that is in the picture),
  [0008](0008-every-expanded-page-collapses-on-pointer-exit.md).
