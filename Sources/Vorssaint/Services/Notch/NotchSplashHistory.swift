// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Vorssaint

import Foundation

// MARK: - What is kept

/// One metric reading, kept for the charts.
///
/// A sample carries what the server answered for one moment. A metric the
/// server did not answer is nil, and stays out of the chart's line: a gap is
/// drawn as a gap, and nothing is filled in.
///
/// Each measuring chart draws two lines from one sample, so a sample carries
/// both of the engine's figures for each: the batch it had in hand at that
/// moment, and the average over the whole of its running. Nothing is kept
/// that the engine did not answer, and a thinned sample is the average of its
/// bucket for every field, so a thinned line is a thinner version of the same
/// measurement and not a different one.
struct NotchSplashSample: Equatable {
    let at: Date
    /// The decode batch in hand, and the engine's average over its running.
    var decodeCurrent: Double?
    var decode: Double?
    var prefillCurrent: Double?
    var prefill: Double?
    /// The first token's time at the two percentiles the engine names.
    var ttftSeconds: Double?
    var ttftP95Seconds: Double?
    var cachePercent: Double?

    /// The same sample with its figures rounded to what a chart can show, so
    /// a month of readings stays a small file.
    func rounded() -> NotchSplashSample {
        func round(_ value: Double?, _ places: Double) -> Double? {
            guard let value, value.isFinite else { return nil }
            return (value * places).rounded() / places
        }
        return NotchSplashSample(at: at,
                                 decodeCurrent: round(decodeCurrent, 100),
                                 decode: round(decode, 100),
                                 prefillCurrent: round(prefillCurrent, 10),
                                 prefill: round(prefill, 10),
                                 ttftSeconds: round(ttftSeconds, 1000),
                                 ttftP95Seconds: round(ttftP95Seconds, 1000),
                                 cachePercent: round(cachePercent, 100))
    }

    /// Nothing the server answered for this moment, which is a reading with no
    /// chart in it: a sample is kept only when at least one field has a figure.
    var hasFigures: Bool {
        decodeCurrent != nil || decode != nil || prefillCurrent != nil || prefill != nil
            || ttftSeconds != nil || ttftP95Seconds != nil || cachePercent != nil
    }
}

/// One day's tokens, built from the differences of the engine's cumulative
/// counters, so a day says what was used that day and not what the engine has
/// used since it started.
struct NotchSplashDay: Equatable {
    /// The day's start, in the user's calendar.
    let start: Date
    var input: Int64 = 0
    var output: Int64 = 0

    var total: Int64 { input + output }
    var hasActivity: Bool { input > 0 || output > 0 }
}

// MARK: - The history

/// The dashboard's measured past: the samples the four charts draw and the
/// daily token totals the trend card draws.
///
/// Two rules hold the whole thing honest. Nothing is invented: a period before
/// the app was measuring has no records, and the cards say so, and a counter
/// that went down - a restart, a reset - adds nothing rather than a negative.
/// And the size stays small: readings are kept close as they are, and thinned
/// as they age, for thirty days.
struct NotchSplashHistory: Equatable {
    private(set) var samples: [NotchSplashSample] = []
    private(set) var days: [NotchSplashDay] = []
    /// The counters the last reading carried, and the engine that carried
    /// them, so the next reading's difference is a difference and not a guess.
    private(set) var counters: NotchSplashCounters?

    init(samples: [NotchSplashSample] = [], days: [NotchSplashDay] = [],
         counters: NotchSplashCounters? = nil) {
        self.samples = samples
        self.days = days
        self.counters = counters
    }

    static let empty = NotchSplashHistory()

    /// A reading's cumulative counters, as the engine writes them.
    struct NotchSplashCounters: Equatable, Codable {
        let instanceKey: String
        let input: Int64?
        let output: Int64?
    }

    // MARK: Measuring

