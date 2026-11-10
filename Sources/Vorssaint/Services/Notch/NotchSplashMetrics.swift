// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// MARK: - The line of a metric

/// The recent past of one figure, as its card draws it.
///
/// A line is a window and not a lifetime: what the card shows is the last
/// couple of minutes of readings, and what is older leaves the line as it
/// ages out. Two rules keep a line honest. Nothing is invented: a value is
/// recorded only when something was measured, and a card with no values
/// draws the quiet rule of an empty chart rather than a flat one. And the
/// size stays bounded: a server read every second for hours adds no memory,
/// because the oldest readings leave as the newest arrive.
struct NotchSplashSeries: Equatable {
    struct Point: Equatable {
        let at: Date
        let value: Double
    }

    /// Oldest first.
    private(set) var points: [Point] = []
    /// How far back the line reaches.
    let window: TimeInterval
    /// A ceiling on the points kept, so a fast server and a slow window cannot
    /// grow the line without limit.
    let maximumPoints: Int
    /// Two readings this far apart are one measurement, not two: a value that
    /// has not moved is recorded once, so a line is not thickened by a server
    /// that answers the same numbers every second.
    let minimumSpacing: TimeInterval

    init(window: TimeInterval, maximumPoints: Int, minimumSpacing: TimeInterval = 1) {
        self.window = max(1, window)
        self.maximumPoints = max(2, maximumPoints)
        self.minimumSpacing = max(0, minimumSpacing)
    }

    var isEmpty: Bool { points.isEmpty }
    var values: [Double] { points.map(\.value) }

    /// The newest value, which is the figure beside the line.
    var last: Double? { points.last?.value }

    /// Records one measurement. A value that is not a number is no measurement,
    /// and a value the line already ends with is not recorded twice.
    mutating func append(_ value: Double?, at date: Date) {
        guard let value, value.isFinite else { return }
        if let last = points.last {
            if last.at >= date { return }
            if last.value == value, date.timeIntervalSince(last.at) < minimumSpacing { return }
        }
        points.append(Point(at: date, value: value))
        trim(to: date)
    }

    /// Drops what has aged out of the window, and what the ceiling does not
    /// allow, keeping the newest.
    mutating func trim(to date: Date) {
        let from = date.addingTimeInterval(-window)
        if let first = points.first, first.at < from {
            points.removeAll { $0.at < from }
        }
        if points.count > maximumPoints {
            points.removeFirst(points.count - maximumPoints)
        }
    }

    /// A reading that is not part of the same measurement as the line so far:
    /// an engine begun again, a period with nothing in it.
    mutating func reset() {
        points.removeAll()
    }
}

// MARK: - Percentiles of what was measured

/// The percentile of a window of measurements, by nearest rank.
///
/// The rank is taken from what has been measured and from nothing else: fewer
/// measurements than the rank asks for give the highest of them, which is what
/// a window of one reading can honestly say. A percentile of no measurements is
/// no reading, and the card leaves the place empty.
func notchSplashPercentile(_ values: [Double], _ rank: Double) -> Double? {
    let real = values.filter(\.isFinite)
    guard !real.isEmpty else { return nil }
    let sorted = real.sorted()
    guard rank > 0 else { return sorted.first }
    guard rank < 1 else { return sorted.last }
    let index = Int((rank * Double(sorted.count)).rounded(.up)) - 1
    return sorted[min(max(index, 0), sorted.count - 1)]
}

// MARK: - Current throughput

/// Current throughput, measured from the engine's cumulative counters.
///
/// The endpoint answers a lifetime average: `decode_tokens_per_second` says
/// what the model has moved across the whole of its running, and it moves
/// slowly, so it is the second line of a card and not the first. A current
/// figure has to be measured, and the only counters that can measure it are
/// the cumulative ones - the tokens moved and the wall time the engine spent
/// moving them. Over a window of readings the difference between the first and
/// the last of them is the throughput of that window: a rate, sustained, and
/// not the speed of the last batch.
///
/// Five cases keep the figure honest, and each of them is a reading and not a
/// number:
///
/// * An engine that is not the one the window began in - a restart, an address
///   that moved - empties the window, because a difference across two engines
///   is not a measurement of either.
/// * A counter that came in below the mark it stood at is a counter begun
///   again, and empties the window for the same reason. It is never
///   subtracted.
/// * A window in which the engine's own clock did not move is a window in
///   which no work was done: nothing is being decoded, and the figure is
///   missing, and not zero.
/// * A window too short to carry a rate - one reading, a few milliseconds -
///   answers nothing, because the figure it would give is a spike and not a
///   throughput.
/// * The same reading twice adds no measurement, so a server that is asked
///   again while it does nothing cannot thicken the line.
struct NotchSplashRateTracker: Equatable {
    /// One reading of the counters, at the moment it was answered.
    struct Reading: Equatable {
        let at: Date
        let instanceKey: String
        let decodeTokens: Int64?
        let decodeWallMilliseconds: Double?
        let prefillTokens: Int64?
        let prefillWallMilliseconds: Double?
    }

