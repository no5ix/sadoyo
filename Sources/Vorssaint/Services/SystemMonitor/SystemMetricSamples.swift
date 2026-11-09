// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One moment of the monitor: every reading taken at that instant.
///
/// A card's chart is drawn from these, and not from the current reading
/// repeated. Two things make that honest:
///
/// * The instant is carried with the readings, so a chart's horizontal axis is
///   time and not the order the app happened to draw in, and a stretch with no
///   readings is a stretch with no line.
/// * A pair that belongs together is carried together. The network's down and
///   up are read in one sample of one sampler at one instant, and the disk's
///   read and write the same way, so the two lines of a card's chart are the
///   two halves of one moment and never two moments drawn as one.
///
/// Every reading is optional. A Mac with no battery, a metric the hub has
/// switched off, and a read that failed all leave their field nil, and the
/// card that draws that field says it has nothing.
struct SystemMetricSample: Equatable {
    /// The instant every reading here was taken at, on the system uptime
    /// clock, which is the clock the monitor already stamps its readings with.
    let at: TimeInterval
    /// A share of the machine's work, 0…1.
    var cpu: Double?
    var gpu: Double?
    /// Used memory over total memory, 0…1.
    var memory: Double?
    /// Throughput in bytes a second.
    var netDown: Double?
    var netUp: Double?
    var diskRead: Double?
    var diskWrite: Double?
    /// The machine's draw, in watts.
    var watts: Double?

    /// Whether this moment added anything to draw. A tick that sampled nothing
    /// adds no moment, so a chart's samples are readings and not a count of
    /// the timer's beats.
    var hasReading: Bool {
        cpu != nil || gpu != nil || memory != nil || netDown != nil || netUp != nil
            || diskRead != nil || diskWrite != nil || watts != nil
    }
}

/// One measurement of a chart's line: when, and what.
struct SystemMetricPoint: Equatable {
    let at: TimeInterval
    let value: Double
}

/// The readings a chart asks of the samples.
///
/// The window, the missing fields, and the scale shared between two lines of
/// one card are decided here, so the view draws points and asks nothing of the
/// sampler.
enum SystemMetricSeries {
    /// The window's points of one reading, oldest first.
    ///
    /// `field` is the reading asked for; a sample that has none of it is left
    /// out, which is what makes a gap a gap. `window` is how far back a chart
    /// looks, and `now` the instant the window ends, which the card passes in
    /// so its charts and its figures answer the same moment.
    static func points(in samples: [SystemMetricSample], _ field: KeyPath<SystemMetricSample, Double?>,
                       window: TimeInterval, endingAt now: TimeInterval) -> [SystemMetricPoint] {
        let from = now - max(0, window)
        return samples.compactMap { sample in
            guard sample.at >= from, sample.at <= now,
                  let value = sample[keyPath: field], value.isFinite else { return nil }
            return SystemMetricPoint(at: sample.at, value: value)
        }
    }

    /// The points of a pair, kept as pairs: the instants the two lines share.
    ///
    /// A sample that carries one half of the pair and not the other is kept
    /// with the half it has, and the line it feeds stops short there; the two
    /// lines are drawn against the same instants, which is the whole point of
    /// the pair.
    static func pairs(in samples: [SystemMetricSample], _ first: KeyPath<SystemMetricSample, Double?>,
                      _ second: KeyPath<SystemMetricSample, Double?>,
                      window: TimeInterval, endingAt now: TimeInterval) -> [SystemMetricPair] {
        let from = now - max(0, window)
        return samples.compactMap { sample in
            guard sample.at >= from, sample.at <= now else { return nil }
            let a = sample[keyPath: first]
            let b = sample[keyPath: second]
            guard (a?.isFinite == true) || (b?.isFinite == true) else { return nil }
            return SystemMetricPair(at: sample.at,
                                    first: a?.isFinite == true ? a : nil,
                                    second: b?.isFinite == true ? b : nil)
        }
    }

    /// The highest reading across every line of one card, and the lowest.
    ///
    /// Two lines of one card are drawn on one scale, because a card's chart is
    /// a comparison: an upload that doubles while the download stands still has
    /// to look like that, and two lines each scaled to itself would not say it.
    static func scale(of series: [[SystemMetricPoint]], floorAtZero: Bool = true) -> ClosedRange<Double>? {
        let values = series.flatMap(\.values)
        guard let low = values.min(), let high = values.max(), values.count > 1 else { return nil }
        let top = max(low, high)
        if floorAtZero || low >= 0 { return 0...max(top, 1e-9) }
        return min(low, 0)...max(top, 1e-9)
    }

    /// The steps between a line's own measurements, and the usual one of them.
    ///
    /// The usual step is what tells a line where the monitor stopped reading:
    /// a step three times the usual one is a stretch with no samples, and the
    /// line is broken there rather than drawn across the machine's silence.
    static func steps(of points: [SystemMetricPoint]) -> [TimeInterval] {
        guard points.count > 1 else { return [] }
        return (1..<points.count).map { points[$0].at - points[$0 - 1].at }
    }

    static func usualStep(of points: [SystemMetricPoint]) -> TimeInterval {
        let sorted = steps(of: points).sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    /// A step this far past the usual one is a gap in the readings.
    static let gapFactor: TimeInterval = 3

    /// Where a line stops and begins again: the places its own steps are a
    /// gap. The runs returned are index ranges into `points`, oldest first.
    static func runs(of points: [SystemMetricPoint]) -> [Range<Int>] {
        guard points.count > 1 else { return points.isEmpty ? [] : [0..<points.count] }
        let usual = max(0.001, usualStep(of: points))
        var runs: [Range<Int>] = []
        var start = 0
        for index in 1..<points.count where points[index].at - points[index - 1].at > usual * gapFactor {
            runs.append(start..<index)
            start = index
        }
        runs.append(start..<points.count)
        return runs.filter { $0.count > 0 }
    }
}

/// The two halves of one instant, as one card draws them.
struct SystemMetricPair: Equatable {
    let at: TimeInterval
    let first: Double?
    let second: Double?
}

extension Array where Element == SystemMetricPoint {
    var values: [Double] { map(\.value) }
    var times: [TimeInterval] { map(\.at) }
}

/// A bounded rolling history of the monitor's moments.
///
/// The window is a count of moments, not an unbounded log: the island's charts
/// read the last few minutes, and a machine left running for a month keeps the
/// same handful of readings it kept in the first minute.
struct SystemMetricSampleHistory {
    let capacity: Int
    private(set) var samples: [SystemMetricSample] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    mutating func push(_ sample: SystemMetricSample) {
        guard sample.hasReading else { return }
        // The moments are the sampler's own; a repeat of the last instant adds
        // a moment the machine did not have.
        if let last = samples.last, last.at == sample.at {
            samples[samples.count - 1] = sample
            return
        }
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    /// The same shape `MetricHistory` uses: a chart surface gets its readings,
    /// and a surface that is not on screen asks for nothing, so no background
    /// sample copies the retained array.
    func publishedValues(whileVisible visible: Bool) -> [SystemMetricSample] {
        visible ? samples : []
    }
}
