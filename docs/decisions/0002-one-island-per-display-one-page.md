# 0002. One island per display, one page in the whole system

- Status: accepted
- Date: 2026-11-12
- Context: With `notchDisplay = all` the island had a single window, and the copies on
  the other displays were passive pictures: `.allowsHitTesting(false)`, no hover area,
  and a click that ran `bringIsland(to:)`, which collapsed the island, waited for it to
  settle, checked `canFollowPointer`, and *moved the window* to the clicked display
  before opening it. Two things followed. A timer-up notice, or a song waiting on its
  `New Track` notice, put a `notice` / `heldMusic` in the island, `canFollowPointer`
  answered false, and the click did nothing at all: the second and third displays
  expanded nothing for the first seconds after a countdown ended or a track changed.
  And a picture is not an island: the pointer resting on a copy opened nothing, so only
  the primary display behaved like the island.
- Decision: Every display the island shows on owns a persistent island window, and the
  open dashboard is one page in the whole system, drawn by the window of the display
  whose island was opened.
  - `NotchDisplayExpansion` (in `NotchSupport.swift`) holds the owning display id.
    `asking(toOpen:)` answers the display that carried the page, so the rule that closes
    the previous page is stated once and no caller can open a second beside it.
  - A copy is an interactive host: `syncMirrors()` gives each copy its own activation
    area, its own hover handler (`mirrorHover(_:entered:)`), its own `NotchHoverState`
    and its own scheduled opening, and presents the page on the owning copy at that
    display's own measure (`presentationGeometry`, `expandedGeometry`, `expandedSize`).
    `pointerOverMirror(_:)` reads the pointer from that copy's window, so a pointer on
    one display is never taken for a pointer on another.
  - Opening is asked with `open(_:…on:)`, and `expand(on:)` is the deliberate act: a
    click, or a hover that stayed past the chosen delay. It clears nothing by force and
    moves nothing: the copy keeps its display and draws the page there.
    `bringIsland(to:)` is gone, and no window changes display.
  - A copy answers the pointer's leaving as the island answers its own. A page a copy's
    *hover* opened closes, at the person's close delay, when that copy's pointer leaves;
    a page its *click* opened stays, as it stays on the island's own strip; and a page
    another display carries is not this copy's to close. The same choice the island reads
    (`notchHoverExpands`) is read for the copy: the whole dashboard, or the peek of the
    page's name - which a copy draws at its own display's measure, keeps as its own door,
    and takes back when the pointer leaves. A surface that grew under a pointer that has
    not moved is given the same answer by this same choice (`rearmMirrorHoverOpen`).
    A peek is a copy's own state, so one copy's
    pointer does not peek another display's island, and a page opened anywhere takes a
    copy's peek back: the page is one. Because AppKit can report no exit at all for these
    windows, a copy starts following the pointer's moves when it reports a leaving that can
    close something - the exit AppKit drops, and the pointer that slips back unreported, are
    both covered from there - and it stops when it has nothing left to close
    (`syncMirrorExitMonitoring`), as the island follows them for its own.
  - Deliberate and passive are separate rules on purpose. The island's own news is no
    obstruction to a deliberate act, so `expand(on:)` goes past a `notice` (a countdown
    that has ended keeps ringing) and past `heldMusic` (a song keeps its own dismissal).
    Passive pointer-following keeps the old, restrictive `canFollowPointer`, and
    `followsPointer` is now the `.pointer` choice alone: with `all` nothing is followed
    from one display to another, because each display already has an island.
  - A page cannot outlive the window that draws it. `retireExpansion()` closes the page
    when the owning display's window is gone - copies switched off, display unplugged,
    island withdrawn - and never hands the page to another display.
- Consequences: The delay, the suppression a resize leaves behind, and the pointer's
  place are per display, so a pointer moving from display 2 to 3 opens 3 and opens
  nothing on 2. `NotchMirrorModel.expanded` says which copy draws the page, and
  `NotchMirrorView` draws the real page (`NotchView(service:presentsPage:pageSurfaceSize:)`)
  with hit testing on, and the closed strip with hit testing off. Costs: copies are now
  real windows that take focus (`acceptsKeyFocus`) and must be torn down with their
  hover, their peek, and the moves they follow (`closeMirrors`, `syncMirrors`,
  `retireExpansion`, `collapse`, `removeMirrorExitMonitors`), and the behaviour of
  `notchDisplay = all` changes for anyone who relied on the island following the pointer
  across displays - that is what `.pointer` is for. The three-display interaction cannot
  be proven by unit tests: automated coverage drives the production bodies with window,
  display, Spaces and pointer doubles, and the real hover on three displays needs the
  Release app. The same goes for a copy whose surface grows under a pointer that has not
  moved (`rearmMirrorHoverOpen`): no fixture draws a copy at a measure that grows under a
  resting pointer, so the answer it gives to the person's peek choice is seen in the app.
- Related code: `Sources/Vorssaint/Services/Notch/NotchSupport.swift`
  (`NotchDisplayExpansion`, `NotchMirrorModel`, `NotchMirrorModel.peeking`),
  `Sources/Vorssaint/Services/Notch/NotchService.swift`
  (`syncMirrors`, `makeMirror`, `mirrorHover`, `scheduleMirrorOpen`, `scheduleMirrorPeek`,
  `scheduleMirrorClose`, `syncMirrorExitMonitoring`, `removeMirrorExitMonitors`,
  `carriesPage`, `mirrorHoverExpands`, `rearmMirrorHoverOpen`,
  `mirrorWillPress`, `mirrorWasClicked`, `expand(on:)`, `presentsExpansion(on:)`,
  `retireExpansion`, `presentationGeometry`, `expansionHost`, `followsPointer`),
  `Sources/Vorssaint/UI/Notch/NotchMirrorView.swift`, `Sources/Vorssaint/UI/Notch/NotchView.swift`
  (the island's own and a copy's shared `NotchPeekSurface`).
  Tests: `Tests/NotchMirrorTests.swift` (`displayExpansionChecks`, `pointerExitContracts`),
  `Tests/NotchHoverTests.swift` (`displayExpansionChecks`), `Tests/NotchActivityTests.swift`
  (`displayExpansionChecks`), `Tests/generate_sources.py`.