    /// Records one reading. `status` is what the server answered, `at` when
    /// it was answered, and the counters are added to the day `at` falls in.
    mutating func record(status: NotchSplashStatus, instanceKey: String, at date: Date,
                         calendar: Calendar = .autoupdatingCurrent) {
        let sample = NotchSplashSample(
            at: date,
            decodeCurrent: status.metrics.currentDecodeBatchTokensPerSecond,
            decode: status.metrics.decodeTokensPerSecond,
            prefillCurrent: status.metrics.currentPrefillBatchTokensPerSecond,
            prefill: status.metrics.prefillTokensPerSecond,
            ttftSeconds: NotchSplashSupport.ttftSeconds(milliseconds: status.metrics.ttftMilliseconds),
            ttftP95Seconds: NotchSplashSupport.ttftSeconds(milliseconds: status.metrics.ttftP95Milliseconds),
            cachePercent: NotchSplashSupport.cacheHitPercent(hits: status.cache.hits,
                                                             requests: status.cache.requests,
                                                             reportedRate: status.cache.reportedRate)
        ).rounded()
        if sample.hasFigures {
            samples.append(sample)
        }
        addTokens(status: status, instanceKey: instanceKey, at: date, calendar: calendar)
    }

    /// The day's tokens, from the difference between this reading's counters
    /// and the last. A counter that went down, an engine that is not the one
    /// the last reading came from, and a counter the server does not report
    /// each start a new baseline and add nothing.
    private mutating func addTokens(status: NotchSplashStatus, instanceKey: String, at date: Date,
                                    calendar: Calendar) {
        let read = NotchSplashCounters(instanceKey: instanceKey,
                                       input: status.metrics.prefillInputTokens,
                                       output: status.metrics.decodeOutputTokens)
        let previous = counters
        counters = read
        // The first reading of this engine, or a reading from an engine that
        // is not the one the last reading came from: the totals carry no
        // information about the time between, so nothing is added.
        guard let previous, previous.instanceKey == read.instanceKey else { return }
        let input = Self.difference(before: previous.input, after: read.input)
        let output = Self.difference(before: previous.output, after: read.output)
        // A reading with nothing new to add leaves the day where it was.
        if input == 0 && output == 0 { return }
        let start = calendar.startOfDay(for: date)
        if let index = days.firstIndex(where: { $0.start == start }) {
            days[index].input += input
            days[index].output += output
        } else {
            days.append(NotchSplashDay(start: start, input: input, output: output))
        }
    }

    private static func difference(before: Int64?, after: Int64?) -> Int64 {
        guard let before, let after, after > before else { return 0 }
        return after - before
    }

    /// A baseline for the counters, after a restart, so a session begun over a
    /// running engine does not count the engine's whole life as today's work.
    mutating func resetCounters() {
        counters = nil
    }

    // MARK: Keeping thirty days

    /// Drops samples and days outside the last `days` calendar days, including
    /// today, and thins what is left. Returns whether anything was dropped,
    /// which is when the file has to be written again.
    @discardableResult
    mutating func clean(now: Date, calendar: Calendar = .autoupdatingCurrent,
                        days retention: Int = NotchSplashHistory.retentionDays) -> Bool {
        let before = samples.count + self.days.count
        let first = calendar.date(byAdding: .day, value: -(retention - 1), to: calendar.startOfDay(for: now)) ?? now
        samples.removeAll { $0.at < first }
        self.days.removeAll { $0.start < first }
        if self.days.count > retention {
            self.days = Array(self.days.suffix(retention))
        }
        compact(now: now)
        if samples.count > Self.maximumSamples {
            samples = Array(samples.suffix(Self.maximumSamples))
        }
        return samples.count + self.days.count != before
    }

    /// Thirty days of readings, kept whole.
    static let retentionDays = 30
    /// A ceiling on the samples held, so a server read every second for a
    /// month stays a file of a few hundred kilobytes.
    static let maximumSamples = 12_000
    /// Readings newer than this are kept as they came.
    static let freshWindow: TimeInterval = 30 * 60
    /// Readings older than this are kept to a minute apiece.
    static let dayWindow: TimeInterval = 24 * 60 * 60
    /// Older readings are kept to ten minutes apiece.
    static let coarseBucket: TimeInterval = 10 * 60
    static let fineBucket: TimeInterval = 60