    /// One mark of the counters, kept for the window.
    private struct Mark: Equatable {
        let at: Date
        let decodeTokens: Int64?
        let decodeWall: Double?
        let prefillTokens: Int64?
        let prefillWall: Double?
    }

    /// The last measured throughput of each kind, and nil when nothing in the
    /// window measures one.
    private(set) var decode: Double?
    private(set) var prefill: Double?
    /// The lines the two current figures draw.
    private(set) var decodeSeries = NotchSplashSeries(window: NotchSplashRateTracker.chartWindow,
                                                      maximumPoints: NotchSplashRateTracker.maximumPoints)
    private(set) var prefillSeries = NotchSplashSeries(window: NotchSplashRateTracker.chartWindow,
                                                       maximumPoints: NotchSplashRateTracker.maximumPoints)

    private var marks: [Mark] = []
    private var instanceKey: String?

    /// The window a current rate is measured over: long enough that a single
    /// short generation does not read as a sustained throughput, short enough
    /// that a change in the engine shows.
    static let window: TimeInterval = 60
    /// The same span the lines reach back, so a card's figure and its line are
    /// the one window.
    static let chartWindow: TimeInterval = 120
    static let maximumPoints = 240
    /// A span of readings shorter than this carries no rate: the figure it
    /// would give is one batch's speed, which is the spike the window exists
    /// to avoid.
    static let minimumSpan: TimeInterval = 2
    /// A wall-time difference shorter than this carries no rate: the division
    /// is then a ratio of milliseconds, and one token turns it into a
    /// four-figure throughput.
    static let minimumWallMilliseconds = 250.0
    /// Marks kept, so a server read a second apart is a bounded array and not
    /// a growing one.
    static let maximumMarks = 240

    var isEmpty: Bool { marks.isEmpty }
    /// How many marks the window holds, which is what a rate is measured over.
    var markCount: Int { marks.count }

    /// One reading, which may open a window, extend it, close it, or empty it.
    mutating func observe(_ reading: Reading) {
        // An engine that is not the one the window was measured in.
        if instanceKey != nil, instanceKey != reading.instanceKey { reset() }
        instanceKey = reading.instanceKey

        let mark = Mark(at: reading.at,
                        decodeTokens: reading.decodeTokens,
                        decodeWall: finite(reading.decodeWallMilliseconds),
                        prefillTokens: reading.prefillTokens,
                        prefillWall: finite(reading.prefillWallMilliseconds))
        // The same counters again: nothing moved, so nothing new is measured
        // and no mark is added, whatever the clock says - a poll of a server
        // that has not moved is one measurement, not two. The window is asked
        // again: a rate that has aged out of it is over, and an idle stretch
        // is answered by nothing and not by the last figure it left behind.
        if let last = marks.last, last.at <= mark.at, sameCounters(last, mark) {
            trim(to: mark.at)
            let decode = measure(field: .decode)
            let prefill = measure(field: .prefill)
            // The chart keeps its last point and gains none: the figure is the
            // same window, asked again.
            self.decode = decode
            self.prefill = prefill
            return
        }
        if let last = marks.last, last.at >= mark.at { return }
        // A counter below the mark it stood at is a counter begun again: the
        // window is emptied, and this reading is where the measuring starts.
        if let last = marks.last, wentBackwards(last, mark) { marks.removeAll() }
        marks.append(mark)
        trim(to: mark.at)
        let decode = measure(field: .decode)
        let prefill = measure(field: .prefill)
        self.decode = decode
        self.prefill = prefill
        decodeSeries.append(decode, at: mark.at)
        prefillSeries.append(prefill, at: mark.at)
    }

    /// A figure the current window does not measure: a restart, a session
    /// begun over a running engine, a server that stopped answering.
    mutating func reset() {
        marks.removeAll()
        instanceKey = nil
        decode = nil
        prefill = nil
        decodeSeries.reset()
        prefillSeries.reset()
    }

    // MARK: The measuring

    private enum Field {
        case decode, prefill
    }

    private static func counters(_ field: Field) -> (Mark) -> (Int64?, Double?) {
        switch field {
        case .decode: return { ($0.decodeTokens, $0.decodeWall) }
        case .prefill: return { ($0.prefillTokens, $0.prefillWall) }
        }
    }

