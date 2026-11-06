// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Where one reading's block sits in the combined menu bar title, in points
/// measured from the title's own left edge.
struct MenuBarMetricHitRange: Equatable {
    let metricRaw: String
    let minX: CGFloat
    let maxX: CGFloat

    var width: CGFloat { maxX - minX }
}

/// Where a click on the menu bar belongs.
enum MenuBarHit: Equatable {
    case metric(String)
    case panel
}

/// The combined menu bar item shows several readings in one button, so the
/// button has to answer "which number did the pointer land on". The layout
/// writes the widths, this decides the ranges and the click. Keeping the
/// decision here means a click that opens the overview instead of a reading's
/// page is a decision that can be read, and tested, on its own.
enum MenuBarMetricHitSupport {
    /// Contiguous ranges, in the order the metrics are written. Each slice
    /// carries the glue that separates it from the block on its left, so the
    /// ranges cover the title with no gaps and every point of it belongs to
    /// exactly one reading. A metric that renders nothing gets a zero-wide
    /// slice, which no click can land on.
    static func ranges(metrics: [String], widths: [CGFloat], leadingInset: CGFloat = 0) -> [MenuBarMetricHitRange] {
        var x: CGFloat = leadingInset.isFinite ? leadingInset : 0
        var result: [MenuBarMetricHitRange] = []
        for (index, metric) in metrics.enumerated() {
            let width = index < widths.count ? max(0, widths[index]) : 0
            result.append(MenuBarMetricHitRange(metricRaw: metric, minX: x, maxX: x + width))
            x += width
        }
        return result
    }

    /// The reading whose block covers `x`, or nil when the pointer is over
    /// nothing: before the first block, past the last, a zero-wide block, or a
    /// value that is not a position at all.
    static func metric(at x: CGFloat, in ranges: [MenuBarMetricHitRange]) -> String? {
        guard x.isFinite else { return nil }
        return ranges.first { $0.width > 0 && $0.minX <= x && x < $0.maxX }?.metricRaw
    }

    /// A click on a reading's number is that reading's page; a click anywhere
    /// else on the item, including a click with no position to read, is the
    /// app panel's.
    static func mainItemClick(x: CGFloat?, in ranges: [MenuBarMetricHitRange]) -> MenuBarHit {
        guard let x, let metric = metric(at: x, in: ranges) else { return .panel }
        return .metric(metric)
    }
}
