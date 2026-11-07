// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A page's own reading of how much of it is on screen: how far it has
/// scrolled, how tall the page's window is, and how tall the whole page is.
struct NotchScrollReading: Equatable {
    var offset: CGFloat = 0
    var container: CGFloat = 0
    var content: CGFloat = 0

    /// More of the page lies beyond its window than fits in it.
    var scrolls: Bool { container > 0 && content - container > 1 }

    /// How far through the page the window sits, from its first row at 0 to
    /// its last at 1.
    var progress: CGFloat {
        let travel = content - container
        guard travel > 1 else { return 0 }
        return min(1, max(0, offset / travel))
    }
}

/// The island's scroller for a page that outgrows its panel: a narrow, rounded
/// bar that keeps to a fifth of its track whatever the page's length, so a long
/// list of applications gets a short mark of where it stands rather than a rail
/// down the island's side.
///
/// The bar asks no room of the page and takes no clicks, so the wheel, the
/// trackpad, the keyboard and a drag all scroll the page under it exactly as
/// they did with the system's scroller, whose own long rail this replaces. It
/// shows only while the page has more of itself beyond an edge: a page that
/// fits its panel is drawn whole, with no scroller in it at all.
struct NotchScrollIndicator: ViewModifier {
    /// The bar as a part of its track, which is the page's window.
    static let thumbFraction: CGFloat = 0.2
    /// The bar's width, and its distance from the page's edge and ends.
    static let thickness: CGFloat = 3
    static let edgeInset: CGFloat = 5
    /// A page barely longer than its panel still gets a bar the finger can see.
    static let minimumThumb: CGFloat = 28

    @State private var reading = NotchScrollReading()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: NotchScrollReading.self) { geometry in
                    NotchScrollReading(offset: geometry.contentOffset.y,
                                       container: geometry.containerSize.height,
                                       content: geometry.contentSize.height)
                } action: { _, value in
                    reading = value
                }
                .overlay(alignment: .topTrailing) { bar }
        } else {
            // Earlier systems report no scroll geometry to draw a bar from, so
            // the system's own scroller keeps its charge there.
            content.scrollIndicators(.automatic)
        }
    }

    /// The bar, at the point on its track the page is scrolled to.
    private var bar: some View {
        GeometryReader { proxy in
            let track = proxy.size.height
            let thumb = Self.thumbHeight(track: track)
            Capsule()
                .fill(.white.opacity(0.32))
                .frame(width: Self.thickness, height: thumb)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, Self.edgeInset)
                .offset(y: Self.edgeInset + Self.travel(track: track, thumb: thumb) * reading.progress)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .opacity(reading.scrolls ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: reading.scrolls)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A fifth of the track, and never a bar shorter than a finger can find.
    static func thumbHeight(track: CGFloat) -> CGFloat {
        min(max(0, track - edgeInset * 2), max(minimumThumb, track * thumbFraction))
    }

    /// How far down the track the bar's top may travel.
    static func travel(track: CGFloat, thumb: CGFloat) -> CGFloat {
        max(0, track - thumb - edgeInset * 2)
    }
}

extension View {
    /// The island's scroller, for a page that outgrows its panel.
    func notchScrollIndicator() -> some View { modifier(NotchScrollIndicator()) }
}
