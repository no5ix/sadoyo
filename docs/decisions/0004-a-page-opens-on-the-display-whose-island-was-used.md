# 0004. A page opens on the display whose island was used

- Status: accepted
- Date: 2026-11-12
- Context: [0002](0002-one-island-per-display-one-page.md) gave every display a persistent
  island window and made the open dashboard one page in the whole system, drawn by the
  window of the display whose island was opened. Hover and click were wired to that rule,
  and they answered correctly. Every other way into a page was not. `open` resolved the
  display as `display ?? displayID`, and the actions started *inside* a page named no
  display: the island's secondary-click menu, the header's way to the gallery, a
  dashboard card, a gallery tile, a strip, a page's own control. So hovering the island
  of display 2 opened its page there, and a right-click on that page's Explorer item
  collapsed display 2 and expanded the primary display with Explorer. The same happened
  for the Complete Dashboard, the gallery, the app panel, a reading's detail and the
  pages reached from a card. A menu is the worst case of the general shape: a
  secondary-click menu is built for the window it was opened on, and its items run later,
  after the pointer has travelled and the app's key window has changed, so the display
  cannot be read from the pointer, the key window, `NSScreen.main`, the primary display,
  or any "display the island is on now" at the moment an item is chosen.

  The same shape came back a second time outside the island's windows. A reading's menu bar
  indicator (RAM, DISK, CPU …) is drawn in the menu bar of every display, and its click
  opened the reading's page with no display named. `destinationDisplay` then answered the
  island's own window — the primary — so clicking RAM in an external display's bar expanded
  the primary's island, and the external whose bar was clicked stayed shut: the mirror image
  of the menu case, with the surface outside the island instead of inside its page.
- Decision: The display a page belongs to is the display whose island the interaction
  happened on, named by the window that drew the thing that was used, and the primary
  display is never an automatic destination.
  - Each island window names its own display to everything it draws.
    `NotchMirrorModel.displayID` is the display a copy's window was built for;
    `NotchView(hostDisplayID:)` is the display the window drawing a page stands on; and
    `\.notchPageDisplay` (`NotchComponents.swift`) carries that answer to every view
    inside the window. A window is built for one display and never moves, so this answer
    is fixed for everything that window draws - including a menu that outlives the pointer.
  - Page-opening entry points take the display: `open(_:…on:)`, `openActivity(_:on:)`,
    `openCountdownEvent(on:)`, `toggleSections(on:)`, `select(_:on:)`,
    `showMetric(_:toggle:on:)`, `openAppPanel(toggle:metric:on:)`,
    `showScratchpad(toggle:on:)`, `openScratchpad(on:)`, `showClipboard(toggle:on:)`,
    `openQuickPanel(toggle:on:)`, `openShelf(toggle:on:)`, `activateQuickAction(_:on:)`
    and the wheel route `handleScroll(_:on:)`. A view passes the display of the window it
    is drawn in; a copy's page therefore opens on that copy.
  - The island's menu is built once per surface by `islandMenuActions(on:)`, which answers
    a `NotchIslandMenu` of closures that each carry the display. The display is decided
    where the menu is built, never where an item is chosen, so a menu opened on display 2
    opens its page on display 2 after the pointer has moved to display 1.
  - A surface that stands in no island window names the display its *click* happened on.
    A reading's menu bar indicator — RAM, DISK, CPU, GPU, network, battery — is drawn in
    the menu bar of every display, so it carries no display of its own and `on: nil` reads
    as "wherever the island is": the island's own window, the primary. The indicator's click
    belongs to the display that bar stands on, and its reading's page opens there.
    `MenuBarDisplayRouting` answers which bar a click is on — the captured click first, the
    status window's reported frame only where there was no click to ask, since a replicated
    menu bar (Sidecar, mirroring, a bar parked off screen) reports the window on another
    display — and it answers nil when neither can say. `NotchService.pageDisplay(forMenuBar:)`
    accepts that display where it has an island window to draw a page
    (`hasIslandWindow(on:)`: the island's own, or a copy's that is on the screen), and names
    no display where it has none, which keeps the page where it is. The primary display
    therefore draws a reading's page only when its own bar, or its own island, was used.
  - One resolution rule, in `destinationDisplay(_:)`: the display the request names, then
    the display already carrying the page, then the island's own. A request that names no
    display - a keyboard move in an open page, a global shortcut, a service, a
    notification - therefore lands on the page where the person left it and never moves it
    to the primary display. The island's own window names its display out loud for its own
    interactions: `toggle()`, the activation button, the screen-edge click, a notice, a
    capture preview and the compact music strip.
  - Unchanged from 0002, and relied on here: one page in the whole system
    (`NotchDisplayExpansion.asking(toOpen:)` answers the display that carried it), no
    island window ever moves, and a page cannot outlive the window that draws it
    (`retireExpansion`).
