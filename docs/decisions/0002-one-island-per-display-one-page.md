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
    windows, an island follows the pointer's moves by one rule, stated once in
    `NotchIslandHover` and asked of the island's own window and of every copy's alike
    (`syncHoverExitMonitoring`, `syncMirrorExitMonitoring`). The following starts at the
    island's own *entry* - while its hover waits out the chosen delay, and while a press's
    suppression is held - and runs while it carries the open page or the page's name. It
    never starts from a report of a leaving, because the opening that entry waits out
    grows the island's surface under a pointer that has not moved, and a window grown
    under a stationary pointer is the one that reports no leaving: the exit that closes
    the page is the exit least likely to arrive. It stops when there is nothing left to
    close, and one copy's monitors ask about one copy's island only.
  - Leaving is measured against the whole interactive region, not the compact strip:
    `NotchWindowHost.containsHover` asks a window's *destination* bounds, so the open page
    and a peek are part of the region the pointer is inside. A pointer that moves from the
    closed strip into the page a hover opened is inside, and the page stays; it closes
    when the pointer leaves the whole of it. Every display answers this the same, and no
    display is given a collapse timer of its own.
  - The closed island's content is one answer, in `NotchService.stripContent`
    (`NotchStripContent`): the pair of activities, and whether the song is named between
    the wings. Every window of the island draws that content, so the strip a person sees
    is the same content on every display, and `interactive` gates only what a surface does
    under a pointer - its hover, its play and pause, its naming - never what it shows. A
    copy that picked its own arrangement, the song's solo layout where the island shows
    the pair, is a second island; the layout question is answered once, from the island's
    own surface.
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
  across displays - that is what `.pointer` is for. The hover lifecycle every island
  answers, and the content every window draws, are one rule each and are tested as such:
  `hoverLifecycleContracts` and `hoverParityChecks` drive the production bodies through
  three displays, a pointer that reports only its entry, and an open panel the pointer
  moves inside. What remains outside the fixtures is the physical interaction on three
  displays, which needs the Release app. The same goes for a copy whose surface grows
  under a pointer that has not moved (`rearmMirrorHoverOpen`): no fixture draws a copy at
  a measure that grows under a resting pointer, so the answer it gives to the person's
  peek choice is seen in the app.
- Related code: `Sources/Vorssaint/Services/Notch/NotchSupport.swift`
  (`NotchDisplayExpansion`, `NotchIslandHover`, `NotchStripContent`, `NotchMirrorModel`,
  `NotchMirrorModel.peeking`),
  `Sources/Vorssaint/Services/Notch/NotchService.swift`
  (`syncMirrors`, `makeMirror`, `mirrorHover`, `scheduleMirrorOpen`, `scheduleMirrorPeek`,
  `scheduleMirrorClose`, `syncHoverExitMonitoring`, `syncMirrorExitMonitoring`,
  `removeMirrorExitMonitors`, `carriesPage`, `mirrorHoverExpands`, `rearmMirrorHoverOpen`,
  `stripContent`, `mirrorWillPress`, `mirrorWasClicked`, `expand(on:)`, `presentsExpansion(on:)`,
  `retireExpansion`, `presentationGeometry`, `expansionHost`, `followsPointer`),
  `Sources/Vorssaint/Services/Notch/NotchWindowHost.swift` (`containsHover`, whose answer
  is the destination bounds of one window - the whole region a pointer is inside),
  `Sources/Vorssaint/UI/Notch/NotchMirrorView.swift`, `Sources/Vorssaint/UI/Notch/NotchView.swift`
  (the island's own and a copy's shared `NotchPeekSurface`),
  `Sources/Vorssaint/UI/Notch/NotchMusicStrip.swift` and
  `Sources/Vorssaint/UI/Notch/NotchCapsuleViews.swift` (the closed strips, which draw
  `NotchStripContent` on every display).
  Tests: `Tests/NotchMirrorTests.swift` (`displayExpansionChecks`, `pointerExitContracts`,
  `hoverLifecycleContracts`, `stripContentContracts`),
  `Tests/NotchHoverTests.swift` (`displayExpansionChecks`, `hoverParityChecks`),
  `Tests/NotchActivityTests.swift` (`displayExpansionChecks`), `Tests/generate_sources.py`.