    /// The two counters a rate needs, of one mark: nil when the mark lacks
    /// either, which is a server that does not report the field.
    private static func pair(_ field: Field, _ mark: Mark) -> (tokens: Int64, wall: Double)? {
        let read = counters(field)(mark)
        guard let tokens = read.0, let wall = read.1, tokens >= 0 else { return nil }
        return (tokens, wall)
    }

    /// The rate of the window: the tokens moved between the oldest and newest
    /// marks that carry both counters, over the wall time the engine says it
    /// spent moving them. Nil is the honest answer for a window that measures
    /// nothing, and every idle stretch is one of these: the engine's own clock
    /// did not move, so nothing was decoded. The reading is asked, never kept -
    /// the caller decides which of them is a measurement to draw, because a
    /// figure read out of counters that have not moved since the last mark is
    /// the window being asked again, not a new measurement.
    private func measure(field: Field) -> Double? {
        guard let first = marks.first(where: { Self.pair(field, $0) != nil }),
              let last = marks.reversed().first(where: { Self.pair(field, $0) != nil }),
              first.at != last.at,
              let from = Self.pair(field, first), let to = Self.pair(field, last) else {
            return nil
        }
        let span = last.at.timeIntervalSince(first.at)
        let wall = to.wall - from.wall
        let moved = to.tokens - from.tokens
        guard span >= Self.minimumSpan, wall >= Self.minimumWallMilliseconds, moved >= 0 else {
            return nil
        }
        let rate = Double(moved) / wall * 1000
        guard rate.isFinite, rate >= 0 else { return nil }
        return rate
    }

    private func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func sameCounters(_ before: Mark, _ after: Mark) -> Bool {
        before.decodeTokens == after.decodeTokens
            && before.decodeWall == after.decodeWall
            && before.prefillTokens == after.prefillTokens
            && before.prefillWall == after.prefillWall
    }

    /// A counter, or a wall clock, that came in below where it stood.
    private func wentBackwards(_ before: Mark, _ after: Mark) -> Bool {
        func below(_ previous: Double?, _ next: Double?) -> Bool {
            guard let previous, let next else { return false }
            return next < previous
        }
        func below(_ previous: Int64?, _ next: Int64?) -> Bool {
            guard let previous, let next else { return false }
            return next < previous
        }
        return below(before.decodeWall, after.decodeWall) || below(before.prefillWall, after.prefillWall)
            || below(before.decodeTokens, after.decodeTokens) || below(before.prefillTokens, after.prefillTokens)
    }

    private mutating func trim(to date: Date) {
        let from = date.addingTimeInterval(-Self.window)
        if let first = marks.first, first.at < from { marks.removeAll { $0.at < from } }
        if marks.count > Self.maximumMarks { marks.removeFirst(marks.count - Self.maximumMarks) }
        decodeSeries.trim(to: date)
        prefillSeries.trim(to: date)
    }
}

// MARK: - Recent first tokens

/// The first token's time, over the requests that have recently finished.
///
/// The endpoint reports the time to first token as statistics of its own - a
/// p50, and on a build that reports it a p95 - and it reports them over the
/// requests it has run. A card that showed that figure alone would show the
/// whole life of the engine and call it now, and a request that finished an
/// hour ago would still be the number. So the app keeps a window of the
/// measurements as it sees them: at every reading in which the engine's count
/// of finished requests grew, the statistics of that reading are one
/// measurement of a request that has just finished, and the card's p50 and p95
/// are the percentiles of the window.
///
/// This is the strongest thing the endpoint allows. It is written down as a
/// limitation: the app is not told each request's own first token, so its
/// window is of the engine's own recent statistics, taken as each request
/// finishes, and not of the requests themselves.
struct NotchSplashLatencyTracker: Equatable {
    struct Reading: Equatable {
        let at: Date
        let instanceKey: String
        /// Requests the engine says it has finished: the counter that says a
        /// request is over, and so a measurement of one is in hand.
        let completed: Int?
        let p50Milliseconds: Double?
        let p95Milliseconds: Double?
    }

    /// A measurement of one finished request, in seconds.
    private struct Sample: Equatable {
        let at: Date
        let p50: Double?
        let p95: Double?
    }

    private(set) var p50Seconds: Double?
    private(set) var p95Seconds: Double?
    /// The lines the two percentiles draw.
    private(set) var p50Series = NotchSplashSeries(window: NotchSplashLatencyTracker.chartWindow,
                                                   maximumPoints: NotchSplashLatencyTracker.maximumPoints)
    private(set) var p95Series = NotchSplashSeries(window: NotchSplashLatencyTracker.chartWindow,
                                                   maximumPoints: NotchSplashLatencyTracker.maximumPoints)

    private var samples: [Sample] = []
    private var instanceKey: String?
    private var lastCompleted: Int?
    /// The statistics last recorded, so a server that answers the same numbers
    /// twice does not record one request as two.
    private var lastRecorded: Sample?