- Consequences: A page opens where the person was, on every route, and the primary display
  takes a page only when its own island was the one used. Costs, and what they oblige:
  - A new island view that opens a page must read `\.notchPageDisplay` and pass it. Every
    existing page, card, tile, strip and header control does; the rule is mechanical, and
    a view that forgets it opens on the display that already carries the page rather than
    jumping to the primary, so the fault is quiet. The contract test below is what keeps
    the set complete.
  - A new menu bar surface that opens a page must name the display its click landed on, the
    same way, and take the answer through `pageDisplay(forMenuBar:)`. A surface that names
    no display is not wrong on its own — a keyboard move, a global shortcut and a service
    are meant to name none — so the fault is quiet here too: the page stays where it is, or,
    with no page open, lands on the island's own display. That last case is exactly the
    failure this record was written for, and `menuBarDisplayContracts` is what keeps it shut.
  - A request that names no display keeps the page where it is. The pages that follow a
    keyboard (`Command-K`, `Command-Option-<module>`, the section arrows, Escape) are
    therefore bound to the display that carries the page, which is where the keyboard is.
  - `showsOnAllDisplays = false` stays a hard boundary: a display with no copy answers no
    pointer, opens no page, and takes none when it returns.
  - Three-display hover, right-click and pointer travel cannot be proven by unit tests.
    The automated coverage drives the production bodies with display, window and pointer
    doubles: `NotchDestinationContract.pageDisplayContracts` (the menu on a copy, the menu
    after the pointer has travelled, every page route, one page at a time, and a request
    that names no display), `NotchDestinationContract.menuBarDisplayContracts` (a bar click
    on each of three displays, the click outranking a status window that reports another
    display, a display stacked above the primary sharing its x, the display surviving an
    action that runs after the pointer travelled, one page moved across the desk, and a
    display with no island window handed nothing) and `NotchMirrorContract.ownershipContracts`
    (a copy knows its display, an unplug retires the page, a return brings a closed island,
    a switched-off display opens nothing). `MenuPanelRecoveryTests` drives the production
    menu bar route (`AppDelegate.showMetricPanel(for:anchoredTo:)`, `statusScreen(for:)`,
    `statusDisplayID(for:)`) over the same desk, so RAM and DISK clicked in an external
    display's bar are answered by that display, and the panel's anchor follows the same
    click. The real hover, the real menu, the real bar and the real pointer across three
    displays need the Release app.
- Related code: `Sources/Vorssaint/Services/Notch/NotchSupport.swift`
  (`NotchDisplayExpansion`, `NotchIslandMenu`, `NotchMirrorModel.displayID`),
  `Sources/Vorssaint/Services/Notch/NotchService.swift` (`destinationDisplay`,
  `islandMenuActions(on:)`, `open(_:…on:)`, `toggleSections(on:)`, `select(_:on:)`,
  `showMetric(_:toggle:on:)`, `openAppPanel(toggle:metric:on:)`, `expand(on:)`,
  `hasIslandWindow(on:)`, `pageDisplay(forMenuBar:)`, `retireExpansion`),
  `Sources/Vorssaint/App/MenuBarDisplayRouting.swift` (which bar a click is on),
  `Sources/Vorssaint/App/AppDelegate.swift` (`statusDisplayID(for:)`, `statusScreen(for:)`,
  `showMetricPanel(for:anchoredTo:)`),
  `Sources/Vorssaint/UI/Notch/NotchComponents.swift`
  (`EnvironmentValues.notchPageDisplay`), `Sources/Vorssaint/UI/Notch/NotchMirrorView.swift`,
  `Sources/Vorssaint/UI/Notch/NotchView.swift`, and the page, card, tile and strip views
  that pass `on: pageDisplay`. Tests: `Tests/NotchDestinationTests.swift`,
  `Tests/NotchMirrorTests.swift`, `Tests/NotchHoverTests.swift` (`displayExpansionChecks`),
  `Tests/MenuPanelRecoveryTests.swift`, `Tests/generate_sources.py`.