    /// Thins the samples: whole for the last half hour, a minute apiece for
    /// the last day, ten minutes apiece beyond that. Each thinned sample is
    /// the average of the readings in its bucket, and a bucket with nothing in
    /// a field keeps that field empty.
    mutating func compact(now: Date) {
        let fresh = now.timeIntervalSince1970 - Self.freshWindow
        let fine = now.timeIntervalSince1970 - Self.dayWindow
        var kept: [NotchSplashSample] = []
        var buckets: [Int: [NotchSplashSample]] = [:]
        var starts: [Int: Double] = [:]
        var order: [Int] = []
        for sample in samples {
            let at = sample.at.timeIntervalSince1970
            if at >= fresh {
                kept.append(sample)
                continue
            }
            let size = at >= fine ? Self.fineBucket : Self.coarseBucket
            // A key of its own for each thinning level, so a minute's bucket
            // and a ten-minute bucket never share a number.
            let key = Int(floor(at / size)) + (size == Self.fineBucket ? 0 : Self.bucketKeyOffset)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(sample)
            starts[key] = Double(key % Self.bucketKeyOffset) * size
        }
        let merged = order.compactMap { key -> NotchSplashSample? in
            guard let group = buckets[key], !group.isEmpty else { return nil }
            return NotchSplashSample(at: Date(timeIntervalSince1970: starts[key] ?? group[0].at.timeIntervalSince1970),
                                     decodeCurrent: Self.average(group.map(\.decodeCurrent)),
                                     decode: Self.average(group.map(\.decode)),
                                     prefillCurrent: Self.average(group.map(\.prefillCurrent)),
                                     prefill: Self.average(group.map(\.prefill)),
                                     ttftSeconds: Self.average(group.map(\.ttftSeconds)),
                                     ttftP95Seconds: Self.average(group.map(\.ttftP95Seconds)),
                                     cachePercent: Self.average(group.map(\.cachePercent)))
                .rounded()
        }
        kept.append(contentsOf: merged)
        samples = kept.sorted { $0.at < $1.at }
    }

    /// A number big enough to keep the coarse buckets' keys apart from the
    /// minute buckets'.
    static let bucketKeyOffset = 1_000_000_000

    private static func average(_ values: [Double?]) -> Double? {
        let real = values.compactMap { $0 }
        guard !real.isEmpty else { return nil }
        return real.reduce(0, +) / Double(real.count)
    }

    // MARK: What the cards ask

    /// The samples in the charts' window, oldest first, which is the line the
    /// cards draw: ten minutes of readings, and nothing older.
    func series(window: TimeInterval = NotchSplashSupport.chartWindowSeconds, endingAt now: Date) -> [NotchSplashSample] {
        let from = now.addingTimeInterval(-window)
        return samples.filter { $0.at >= from && $0.at <= now }
    }

    func values(_ field: (NotchSplashSample) -> Double?,
                window: TimeInterval = NotchSplashSupport.chartWindowSeconds,
                endingAt now: Date) -> [Double] {
        series(window: window, endingAt: now).compactMap(field)
    }

    /// The last `count` calendar days, today last, with a day of nothing for
    /// every day that has no record, so the trend's bars line up with the
    /// dates under them.
    func trend(calendar: Calendar = .autoupdatingCurrent, now: Date,
               count: Int = NotchSplashHistory.retentionDays) -> [NotchSplashDay] {
        let today = calendar.startOfDay(for: now)
        var out: [NotchSplashDay] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            let start = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let day = days.first { calendar.isDate($0.start, inSameDayAs: start) }
            out.append(NotchSplashDay(start: start, input: day?.input ?? 0, output: day?.output ?? 0))
        }
        return out
    }

    /// The tokens of the days shown, which is the trend card's caption.
    func total(of days: [NotchSplashDay]) -> Int64 {
        days.reduce(0) { $0 + $1.total }
    }

    var hasSamples: Bool { !samples.isEmpty }
    var hasTokens: Bool { days.contains(where: \.hasActivity) }
}

// MARK: - The file

/// The history on disk: one JSON file in the app's own Application Support
/// container, written owner-only like everything else kept there.
///
/// Reading is done once, at the start of a session, and the whole history
/// comes back with it, so a crash costs the readings that were measured in
/// the last half minute and nothing older. Writing is throttled: a server
/// read every second is not a file written every second.
/// Used from the monitoring session's own thread, which is where the readings
/// are applied: the store is not shared, and no thread reaches into it.
final class NotchSplashHistoryStore {
    private let url: URL?
    private(set) var history: NotchSplashHistory = .empty
    /// When the file was last written, so a reading a second apart does not
    /// write a file a second apart.
    private var written: Date?
    /// How long a written file may go without being written again.
    static let writeInterval: TimeInterval = 30
    static let folderName = "Splash"
    static let fileName = "history.json"

