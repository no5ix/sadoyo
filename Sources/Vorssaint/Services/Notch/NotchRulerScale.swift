// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// The range, the tick spacing and the labelling of one horizontal ruler.
///
/// The island's rulers are the same control — the same dragging, the same
/// wheel, the same haptic tick — and differ only in what they count: the
/// timer's minutes, a Pomodoro's focus, a monitoring interval in seconds.
/// A scale carries that difference so the control never hardcodes a range
/// and every ruler is measured by the same arithmetic.
struct NotchRulerScale: Equatable {
    let minimum: Int
    let maximum: Int
    /// Points between two neighbouring values.
    let spacing: Double
    /// A ruler labels every nth value and always its first; one labels all.
    let labelEvery: Int

    init(minimum: Int, maximum: Int, spacing: Double = 14, labelEvery: Int = 1) {
        let lower = min(minimum, maximum)
        let upper = max(minimum, maximum)
        self.minimum = lower
        self.maximum = max(lower, upper)
        self.spacing = spacing.isFinite && spacing > 0 ? spacing : 14
        self.labelEvery = max(1, labelEvery)
    }

    /// The count of values the ruler can rest on, the range's own length.
    var count: Int { maximum - minimum + 1 }

    /// The part of a row a ruler whose whole range fits is drawn across. The
    /// labels and the ticks are measured by the same number, so a ten-value
    /// ruler is read across the row it stands in and not in a narrow band in
    /// its middle, and the two ends keep the same margin.
    static let fixedSpanFraction = 0.8

    /// The points between neighbours at a row of `width`.
    ///
    /// A range that fits in the row is spread across four fifths of it, which
    /// is what makes a ten-second ruler readable; a range too wide for the row
    /// - the timer's 180 minutes - keeps its own spacing and slides under the
    /// pointer, exactly as it always did. The widest label two digits need at
    /// the ruler's own size is the floor, so a short row never squeezes the
    /// numbers into each other.
    func spacing(width: Double) -> Double {
        guard width.isFinite, width > 0, count > 1 else { return spacing }
        guard fitsEntireScale(width: width) else { return spacing }
        let widest = Double(Self.widestLabelWidth(digits: labelDigits))
        let pitch = max(Self.minimumLabelPitch, width * Self.fixedSpanFraction / Double(count - 1))
        return max(spacing, pitch, widest + 6)
    }

    /// Whether the whole range can stand in a row of `width` at the scale's
    /// own spacing, which is the test for a fixed ruler and a sliding one.
    func fitsEntireScale(width: Double) -> Bool {
        guard width.isFinite, width > 0 else { return false }
        return Double(count - 1) * spacing <= width - 2 * Self.inset(width: width)
    }

    /// The digits a label of this range carries, so the spacing knows how wide
    /// a number gets: 1 to 10 is two digits, 1 to 180 is three.
    var labelDigits: Int {
        let largest = max(abs(minimum), abs(maximum))
        var digits = 1
        var rest = largest
        while rest >= 10 { rest /= 10; digits += 1 }
        return digits
    }

    /// The room left at either end of a row, which is also the least margin a
    /// fixed ruler's first and last tick keep.
    static func inset(width: Double) -> Double { min(24, max(0, width) / 2) }

    /// A label's floor in points: two digits at the ruler's 14 points, with
    /// room between neighbours.
    static let minimumLabelPitch = 26.0

    /// The width of the widest number a ruler of `digits` digits writes, as
    /// the ruler draws it: the monospaced digits at 14 points, medium.
    static func widestLabelWidth(digits: Int) -> CGFloat {
        let rule = String(repeating: "8", count: max(1, digits)) as NSString
        return ceil(rule.size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        ]).width)
    }

    /// The value a drag or a wheel lands on, kept inside the range.
    func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return Double(minimum) }
        return min(Double(maximum), max(Double(minimum), value))
    }

    /// The value after a drag or a wheel of `points`. Dragging right moves the
    /// scale down, as a ruler slid under a pointer does.
    func moving(_ value: Double, by points: Double) -> Double {
        moving(value, by: points, spacing: spacing)
    }

    /// The same, at the spacing a row of a given width draws at, so a drag and
    /// a wheel travel by the ticks a person is looking at.
    func moving(_ value: Double, by points: Double, width: Double) -> Double {
        moving(value, by: points, spacing: spacing(width: width))
    }

    private func moving(_ value: Double, by points: Double, spacing: Double) -> Double {
        guard value.isFinite, points.isFinite, spacing > 0 else { return Double(minimum) }
        return clamped(value - points / spacing)
    }

    /// The whole value a position rests on.
    func value(_ value: Double) -> Int { Int(clamped(value).rounded()) }

    /// Where a value sits relative to the one in effect.
    func offset(of value: Int, selected: Int) -> Double {
        (Double(value) - Double(selected)) * spacing
    }

    /// The same, at the spacing a row of a given width draws at, so the ticks
    /// and their numbers are measured by the ruler the person is reading.
    func offset(of value: Int, selected: Int, width: Double) -> Double {
        (Double(value) - Double(selected)) * spacing(width: width)
    }

    /// Keep the ruler filled near either end instead of centering a short
    /// range over an empty half. The inset fits the widest labels as well.
    ///
    /// A range that fits is drawn as a fixed strip across four fifths of the
    /// row, so the selected value sits where its tick is and the first and
    /// last ticks keep the same margin; a range too wide for the row is kept
    /// inside the insets and slides, which is the timer's ruler unchanged.
    func selectionX(selected: Int, width: Double) -> Double {
        guard width.isFinite, width > 0 else { return 0 }
        let inset = Self.inset(width: width)
        let chosen = min(Double(maximum), max(Double(minimum), Double(selected)))
        let span = Double(count - 1) * spacing(width: width)
        if fitsEntireScale(width: width) {
            return (width - span) / 2 + (chosen - Double(minimum)) * spacing(width: width)
        }
        let leading = (chosen - Double(minimum)) * spacing(width: width)
        let trailing = (Double(maximum) - chosen) * spacing(width: width)
        if leading + trailing <= width - 2 * inset {
            return (width - leading - trailing) / 2 + leading
        }
        return min(inset + leading, max(width / 2, width - inset - trailing))
    }

    /// Where the pointer is: above the tick in effect, which for a ruler drawn
    /// at a measured row is that tick's own place in the row.
    func pointerX(selected: Int, width: Double) -> Double {
        selectionX(selected: selected, width: width)
    }

    /// Whether a value gets its number written under its tick. The first is
    /// always written, so a ruler is never led by an unlabelled tick.
    func showsLabel(_ value: Int) -> Bool {
        value == minimum || value.isMultiple(of: labelEvery)
    }

    /// The minutes the timer and the Pomodoro count, labelled every fifth and
    /// read as hours past an hour.
    static let minutes = NotchRulerScale(minimum: 1, maximum: 180, spacing: 14, labelEvery: 5)
    /// The whole seconds a monitoring interval is chosen from.
    static let seconds = NotchRulerScale(minimum: 1, maximum: 10, spacing: 14, labelEvery: 1)
}
