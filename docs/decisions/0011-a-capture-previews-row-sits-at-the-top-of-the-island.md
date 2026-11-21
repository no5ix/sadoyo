# 0011. A capture preview's row sits at the top of the island, beside a camera where there is one

- Status: accepted
- Date: 2026-11-21
- Context: Decision 0010 kept the island that shows a capture preview in the
  picture, and the compact preview of 0009 gave the page its picture's measure.
  On a built-in display the row of actions was still drawn *below* the island's
  top band, while on a display that draws no camera it sat *at* the top, so the
  same capture read differently on the two displays: on the built-in the page's
  name and its actions were pushed under the camera band, and the title was
  squeezed. The row's placement is decided by `headerTopInset`, which is driven
  by `headerCameraGap`, which needs the row to have room beside the camera. The
  page was planned from its picture alone (350 points), which leaves no room
  beside a camera of 185 points for the row's actions.
- Decision: A capture preview's row is planned for the form the island's top
  takes, and the page is planned from that row.
  - Where the island draws a camera, the row wraps it: the page's way back and
    its name lead, the actions that fit trail, and what does not fit rides in
    the row's own menu. The page's width is planned from the camera, its
    clearance and both sides (`NotchLayout.capturePreviewBandWidth`), never
    wider than the display's page width, and a page width set by hand stays the
    limit.
  - Where the island draws no camera, the row is the whole of the top and shows
    every action, exactly as the compact preview has always done. The page is
    planned from the whole row (`NotchLayout.capturePreviewRowWidth`).
  - The actions a side keeps are counted from the end of the row, where the
    capture is given somewhere to go - share, pin, editor - so the menu holds
    the deleting and the reading. The count is measured from the island's own
    row (`NotchBand`) of the display that draws the page
    (`presentationGeometry`), so a page handed to another display's island is
    counted for that display, and the row answers live as the page moves.
  - Only capture *controls* keep the island's own window out of a capture
    (decision 0010). Editing keeps its full-width header; a preview asks for a
    full-width header only where the island draws no camera.
  - The row's menu is labelled with the words the tool already uses for more
    tools (`ScreenshotFeatureStrings.moreTools`, localized in every language),
    and every action stays reachable by keyboard, whose shortcuts read the whole
    set whether the button is in the row or in the menu.
- Consequences: One row of actions reads the same on every display: at the top
  of the island. The island is a little wider for a preview on a notched display
  (its camera plus two planned sides, 541 points for the built-in at its 185
  point camera) and no wider than the preset's page. A narrow preset (compact,
  480) is the limit: the row keeps its top placement and its four slots, and the
  page's name spends first. The row's width does not change mid-preview as the
  QR, Copy text and share-link controls appear, because the full-row measure
  counts all nine slots. The menu is a new control in the island's row, and the
  screenshot suite's fixtures now carry an island that answers for a side's
  width.
- Related code: `Sources/Vorssaint/Services/Notch/NotchSupport.swift`
  (`capturePreviewBandWidth`, `capturePreviewBandSideRoom`,
  `capturePreviewRowWidth`, `capturePreviewTrailingActions`, `NotchBand.side`,
  `headerCameraGap`, `headerTopInset`, `expandedWidth`);
  `Sources/Vorssaint/Services/Notch/NotchService.swift` (`expandedGeometry`,
  `capturePreviewTrailingActions`, `presentationGeometry`);
  `Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift`
  (`islandRow`, `rowSlots`, `keptSlots`, `overflowSlots`, `rowOverflowMenu`).
  Tests: `Tests/NotchMirrorTests.swift`
  (`capturePreviewPageGeometryContracts`), `Tests/ScreenshotOCRControlTests.swift`
  (the row beside a camera, and across a top without one),
  `Tests/ScreenshotFeatureTests.swift` (the shape of both rules). The live
  layout was photographed on a 16-inch MacBook Pro (built-in 1728×1117, camera
  185 points, `spacious` preset) beside two 1920×1080 displays, with a capture
  taken on each display: on the built-in the row sits at the island's top split
  around the camera with its menu; on the external display the row spans the top
  with every action.
- Related: `0009. A capture preview opens on the display it was taken on`,
  `0010. The island that shows a capture preview is in the picture`.