    /// The window of finished requests the percentiles are taken over.
    static let window: TimeInterval = 10 * 60
    static let chartWindow: TimeInterval = 120
    static let maximumSamples = 120
    static let maximumPoints = 240
    /// The share of the window the p95 asks for.
    static let p95Rank = 0.95

    var isEmpty: Bool { samples.isEmpty }
    /// How many finished requests the window holds, which is what the
    /// percentiles are taken over.
    var sampleCount: Int { samples.count }

    mutating func observe(_ reading: Reading) {
        if instanceKey != nil, instanceKey != reading.instanceKey { reset() }
        instanceKey = reading.instanceKey

        let p50 = NotchSplashSupport.ttftSeconds(milliseconds: reading.p50Milliseconds)
        let p95 = NotchSplashSupport.ttftSeconds(milliseconds: reading.p95Milliseconds)
        let sample = Sample(at: reading.at, p50: p50, p95: p95)
        // Nothing to measure: the server reports no first-token time at all.
        guard sample.p50 != nil || sample.p95 != nil else {
            lastCompleted = reading.completed
            trim(to: sample.at)
            publish(at: sample.at)
            return
        }
        let grew: Bool
        if let completed = reading.completed, let last = lastCompleted {
            // A count that went down is an engine begun again: the window
            // starts over, and this reading is its first.
            if completed < last {
                reset()
                instanceKey = reading.instanceKey
                samples.append(sample)
                lastRecorded = sample
                lastCompleted = completed
                trim(to: sample.at)
                publish(at: sample.at)
                return
            }
            grew = completed > last
        } else if reading.completed != nil, lastCompleted == nil {
            // The first reading of this engine carries a count and no
            // difference: it is the baseline, and it is a measurement too,
            // which is what a card needs before its first request finishes.
            grew = true
        } else {
            // A server with no finished-request count: every reading in which
            // its statistics moved is a request that has finished.
            grew = lastRecorded.map { $0.p50 != sample.p50 || $0.p95 != sample.p95 } ?? true
        }
        lastCompleted = reading.completed
        guard grew, lastRecorded?.at != sample.at else {
            trim(to: sample.at)
            publish(at: sample.at)
            return
        }
        samples.append(sample)
        lastRecorded = sample
        trim(to: sample.at)
        publish(at: sample.at)
    }

    mutating func reset() {
        samples.removeAll()
        instanceKey = nil
        lastCompleted = nil
        lastRecorded = nil
        p50Seconds = nil
        p95Seconds = nil
        p50Series.reset()
        p95Series.reset()
    }

    /// The percentiles of the window, and the lines they draw. A window with
    /// nothing in it answers nil, and its cards leave the places empty.
    private mutating func publish(at date: Date) {
        let p50 = notchSplashPercentile(samples.compactMap(\.p50), 0.5)
        let p95 = notchSplashPercentile(samples.compactMap(\.p95), Self.p95Rank)
        p50Seconds = p50
        p95Seconds = p95
        p50Series.append(p50, at: date)
        p95Series.append(p95, at: date)
    }

    private mutating func trim(to date: Date) {
        let from = date.addingTimeInterval(-Self.window)
        if let first = samples.first, first.at < from { samples.removeAll { $0.at < from } }
        if samples.count > Self.maximumSamples { samples.removeFirst(samples.count - Self.maximumSamples) }
        p50Series.trim(to: date)
        p95Series.trim(to: date)
    }
}

// MARK: - What the cards read

/// The live figures of the three cards that measure, and the lines they draw.
///
/// The two figures of a card are two things: the current one is measured by
/// the app over a window of readings, and the overall one is the engine's own
/// lifetime average. Each pair, and each line, arrives together as one value,
/// so a card cannot draw a figure of one reading against a line of another.
struct NotchSplashLiveMetrics: Equatable {
    /// Current decode throughput, from the counters of the last window.
    var decode: Double?
    var prefill: Double?
    /// The first token's time over the requests that recently finished.
    var ttftP50: Double?
    var ttftP95: Double?
    var decodeSeries: [Double] = []
    var prefillSeries: [Double] = []
    var ttftP50Series: [Double] = []
    var ttftP95Series: [Double] = []

    static let empty = NotchSplashLiveMetrics()

    /// The decode speed the island's strip shows: what is being decoded now,
    /// and the engine's own average while nothing in the window measures a
    /// current rate. Both are measurements; neither is invented, and the
    /// strip shows nothing when the server answers neither.
    static func stripDecodeSpeed(current: Double?, overall: Double?) -> Double? {
        if let current, current.isFinite { return current }
        guard let overall, overall.isFinite, overall > 0 else { return nil }
        return overall
    }
}