    init(url: URL? = NotchSplashHistoryStore.defaultURL()) {
        self.url = url
    }

    /// Where the file lives: the app's own Application Support container, the
    /// Splash folder inside it.
    static func defaultURL() -> URL? {
        PrivateFileStore.containerURL?
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// Reads the file, if there is one, and drops what is out of its keeping.
    /// A file that cannot be read is a history that has not been kept: the
    /// dashboard starts measuring, and says it has no past.
    @discardableResult
    func load(now: Date = Date()) -> Bool {
        guard let url, let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(HistoryFile.self, from: data) else {
            history = .empty
            return false
        }
        history = NotchSplashHistory(samples: file.samples.map { $0.sample },
                                     days: file.days.map { $0.day },
                                     counters: file.counters)
        history.clean(now: now)
        return true
    }

    /// Records one reading, and writes the file when it is due. Reading and
    /// writing are done on the main thread, which is why writing is throttled:
    /// a server read every second is not a file written every second.
    func record(status: NotchSplashStatus, instanceKey: String, at date: Date,
                calendar: Calendar = .autoupdatingCurrent) {
        history.record(status: status, instanceKey: instanceKey, at: date, calendar: calendar)
        saveIfNeeded(at: date)
    }

    /// Thirty days kept, the rest deleted from the file, not only from the
    /// screen. Asked when a session starts and while it runs.
    func clean(now: Date) {
        guard history.clean(now: now) else { return }
        write(at: now)
    }

    func saveIfNeeded(at date: Date) {
        guard let written, date.timeIntervalSince(written) < Self.writeInterval else {
            write(at: date)
            return
        }
    }

    /// Writes now, whatever the throttle says: the end of a session, and the
    /// app's own way out.
    func flush(at date: Date = Date()) {
        write(at: date)
    }

    @discardableResult
    private func write(at date: Date) -> Bool {
        written = date
        guard let url else { return false }
        let file = HistoryFile(version: 1,
                               samples: history.samples.map(SampleFile.init(sample:)),
                               days: history.days.map(DayFile.init(day:)),
                               counters: history.counters)
        guard let data = try? JSONEncoder().encode(file) else { return false }
        let folder = url.deletingLastPathComponent()
        PrivateFileStore.createDirectory(at: folder)
        return PrivateFileStore.write(data, to: url)
    }

    // MARK: The file's shape

    /// Dates as whole seconds, keys as short as the figures: a month of
    /// readings is a file of a few hundred kilobytes, and readable by hand.
    struct HistoryFile: Codable {
        var version: Int
        var samples: [SampleFile]
        var days: [DayFile]
        var counters: NotchSplashHistory.NotchSplashCounters?
    }

    struct SampleFile: Codable {
        var t: Int
        var dc: Double?
        var d: Double?
        var pc: Double?
        var p: Double?
        var f: Double?
        var f95: Double?
        var c: Double?

        init(sample: NotchSplashSample) {
            t = Int(sample.at.timeIntervalSince1970)
            dc = sample.decodeCurrent
            d = sample.decode
            pc = sample.prefillCurrent
            p = sample.prefill
            f = sample.ttftSeconds
            f95 = sample.ttftP95Seconds
            c = sample.cachePercent
        }

        var sample: NotchSplashSample {
            NotchSplashSample(at: Date(timeIntervalSince1970: Double(t)),
                              decodeCurrent: dc, decode: d,
                              prefillCurrent: pc, prefill: p,
                              ttftSeconds: f, ttftP95Seconds: f95,
                              cachePercent: c)
        }
    }

    struct DayFile: Codable {
        var t: Int
        var i: Int64
        var o: Int64

        init(day: NotchSplashDay) {
            t = Int(day.start.timeIntervalSince1970)
            i = day.input
            o = day.output
        }

        var day: NotchSplashDay {
            NotchSplashDay(start: Date(timeIntervalSince1970: Double(t)), input: i, output: o)
        }
    }
}
