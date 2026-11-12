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
    copy's peek back: the page is one.
    One rule governs the deadlines of every island, and it is the island's own rule that
    has always closed the island on its own display: **a deadline an island started is
    kept until the pointer crosses the boundary** (`NotchIslandHover`, asked of the
    island's own window by `hover(_:)` and of every copy by `mirrorHover(_:entered:)`).
    A report of a presence the island already has is answered by the pointer's place, and
    it keeps the deadline that is already waiting; only a crossing takes a work item back.
    This is not a detail. A leaving is told more than once - the window's tracking area,
    then the moves that carry the pointer away, and a page that grew under a resting
    pointer replaces the area under it - and a copy that took its waiting work back on
    every report cancelled the close its own leaving had asked for before the person's
    close delay was out, and then declined to ask again because it was already outside.
    The page a copy's hover opened therefore never closed, on the display that opened it,
    while the island's own window - which keeps its deadline - opened and closed. Measured
    on three displays with the Release app: a copy's window reports its entering *and* its
    leaving (`mouseEntered`, `mouseExited` both arrive), the close is armed at the leaving,
    and the next pointer report cancelled it.
    The following starts at the
    island's own *entry* - while its hover waits out the chosen delay, and while a press's
    suppression is held - and runs while it carries the open page or the page's name. It
    never starts from a report of a leaving, because the opening that entry waits out
    grows the island's surface under a pointer that has not moved, and a window grown
    under a stationary pointer is the one that reports no leaving: the exit that closes
    the page is the exit least likely to arrive. It stops when there is nothing left to
    close.
  - The pointer's moves are read of every island at once: `syncPointerWatching` arms
    **one pair of monitors for all the copies** - as the island's own window has its own
    pair - while a copy has something for the pointer to settle (`watchesMirrors`, by the
    same `followsPointer` rule), and `sweepPointer` asks the pointer's place of each
    window, so a pointer reaching an island is that island's entry and leaving its whole
    region is its exit - answered only when it changes, so no move restarts a deadline,
    and a pointer that comes back takes the leaving's close back. One pair, not one per
    copy: a move is answered by every monitor registered for it, so a per-copy pair made
    each move answer the same island twice, which is the double answer that took a close
    back. The pointer is asked because a window's report is the thing that goes missing -
    the moves a window receives stop when the pointer crosses the transparent margin,
    passes into another display, or is handed to a tracking area replaced under it; the
    island's own window is already read from the pointer wherever its reports are known to
    fail (out of sight at rest, its page open), so the entry a copy cannot hear is never
    the door to its island, and a copy's own entering is what arms the watching.
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
  hover, their peek, and the moves followed for them (`closeMirrors`, `syncMirrors`,
  `retireExpansion`, `collapse`, `syncPointerWatching`), and the behaviour of
  `notchDisplay = all` changes for anyone who relied on the island following the pointer
  across displays - that is what `.pointer` is for. The hover lifecycle every island
  answers, and the content every window draws, are one rule each and are tested as such:
  `hoverCollapseChecks`, `hoverLifecycleContracts`, `hoverParityChecks` and
  `pointerSweepChecks` drive the production bodies through three displays - the reports
  of one leaving in the order AppKit tells them, an open panel the pointer moves inside,
  a crossing from one display to the next, a display unplugged mid-hover and one that
  returns, and the pointer's place read in each display's own frame. A fixture that
  reports a pointer's move to one monitor set only hides the double answer that broke the
  copies, so a move is reported as every island hears it and the overlapping reports of
  one leaving are told on purpose. What remains outside the fixtures is the physical
  interaction on three
  displays, which needs the Release app. The same goes for a copy whose surface grows
  under a pointer that has not moved (`rearmMirrorHoverOpen`): no fixture draws a copy at
  a measure that grows under a resting pointer, so the answer it gives to the person's
  peek choice is seen in the app.
- Related code: `Sources/Vorssaint/Services/Notch/NotchSupport.swift`
  (`NotchDisplayExpansion`, `NotchIslandHover`, `NotchStripContent`, `NotchMirrorModel`,
  `NotchMirrorModel.peeking`),
  `Sources/Vorssaint/Services/Notch/NotchService.swift`
  (`syncMirrors`, `makeMirror`, `mirrorHover`, `scheduleMirrorOpen`, `scheduleMirrorPeek`,
  `scheduleMirrorClose`, `syncHoverExitMonitoring`, `mirrorFollowsPointer`,
  `watchesMirrors`, `sweepPointer`, `syncPointerWatching`, `removePointerWatchMonitors`,
  `carriesPage`, `mirrorHoverExpands`, `rearmMirrorHoverOpen`,
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
  `hoverCollapseChecks`, `hoverLifecycleContracts`, `pointerSweepChecks`,
  `stripContentContracts`),
  `Tests/NotchHoverTests.swift` (`displayExpansionChecks`, `hoverParityChecks`),
  `Tests/NotchActivityTests.swift` (`displayExpansionChecks`), `Tests/generate_sources.py`.
