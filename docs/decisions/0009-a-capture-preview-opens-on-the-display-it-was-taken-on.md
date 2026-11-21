# 0009. A capture preview opens on the display it was taken on

- Status: accepted
- Date: 2026-11-21
- Context: With the island on every display, a screenshot taken on an external display
  expanded the island of the primary display: a person working on display 2 who captures
  on display 1 got the page, and the preview of the capture, on the screen that was not
  involved. `NotchService.presentCapture` named `displayID` — the island's own display —
  which is what [0004](0004-a-page-opens-on-the-display-whose-island-was-used.md) records
  for "a capture preview". A finished capture is a surface that stands in no island
  window, the way a reading's menu bar indicator does in 0004: it carries no display of
  its own, and asking the island's own window for it answers the primary. It does,
  however, record where it happened. `ScreenshotSelectionController.Capture.anchorRect`
  is the captured area in Cocoa global coordinates — the selected region, a picked
  window's frame, a full screen's frame, a scrolling region — and the preview's own
  placement already reads it (`quickPreviewVisibleFrame`).
- Decision: A capture preview opens on the island of the display the capture was taken
  on, where that display has an island to draw it, and on the island's own display
  everywhere else.
  - One routing rule, `NotchSupport.capturePageDisplay(requested:islandDisplay:displaysWithIsland:)`:
    the requested display where it is among the displays that have an island window now
    (the island's own, plus every copy on the screen — the set `hasIslandWindow(on:)`
    answers), and the island's own display where it is not, where none was asked for, and
    where the island has no display at all.
  - One reading of the capture, `ScreenshotSupport.captureDisplayID(anchor:pointer:screens:)`:
    the screen holding the captured area, the screen holding most of it when a region
    crosses displays, and the pointer's screen when a region splits evenly — the same
    reading `quickPreviewVisibleFrame` makes, so the island and the floating preview agree.
    An anchor that names no area, which is what a clipboard picture and a picture opened
    from the shelf carry, names no display, and nothing downstream guesses one.
  - `presentCapture(…on:)` hands that display to `open(.captures, …on:)`, and the page
    needs no machinery of its own. The display that owns the page is drawn by
    `expansionHost`: a copy's window draws the preview as the page of its own display, at
    that display's measure (`presentationGeometry`), and the other displays keep their
    closed strips. What belongs to the window that draws a page follows it: the preview's
    shortcuts (`capturePresentationWindow`, which the preview's key monitor resolves again
    at every key press, because a page — preview and all — can be handed to another
    display's window while the preview stays open),
    its clicks (`ownsWindow` counts the window drawing the page beside the island's own),
    and its pointer (`mirrorHover(_:entered:)` answers the preview its copy draws, and
    `hover(_:)` stops answering a preview a copy has taken).
  - The fallbacks are the ones already in place, and no capture is ever left undrawn. A
    display with no island of its own — full screen, hidden until the pointer, copies
    switched off, any one-display choice — and a capture that names no display fall to the
    island's own display. A preview whose window goes away with its display goes to the
    floating panel through its own `fallback`, as it does when the island stops routing
    captures (`retireExpansion`).
- Consequences: The island that opens for a capture is the island beside the picture that
  was taken, and every other display keeps its closed strip.
  - `.all` is the only mode with copies, so a capture on any other display choice keeps
    the old behaviour exactly: `hasIslandWindow(on:)` answers false for a display with no
    copy of its own, and the island's own display draws the preview as it always did.
  - The preview is one page in one window, as 0002 and 0004 require. No second preview is
    drawn per display, no island window moves, and a preview whose display loses its
    window is a preview closed, not a preview handed to the primary.
  - A new capture surface that wants its island to open must name the display it happened
    on the same way. A surface that names no display is not wrong — clipboard and shelf
    pictures are meant to name none — so the fault is quiet: the preview lands on the
    island's own display, which is the behaviour this record replaced.
  - `Tests/NotchTests.swift` (`capturePageDisplay` routing: the capture's own display, the
    display with no island of its own, the capture that names none, no island anywhere)
    and `Tests/ScreenshotFeatureTests.swift` (`captureDisplayID`: three displays, negative
    coordinates, a full screen, a region crossing displays, an even split decided by the
    pointer, an anchor that names no area, a display with no identifier) state the rule.
    The real capture on a real external display, its keyboard, its hover and its share
    sheet on that display's copy, need the Release app.
- Related code: `Sources/Vorssaint/Services/Notch/NotchSupport.swift`
  (`capturePageDisplay`), `Sources/Vorssaint/Services/Notch/NotchService.swift`
  (`presentCapture(…on:)`, `islandWindowDisplays`, `capturePreviewOnCopy`,
  `capturePreviewPointerInside`, `capturePresentationWindow`, `ownsWindow`,
  `mirrorHover(_:entered:)`, `hover(_:)`, `retireExpansion`, `expansionHost`,
  `hasIslandWindow(on:)`), `Sources/Vorssaint/Services/QuickTools/ScreenshotSupport.swift`
  (`captureDisplayID`), `Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift`,
  `Sources/Vorssaint/UI/Notch/NotchMirrorView.swift`,
  `Tests/NotchTests.swift`, `Tests/ScreenshotFeatureTests.swift`.
- Related decisions: [0002](0002-one-island-per-display-one-page.md) (one island window
  per display, one page), [0004](0004-a-page-opens-on-the-display-whose-island-was-used.md)
  (a page opens on the display whose island was used, refined here for the surface that
  stands in no island window and carries its display in its own geometry),
  [0008](0008-every-expanded-page-collapses-on-pointer-exit.md).
