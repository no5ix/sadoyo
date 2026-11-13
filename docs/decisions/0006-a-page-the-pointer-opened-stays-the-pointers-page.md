# 0006. A page the pointer opened stays the pointer's page

- Status: accepted
- Date: 2026-11-13
- Affects: `NotchService.open`, `NotchService.retireExpansion`, `NotchSupport.openedByHover`,
  `NotchSupport.closesOnPointerExit`, the island's hover and every copy's hover, the pin

## Context

The island opens two ways, and they have always had different endings: a page the
pointer's *hover* opened closes when the pointer leaves the whole interactive
surface, at the close delay the person chose, and a page a *click* on the strip
opened stays, as the strip it was opened from stays ([0002](0002-one-island-per-display-one-page.md)).
`NotchSupport.closesOnPointerExit(expanded:peeking:openedByHover:)` is the answer
the island's hover (`NotchService.hover(_:)`), every copy's hover
(`mirrorHover(_:entered:)`) and both pointer-following rules read, and
`NotchService.openedByHover` is the one fact that carries the distinction.

Every page inside the island is opened by the same entry point as the island
itself - `NotchService.open` - and that entry point answered *why the island is
open* from `takeFocus`, which answers a different question: who is handed the
keyboard. A reading's card (RAM, DISK, CPU, network, battery, fans), a gallery
tile, Explorer, the app panel, the whole dashboard, the pad, the clipboard, the
shelf and the quick panel are each handed the keyboard, so the first card tapped
in a hover-opened page rewrote the reason for the opening to "a click opened it".
`closesOnPointerExit` then answered false, the island armed no close, both
following rules stopped watching the pointer, and the island stayed grown after
the pointer left the screen - on the island's own display, and on every copy's.
Opening a page had become an implicit Keep Open, on the route with the most
traffic and on the two cards the report named.

The same shape came back smaller in `retireExpansion()`. A page cannot outlive the
window that draws it ([0002](0002-one-island-per-display-one-page.md)), so a
display unplugged while its copy drew the page retires the page. `collapse()`
clears the state that belongs to a page; `retireExpansion()` closed the page
without clearing any of it. A page pinned on the display that was unplugged left
`pinned` set with no page on screen, and `pinned` answers the hover of every
island shut: no island opened again for a pointer until the person found the pin
in a menu of an island that showed nothing.

## Decision

**The act that opened the island answers why it is open, once, at the opening. A
step inside the open page keeps that answer, takes the keyboard it needs, and is
never an implicit pin.**

- `NotchSupport.openedByHover(opening:wasOpenedByHover:takeFocus:)` states the rule:
  an opening from the closed strip answers `!takeFocus` - a hover's page, or a
  click's page - and a navigation inside an island that is already open answers
  `wasOpenedByHover`. `NotchService.open` records it there and nowhere else, so
  one answer is read by the island's hover, by every copy's hover, by both
  pointer-following rules, and by `closesOnActivation`.
- The pin stays the only state that outlasts the pointer's leaving. It is the
  Keep Open the person chose - the page's quick-access row, the island's menu
  (`NotchIslandMenu.togglePin`, `activateQuickAction(.pin)`) - and it is cleared
  with the page: by `collapse()`, and now by `retireExpansion()` too, which
  clears `pinned` and `openedByHover` with the page whose window has gone.
- The expanded region, the deadlines and the ownership rules are unchanged:
  `closesOnPointerExit`, `NotchIslandHover`, `syncHoverExitMonitoring`,
  `syncPointerWatching`, `sweepPointer`, and the per-display rules of
  [0002](0002-one-island-per-display-one-page.md)
  and [0004](0004-a-page-opens-on-the-display-whose-island-was-used.md) are the
  same; the answer they read is the one that was always meant to survive a
  navigation. A page reached inside a copy's page is asked `on:` that copy's
  display, as every route already names, so it stays on the display whose island
  was used and the page remains one in the whole system.

## Consequences

- Hover-open pages collapse on every route and on every display: RAM, DISK, every
  reading's detail, Explorer, the gallery, the app panel, the whole dashboard,
  the pad, the clipboard, the shelf and the quick panel. Pointer movement inside
  the expanded panel keeps the page; leaving the whole region asks for the close
  at the chosen delay; returning over the delay takes it back.
- A click-opened island keeps its pages over a leaving, as its strip does, and
  a step inside such a page changes nothing. `takeFocus` is no longer a proxy for
  provenance, so a new page-opening route needs no provenance argument at all: it
  is answered by the opening, which is where the act is known.
- Cost, stated plainly: a page reached from a hover closes when the pointer
  leaves, including a page the person is reading. The pin is the way to keep it,
  and a card's click is not a pin. Unpinning returns the page to the pointer's
  rule, because the page keeps the provenance it was opened with.
- A display that goes away leaves no pin and no pointer's claim behind, so the
  remaining islands keep answering the pointer with nothing on screen to unpin.
- What the tests prove: the rule itself, the island's own lifecycle (hover, card,
  resting pointer, leaving, return over the delay, pin, unpin, click-opened
  island), the same lifecycle on a copy's display, the page staying on the
  display whose island was used for every route, one page in the whole system,
  and the pin and provenance going with a retired page. That a page *looks* right
  on a real display, with a real pointer, at a real close delay, needs the
  Release app.
- Related code: `Sources/Vorssaint/Services/Notch/NotchSupport.swift`
  (`openedByHover`, `closesOnPointerExit`, `NotchIslandHover`),
  `Sources/Vorssaint/Services/Notch/NotchService.swift` (`open`, `hover`,
  `mirrorHover`, `scheduleMirrorClose`, `syncHoverExitMonitoring`,
  `syncPointerWatching`, `retireExpansion`, `collapse`, `pinned`).
  Tests: `Tests/NotchHoverTests.swift` (`pageLifecycleChecks`),
  `Tests/NotchDestinationTests.swift` (`pageProvenanceContracts`),
  `Tests/NotchMirrorTests.swift` (the copy's page, its card, and the pin).
  Supersedes nothing: the hover-and-click distinction of
  [0002](0002-one-island-per-display-one-page.md) and the display ownership of
  [0004](0004-a-page-opens-on-the-display-whose-island-was-used.md) stand as they
  were recorded.
