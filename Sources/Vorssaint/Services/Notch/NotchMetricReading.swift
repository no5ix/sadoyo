// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The reading rules every surface shares: a share written as a person reads
/// it, and the tone of a load once the load's gate has had its say.
///
/// The island's compact cards, the System page's tiles, the menu bar and the
/// detail pages all ask the same two questions, and they ask them here. The
/// rules sit apart from the monitor's snapshot and from the views, so the
/// answer a card gives can be tested with a number in it and not with a
/// sampler behind it.
enum NotchMetricReading {
    /// A share as a figure: `41%`. A share that is not a number says nothing,
    /// and a share out of its range is read at its end.
    static func percent(_ value: Double?) -> String? {
        value.flatMap { $0.isFinite ? "\(Int((min(1, max(0, $0)) * 100).rounded()))%" : nil }
    }

    /// The same share as the thresholds read it: 0…100.
    static func percentValue(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite ? min(1, max(0, $0)) * 100 : nil }
    }

    /// The tone of a load: the threshold's answer, with the gate's answer over
    /// it when the gate has one. A load that has not held keeps the page's
    /// quiet colour, which is the whole point of the gate.
    static func tone(_ metric: NotchDashboardMetric, percent: Double?,
                     sustained: [NotchDashboardMetric: NotchMetricTone]) -> NotchMetricTone {
        gate(NotchMetricHealth.tone(metric: metric, percent: percent),
             gated: sustained[metric])
    }

    /// One reading and one gate, answered.
    ///
    /// A gate that has gone quiet while the reading is loud is a gate that has
    /// not seen a fresh sample yet: the reading answers for itself.
    static func gate(_ reading: NotchMetricTone, gated: NotchMetricTone?) -> NotchMetricTone {
        guard let gated else { return reading }
        return reading.severity > gated.severity ? gated : reading
    }
}
