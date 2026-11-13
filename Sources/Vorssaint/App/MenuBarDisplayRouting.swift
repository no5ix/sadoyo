// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Pure geometry for the one question a menu bar click has to answer before it
/// opens an island page: which display's menu bar was clicked.
///
/// Every display has a menu bar, and the app's reading indicators — RAM, DISK,
/// CPU, GPU, network, battery — live in all of them. A click belongs to the
/// display that bar stands on, and the island page it opens belongs to that
/// display too (see
/// `docs/decisions/0004-a-page-opens-on-the-display-whose-island-was-used.md`):
/// the primary display never takes a page that a click on another display's
/// bar asked for.
///
/// The island's own views carry their display in `\.notchPageDisplay`, because
/// the window that draws them was built for one display and never moves. A menu
/// bar indicator has no island window behind it, so it has nothing to carry:
/// the click answers instead, and it has to be asked where it happens, before
/// the action runs and the pointer has travelled.
///
/// A status item's window is not proof of the bar it was clicked on. A
/// replicated menu bar (Sidecar, mirroring, a bar parked off screen) reports
/// the status window on another display, and a menu bar set to hide itself
/// parks that window outside the visible area. So the captured click answers
/// first — the one position the window server vouches for, the same authority
/// `StatusItemAnchorSupport` gives it for the panel's anchor — and the
/// window's reported frame answers only where there is no click to ask.
///
/// The answer is nil when neither can say. A click that cannot be placed names
/// no display, and a request that names no display keeps the island's page
/// where it is; taking the primary display for a click that may have happened
/// on another bar is the failure this file exists to prevent.
enum MenuBarDisplayRouting {
    /// One display's menu bar, as far as this choice goes: the display's
    /// identity and the frame of the screen it covers. A caller builds these from
    /// the screens it is looking at — AppKit's `NSScreen`, whose `notchDisplayID`
    /// is its own `NSScreenNumber`, and a screen named by a test — so the choice
    /// can be read on a desk of displays that is not the one this Mac has.
    struct Bar: Equatable {
        let displayID: CGDirectDisplayID
        let frame: CGRect
    }

    /// The bar a click belongs to, by index into the same list, or nil when
    /// nothing says which bar it was.
    ///
    /// `click` is the pointer in AppKit's global screen coordinates, origin at
    /// the bottom left of the main display. It is asked first: a display
    /// stacked above another shares its x, so only the click tells those bars
    /// apart, and a status item's window can be reporting a display the icon is
    /// not drawn on at all. `windowFrame` answers only for a click that was
    /// never captured, where the window's own place is the evidence left.
    ///
    /// The click test is inclusive of a frame's edges, the way `NSMouseInRect`
    /// is: a click on the shared edge of two arranged displays belongs to a bar
    /// and must not fall between them.
    static func barIndex(click: CGPoint?, windowFrame: CGRect?, bars: [Bar]) -> Int? {
        if let click, let clicked = bars.firstIndex(where: { contains($0.frame, click) }) {
            return clicked
        }
        if let windowFrame, let hosting = bars.firstIndex(where: { $0.frame.intersects(windowFrame) }) {
            return hosting
        }
        return nil
    }

    /// `NSMouseInRect(point, frame, false)` without AppKit's call, measured on the
    /// same edges: a point on a frame's top edge (or its left) is inside it, and a
    /// point on its bottom edge (or its right) is not — the boundary belongs to the
    /// screen below and to the left, which is the screen whose menu bar a click on
    /// a shared boundary is on. A click exactly at the top of the screen below is
    /// the case that matters: it is that screen's bar, and a rule that also counts
    /// it as the screen above anchors the page, and the panel, to the wrong display.
    private static func contains(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x < frame.maxX && point.y > frame.minY && point.y <= frame.maxY
    }
}
