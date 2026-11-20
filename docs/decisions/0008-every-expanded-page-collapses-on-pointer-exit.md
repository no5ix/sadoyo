# 0008. Every expanded page collapses on pointer exit

- Status: accepted
- Date: 2026-11-20
- Affects: `NotchSupport.closesOnPointerExit`, the island's `hover(_:) `, every
  copy's `mirrorHover(_:entered:)`, `NotchService.syncHoverExitMonitoring`,
  `NotchService.mirrorFollowsPointer`, and explicit Keep Open handling
- Supersedes: the hover-versus-click dismissal distinction in [0006](0006-a-page-the-pointer-opened-stays-the-pointers-page.md)

## Context

The previous rule let a page opened by hovering collapse when the pointer left,
but treated a page opened by clicking the closed island as a deliberate surface
that remained expanded. The same rule was consulted by the primary island and
all per-display mirrors. That made the lifecycle depend on how the island was
opened rather than on the user's pointer leaving its visible interactive region.
It also made event-driven content such as a calendar countdown harder to reason
about when a display's collapsed island was expanded by hover.

The requested interaction is uniform: after any expanded page is opened - by
hover, by clicking the closed island, or by clicking a control inside the page -
moving the pointer outside the complete interactive Dynamic Island region must
collapse it on whichever display owns it.

## Decision

**Every expanded page follows the pointer-exit collapse rule, regardless of
opening method or displayed content.** The existing configured close delay and
return-before-deadline cancellation remain unchanged. The hit-test region remains
the whole destination surface, so moving from the compact notch into the
expanded panel is not an exit.

The only explicit user choice that outlasts pointer exit is Keep Open. Existing
modal, sheet, drag, and active-interaction protections remain in force while
their interaction is genuinely active; they are not inferred merely from a
page being open.

The display that owns the one expanded page still owns its close. The page never
moves windows between displays. The primary island and every mirror ask the same
`NotchSupport.closesOnPointerExit` rule, and the mirror pointer-following path
must remain armed for click-opened pages so their exit is observable too.

`openedByHover` remains recorded for application-activation semantics, where
whether the island was entered by pointer or opened by a deliberate click can
matter. It no longer exempts a click-opened expanded page from pointer-exit
collapse.

## Consequences

- Hover-opened and click-opened pages both collapse after the pointer leaves the
  whole interactive surface and the configured close delay expires.
- Clicking RAM, DISK, Explorer, a Splash Dashboard card, a gallery tile, or any
  other control does not implicitly pin the page.
- Returning before the close deadline cancels the pending collapse.
- An explicitly pinned page remains open until unpinned, subject to the existing
  lifecycle of the page and its owning display.
- Primary and external displays behave identically. Only the display that owns
  the page closes it; another display's pointer cannot close a page it does not
  carry.
- Activity or notice content (including a calendar event countdown) does not
  change this dismissal policy.
- Regression coverage verifies click-opened and hover-opened pages on the
  primary island and display mirrors, plus the explicit pin exception.

## Related code and tests

- `Sources/Vorssaint/Services/Notch/NotchSupport.swift`
- `Sources/Vorssaint/Services/Notch/NotchService.swift`
- `Sources/Vorssaint/UI/Notch/NotchComponents.swift`
- `Tests/NotchHoverTests.swift`
- `Tests/NotchMirrorTests.swift`
- `Tests/NotchDestinationTests.swift`
