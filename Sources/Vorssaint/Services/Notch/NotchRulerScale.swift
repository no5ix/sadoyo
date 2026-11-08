// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

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

    /// The value a drag or a wheel lands on, kept inside the range.
    func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return Double(minimum) }
        return min(Double(maximum), max(Double(minimum), value))
    }

    /// The value after a drag or a wheel of `points`. Dragging right moves the
    /// scale down, as a ruler slid under a pointer does.
    func moving(_ value: Double, by points: Double) -> Double {
        guard value.isFinite, points.isFinite else { return Double(minimum) }
        return clamped(value - points / spacing)
    }

    /// The whole value a position rests on.
    func value(_ value: Double) -> Int { Int(clamped(value).rounded()) }

    /// Where a value sits relative to the one in effect.
    func offset(of value: Int, selected: Int) -> Double {
        (Double(value) - Double(selected)) * spacing
    }

    /// Keep the ruler filled near either end instead of centering a short
    /// range over an empty half. The inset fits the widest labels as well.
    func selectionX(selected: Int, width: Double) -> Double {
        guard width.isFinite, width > 0 else { return 0 }
        let inset = min(24, width / 2)
        let selected = min(Double(maximum), max(Double(minimum), Double(selected)))
        let leading = (selected - Double(minimum)) * spacing
        let trailing = (Double(maximum) - selected) * spacing
        if leading + trailing <= width - 2 * inset {
            return (width - leading - trailing) / 2 + leading
        }
        return min(inset + leading, max(width / 2, width - inset - trailing))
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
