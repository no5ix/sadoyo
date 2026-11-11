// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreGraphics
import Foundation
import SwiftUI

// MARK: - The card's measurements

/// The dashboard card's own measurements, in points.
///
/// The card is drawn twice — on the page, and in the dashboard's Live
/// Activities section — and measured once. Its height is a value so the
/// island can size the page around it before it is drawn, as it does for every
/// card it carries.
enum NotchSplashLayout {
    /// The card's outer corner, and the corner of the four readings inside it.
    static let cornerRadius: CGFloat = 14
    static let metricCornerRadius: CGFloat = 10
    /// The card's edge to its content, on every side alike.
    static let padding: CGFloat = 10
    static let headerHeight: CGFloat = 20
    static let headerSpacing: CGFloat = 10
    /// The gap between the four readings: one gap, four columns, one row.
    static let metricSpacing: CGFloat = 8
    /// The gap between the card's sections: the readings, the memory, the
    /// trend, each a card of the reference.
    static let sectionSpacing: CGFloat = 10
    /// A reading is its name, its figure, its unit and the line of what it
    /// has measured: a card of its own, and taller than a row of text.
    static let metricCardHeight: CGFloat = 86
    /// The two figures of a card that measures, in the room its width has for
    /// them: a pair is read as one line, so it is set a little under a single
    /// figure and stays legible in a card of the same width as the rest.
    static let pairValueSize: CGFloat = 16
    /// The line a metric's measurements draw, in the height of a thumb.
    static let sparklineHeight: CGFloat = 22
    /// The memory's card: its name and the three readings in one row, and the
    /// governor's bar under them. The name and the numbers share a line, so the
    /// card is a glance and not a page, and it is shorter than the two rows it
    /// replaces were.
    static let memoryCardHeight: CGFloat = 74
    /// The trend's card: its name, the caption of the period, thirty bars,
    /// the dates, and the two names of the two colours.
    static let trendCardHeight: CGFloat = 124
    /// The bars themselves, between the caption of the period and the dates.
    static let trendBarsHeight: CGFloat = 60
    static let labelSize: CGFloat = 10
    static let valueSize: CGFloat = 22
    static let footerSize: CGFloat = 10
    static let headerSize: CGFloat = 13
    /// The mark that stands before the card's name, a little under the name's
    /// own size so the two read as one line.
    static let titleIconSize: CGFloat = 13
    static let readingSize: CGFloat = 11
    /// The memory card's three names, its figures, its units and its caption.
    static let memoryLabelSize: CGFloat = 10
    static let memoryValueSize: CGFloat = 18
    static let memoryUnitSize: CGFloat = 10.5
    static let sectionTitleSize: CGFloat = 11.5
    static let captionSize: CGFloat = 10
    /// The utilization bar, and the number beside it.
    static let utilizationBarHeight: CGFloat = 8
    /// The card as the page and the section measure it: the header's line, the
    /// four readings, the memory, and - on the page, where a month of bars has
    /// room to be pointed at - the trend.
    ///
    /// The compact card of the dashboard's Live Activities section is measured
    /// without the trend, because it draws none: a card measured with a chart it
    /// does not draw is a page of the wrong height, in the same way a card
    /// drawn and not measured is.
    static func cardHeight(compact: Bool = false) -> CGFloat {
        let core = padding * 2 + headerHeight + headerSpacing + metricCardHeight
            + sectionSpacing + memoryCardHeight
        return compact ? core : core + sectionSpacing + trendCardHeight
    }

    /// The page: the ruler's row, the card under it, and the gap between. The
    /// page's card is the whole card, trend and all - the compact card belongs
    /// to the dashboard, not to a page.
    ///
    /// This is the page of a reading that is not being read: a task frozen at
    /// its end, or a last reading kept after the way out, still sets its
    /// interval here, so the ruler is drawn and measured.
    static var pageHeight: CGFloat {
        NotchLayout.timerRulerHeight + NotchLayout.rowSpacing + cardHeight(compact: false)
    }

    /// The page of a session that is reading: the card, and nothing above it.
    /// The ruler set the interval before Start, and a running session takes a
    /// new one at once, so the page keeps no room for a control it does not
    /// draw - the same rule that left no ground for the words that went before.
    static var pageReadingHeight: CGFloat {
        cardHeight(compact: false)
    }

    /// The page before a session: the interval's ruler, and the ground under it
    /// and nothing else. The mark and the words that used to sit below said what
    /// Start does and does not do; the page's header, its ruler, its value and
    /// its Start say that, so the page is measured to what it draws and keeps no
    /// room for a block it no longer draws.
    static var pageSetupHeight: CGFloat {
        NotchLayout.timerRulerHeight + NotchLayout.rowSpacing + pageGroundHeight
    }

    /// The ground a page of one row keeps below it, which is the shortest ground
    /// the island's pages have ever kept.
    static let pageGroundHeight: CGFloat = NotchLayout.emptyHeight / 3

    /// The shortest page that stays usable: the ruler at its shortest, and
    /// the words that say what to do before Start.
    static var pageMinimumHeight: CGFloat {
        NotchLayout.timerMinimumRulerHeight + NotchLayout.rowSpacing + NotchLayout.emptyHeight / 3
    }

    /// The narrowest a reading stays readable, at its figure's own size.
    /// Below four of these the row keeps its four columns anyway and the
    /// figures scale down, which is what the page's narrowest preset allows.
    static let metricMinimumCardWidth: CGFloat = 92
}

// MARK: - Lenient JSON

/// A JSON value read without a schema.
///
/// A status endpoint answers with whatever its build reports, and a reading
/// is only as good as the fields it finds: a missing number is no reading,
/// not a zero. Reading the whole document as values first keeps that rule,
/// lets one field be spelled two ways, and lets a server that changes shape
/// be met with a smaller card instead of a failed request.
enum SplashJSON: Decodable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: SplashJSON])
    case array([SplashJSON])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .boolean(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([String: SplashJSON].self) { self = .object(value); return }
        if let value = try? container.decode([SplashJSON].self) { self = .array(value); return }
        self = .null
    }

    var object: [String: SplashJSON]? {
        if case .object(let values) = self { return values }
        return nil
    }

    var array: [SplashJSON]? {
        if case .array(let values) = self { return values }
        return nil
    }

    var string: String? {
        switch self {
        case .string(let value): return value
        case .boolean(let value): return value ? "true" : "false"
        case .number(let value):
            return value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
        default: return nil
        }
    }

    var double: Double? {
        switch self {
        case .number(let value): return value.isFinite ? value : nil
        case .boolean(let value): return value ? 1 : 0
        case .string(let value):
            let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
            return number?.isFinite == true ? number : nil
        default: return nil
        }
    }

    var int: Int? {
        guard let value = double, abs(value) < 1e15 else { return nil }
        return Int(value)
    }

    var int64: Int64? {
        guard let value = double, abs(value) < 9e18 else { return nil }
        return Int64(value)
    }

    var bool: Bool? {
        switch self {
        case .boolean(let value): return value
        case .number(let value): return value == 1 ? true : (value == 0 ? false : nil)
        case .string(let value):
            let word = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if word == "true" { return true }
            if word == "false" { return false }
            return nil
        default: return nil
        }
    }

    /// The first of `names` the document carries, skipping a field it spells
    /// as `null`.
    subscript(_ names: String...) -> SplashJSON? { field(names) }

    subscript(_ name: String) -> SplashJSON? {
        guard case .object(let values) = self else { return nil }
        let value = values[name]
        if let value, case .null = value { return nil }
        return value
    }

    func field(_ names: [String]) -> SplashJSON? {
        for name in names { if let value = self[name] { return value } }
        return nil
    }

    /// One step of a reading: the first name carried, read as one kind of
    /// value. A field that is absent, spelled `null`, or not of the kind is no
    /// reading at all, which the card shows as an empty place.
    func readDouble(_ names: [String]) -> Double? { field(names)?.double }
    func readInt(_ names: [String]) -> Int? { field(names)?.int }
    func readBytes(_ names: [String]) -> Int64? { field(names)?.int64 }
    func readText(_ names: [String]) -> String? { field(names)?.string }
    func readBool(_ names: [String]) -> Bool? { field(names)?.bool }
    func readArray(_ names: [String]) -> [SplashJSON]? { field(names)?.array }

    /// A document read from a response body, or nil for anything that is not
    /// a JSON object: an HTML error page, an empty body, a truncated stream.
    static func document(_ data: Data) -> SplashJSON? {
        guard !data.isEmpty, let value = try? JSONDecoder().decode(SplashJSON.self, from: data),
              value.object != nil else { return nil }
        return value
    }
}

/// The same steps on a reading that may be absent, so a chain of names is one
/// call whether the server carried the group it sits in or not.
extension Optional where Wrapped == SplashJSON {
    func field(_ names: [String]) -> SplashJSON? { self?.field(names) }
    func readDouble(_ names: [String]) -> Double? { self?.readDouble(names) }
    func readInt(_ names: [String]) -> Int? { self?.readInt(names) }
    func readBytes(_ names: [String]) -> Int64? { self?.readBytes(names) }
    func readText(_ names: [String]) -> String? { self?.readText(names) }
    func readBool(_ names: [String]) -> Bool? { self?.readBool(names) }
    func readArray(_ names: [String]) -> [SplashJSON]? { self?.readArray(names) }
}

// MARK: - The status reading

/// One reading of Splash's `/status`, as far as that build reported.
///
/// Nothing here is invented: every reading is optional, and a card shows a
/// placeholder for what the server did not answer. `activeRequestIDs` names
/// the requests the server says it is running now, in the order it gave
/// them; the task timer is built on those identities.
struct NotchSplashStatus: Equatable {
    struct Instance: Equatable {
        let id: String?
        let startedAt: Date?
    }

    struct Requests: Equatable {
        let completed: Int?
        let failed: Int?
        let cancelled: Int?

        static let empty = Requests(completed: nil, failed: nil, cancelled: nil)

        /// None of the three, which is a server that reports no counters at
        /// all and so cannot confirm a completion.
        var reportsNothing: Bool { completed == nil && failed == nil && cancelled == nil }
    }

    struct Metrics: Equatable {
        /// What the engine has moved on average over the whole of its running.
        let decodeTokensPerSecond: Double?
        let prefillTokensPerSecond: Double?
        /// What the engine says it is moving in the batch it has in hand now.
        ///
        /// These are the engine's own measurement of the batch, taken over the
        /// batch's own wall time, and they are the figure a card's first line
        /// shows. A batch that reports itself not valid, a server that carries
        /// no batch block, and a rate that is not a number are all no
        /// measurement, and the card leaves that line empty rather than
        /// borrowing the lifetime average for it.
        let currentDecodeBatchTokensPerSecond: Double?
        let currentPrefillBatchTokensPerSecond: Double?
        /// Time to first token, in milliseconds, at the p50 the server names.
        let ttftMilliseconds: Double?
        /// The same statistic at the p95, on a build that reports it.
        let ttftP95Milliseconds: Double?
        let prefillInputTokens: Int64?
        let decodeOutputTokens: Int64?
    }

    struct Cache: Equatable {
        let hits: Int?
        let requests: Int?
        /// The server's own rate, kept for a build that reports a rate and no
        /// counters.
        let reportedRate: Double?
    }

    struct KV: Equatable {
        let activeBytes: Int64?
        let pagesFree: Int?
        let pagesTotal: Int?
        let spilledBytes: Int64?
        let spillCount: Int?
        let reservationFailures: Int?
    }

    struct Memory: Equatable {
        let currentBytes: Int64?
    }

    struct Governor: Equatable {
        let limitBytes: Int64?
        let chargedBytes: Int64?
    }

    /// What the engine has in hand right now.
    ///
    /// The engine counts requests, not tasks: a coding agent's task is a run
    /// of requests with pauses between them, while it runs a tool, while it
    /// thinks, while its client composes the next prompt. So the card asks
    /// the one question the endpoint can answer - is this server doing
    /// anything, on any of the counts it keeps - and leaves the shape of a
    /// task to the run of readings, which is `NotchSplashTaskTracker`'s.
    struct Activity: Equatable {
        /// Requests the server names as running.
        let activeRequests: Int
        let queued: Int
        let prefilling: Int
        let decoding: Int
        /// Waiting for resources, for a prefix, for a mask, and in a terminal
        /// state not yet reaped: work that has not left the building.
        let waiting: Int
        /// Requests the server has accepted and not finished.
        let pending: Int
        /// Requests the front end holds: accepted and being served, and waiting
        /// there for the engine. This is the stretch between a client's prompt
        /// arriving and the scheduler naming it, which the scheduler's own
        /// counts do not cover.
        let frontend: Int
        /// Client requests in flight, which covers the time between a request
        /// arriving and the engine picking it up.
        let httpRequests: Int
        /// The engine is mid-loop and the answer is a snapshot: a snapshot
        /// that shows nothing running is not proof that nothing is.
        let statusIsStale: Bool

        static let quiet = Activity(activeRequests: 0, queued: 0, prefilling: 0, decoding: 0,
                                    waiting: 0, pending: 0, frontend: 0, httpRequests: 0,
                                    statusIsStale: false)

        var hasWork: Bool {
            activeRequests > 0 || queued > 0 || prefilling > 0 || decoding > 0 || waiting > 0
                || pending > 0 || frontend > 0 || httpRequests > 0 || statusIsStale
        }
    }

    let instance: Instance
    let activeRequestIDs: [String]
    let activity: Activity
    let requests: Requests
    let metrics: Metrics
    let cache: Cache
    let kv: KV
    let memoryActual: Memory
    let governor: Governor

    /// Reads one `/status` document. Names a server may spell a field in more
    /// than one way are all asked; a field it does not carry stays nil, and
    /// the card that shows that reading leaves the place empty.
    init(document: SplashJSON) {
        let root = document
        let instance = root.field(["instance"])
        self.instance = Instance(
            id: instance.readText(["id", "instance_id", "uuid"]) ?? root.readText(["instance_id", "instance"]),
            startedAt: NotchSplashStatus.date(instance.field(["started_at", "start_time", "created_at",
                                                              "boot_time"])
                ?? root.field(["started_at", "start_time"]))
        )
        activeRequestIDs = NotchSplashStatus.requestIDs(
            root.readArray(["active_requests", "running_requests"]))

        let scheduler = root.field(["scheduler", "scheduler_state"])
        let transport = root.field(["transport"])
        let frontend = root.field(["frontend", "front_end"])
        let http = root.field(["http"])
        activity = Activity(
            activeRequests: activeRequestIDs.count,
            queued: scheduler.readInt(["queued"]) ?? 0,
            prefilling: scheduler.readInt(["prefilling"]) ?? 0,
            decoding: scheduler.readInt(["decoding"]) ?? 0,
            waiting: ["waiting_resources", "waiting_prefix", "waiting_mask", "terminal"]
                .reduce(0) { total, name in total + (scheduler.readInt([name]) ?? 0) },
            pending: transport.readInt(["pending"]) ?? 0,
            frontend: (frontend.readInt(["active"]) ?? 0) + (frontend.readInt(["waiting"]) ?? 0),
            httpRequests: (http.field(["requests"]) ?? http).readInt(["active"]) ?? 0,
            statusIsStale: transport.readBool(["status_stale"]) ?? false
        )

        let counters = root.field(["requests"]) ?? root
        self.requests = Requests(
            completed: counters.readInt(["completed", "completed_total", "finished", "succeeded"]),
            failed: counters.readInt(["failed", "failed_total", "failures", "errors"]),
            cancelled: counters.readInt(["cancelled", "cancelled_total", "canceled", "aborted"])
        )

        let stats = root.field(["metrics", "stats", "statistics"]) ?? root
        let ttft = stats.field(["ttft_ms", "ttft", "time_to_first_token_ms", "time_to_first_token"])
        self.metrics = Metrics(
            decodeTokensPerSecond: stats.readDouble(["decode_tokens_per_second", "decode_tps",
                                                     "decode_throughput"])
                ?? root.readDouble(["decode_tokens_per_second"]),
            prefillTokensPerSecond: stats.readDouble(["prefill_tokens_per_second", "prefill_tps",
                                                      "prefill_throughput"])
                ?? root.readDouble(["prefill_tokens_per_second"]),
            currentDecodeBatchTokensPerSecond: Self.batchRate(stats.field(["current_decode_batch",
                                                                           "decode_batch", "live_decode_batch"])),
            currentPrefillBatchTokensPerSecond: Self.batchRate(stats.field(["current_prefill_batch",
                                                                            "prefill_batch", "live_prefill_batch"])),
            ttftMilliseconds: ttft.readDouble(["p50", "median", "p50_ms", "value"])
                ?? stats.readDouble(["ttft_ms", "ttft_ms_p50", "ttft"]),
            ttftP95Milliseconds: ttft.readDouble(["p95", "p95_ms", "percentile_95", "p095"])
                ?? stats.readDouble(["ttft_ms_p95", "ttft_p95_ms"]),
            prefillInputTokens: stats.readBytes(["prefill_input_tokens", "input_tokens", "prompt_tokens"])
                ?? root.readBytes(["prefill_input_tokens"]),
            decodeOutputTokens: stats.readBytes(["decode_output_tokens", "output_tokens", "completion_tokens"])
                ?? root.readBytes(["decode_output_tokens"])
        )

        let cache = root.field(["cache", "prefix_cache"])
        let hits = cache.readInt(["hits", "cache_hits", "hit_count"])
        let misses = cache.readInt(["misses", "cache_misses", "miss_count"])
        let lookups = cache.readInt(["requests", "cache_requests", "lookups", "queries"])
        self.cache = Cache(
            hits: hits,
            requests: lookups ?? (hits != nil && misses != nil ? hits! + misses! : nil),
            reportedRate: cache.readDouble(["hit_rate", "hit_ratio", "cache_hit_rate"])
        )

        let kv = root.field(["kv", "kv_cache"])
        let pages = kv.field(["pages"])
        self.kv = KV(
            activeBytes: kv.readBytes(["active_bytes", "bytes", "used_bytes"]) ?? root.readBytes(["kv_active_bytes"]),
            pagesFree: kv.readInt(["pages_free", "free_pages"]) ?? pages.readInt(["free"]),
            pagesTotal: kv.readInt(["pages_total", "pages", "total_pages"]) ?? pages.readInt(["total", "count"]),
            spilledBytes: kv.readBytes(["spilled_bytes", "spill_bytes"]) ?? root.readBytes(["kv_spilled_bytes"]),
            spillCount: kv.readInt(["spill_count", "spills"]) ?? root.readInt(["kv_spill_count"]),
            reservationFailures: kv.readInt(["reservation_failures", "failed_reservations", "reserve_failures"])
                ?? root.readInt(["kv_reservation_failures"])
        )

        let actual = root.field(["memory_actual", "memory"])
        self.memoryActual = Memory(currentBytes: actual.readBytes(["current_bytes", "bytes", "used_bytes"])
            ?? root.readBytes(["memory_actual_bytes"]))

        let governor = root.field(["memory_governor", "governor", "budget"])
        self.governor = Governor(
            limitBytes: governor.readBytes(["limit_bytes", "limit", "budget_bytes", "max_bytes"])
                ?? root.readBytes(["memory_governor_limit_bytes"]),
            chargedBytes: governor.readBytes(["charged_bytes", "charged", "used_bytes", "bytes"])
                ?? root.readBytes(["memory_governor_charged_bytes"])
        )
    }

    /// The requests a server says are running, named. An entry is an object
    /// with an id, a bare string, or a bare number. An entry with no name at
    /// all is given a standing name of its place, which is the best a server
    /// that reports no ids allows, and is recorded as a limitation.
    static func requestIDs(_ entries: [SplashJSON]?) -> [String] {
        guard let entries else { return [] }
        var ids: [String] = []
        for (index, entry) in entries.enumerated() {
            let id: String?
            switch entry {
            case .object(let values):
                id = ["id", "request_id", "uuid", "req_id", "rid"].compactMap { values[$0]?.string }.first
            case .string(let value):
                id = value.isEmpty ? nil : value
            case .number, .boolean:
                id = entry.string
            default:
                id = nil
            }
            ids.append(id ?? "position.\(index)")
        }
        return ids
    }

    /// The rate of the batch a server names, as the engine measured that batch.
    ///
    /// A batch block that says it is not valid carries a rate over work that
    /// has finished, and a block that answers no rate, a rate that is not a
    /// number, or a rate of nothing is no measurement of the present. Each of
    /// them answers nil, which is an empty line on the card, and never the
    /// lifetime average wearing a current figure's place.
    static func batchRate(_ batch: SplashJSON?) -> Double? {
        guard let batch else { return nil }
        if batch.readBool(["valid"]) == false { return nil }
        guard let rate = batch.readDouble(["tokens_per_second", "tps", "throughput"]),
              rate.isFinite, rate > 0 else { return nil }
        return rate
    }

    /// A timestamp as a server writes it: ISO 8601, epoch seconds, or epoch
    /// milliseconds.
    static func date(_ node: SplashJSON?) -> Date? {
        guard let node else { return nil }
        if let seconds = node.double {
            return Date(timeIntervalSince1970: seconds > 1e11 ? seconds / 1000 : seconds)
        }
        guard let text = node.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let seconds = Double(text) { return date(.number(seconds)) }
        let fraction = ISO8601DateFormatter()
        fraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    /// Anything in hand on any count the server keeps.
    var hasWork: Bool { activity.hasWork }

    /// The whole reading is unusable when it carries no shape at all: not one
    /// counter, not one metric, not one instance.
    var isReadable: Bool {
        instance.id != nil || !activeRequestIDs.isEmpty || !requests.reportsNothing
            || metrics.decodeTokensPerSecond != nil || metrics.prefillTokensPerSecond != nil
            || metrics.ttftMilliseconds != nil || metrics.prefillInputTokens != nil
            || metrics.decodeOutputTokens != nil || cache.hits != nil || cache.requests != nil
            || cache.reportedRate != nil || kv.activeBytes != nil || memoryActual.currentBytes != nil
            || governor.limitBytes != nil || governor.chargedBytes != nil
    }
}

// MARK: - Where the server is

enum NotchSplashEndpoint {
    /// The port the Splash app on this Mac answers on, offered when nothing
    /// has been typed yet.
    static let defaultPort = 8001
    /// The Splash server on this Mac, which is where the dashboard is asked
    /// to look before anyone has said otherwise.
    static let localHost = "127.0.0.1"
    /// The name a machine's own Splash key is handed to the app by, in the
    /// environment its session starts with. The app carries no key of its
    /// own: a key belongs to the machine it runs on, in the settings the
    /// person writes or in the environment the session starts with. The name
    /// of the variable is public; its value never is - not on the screen,
    /// not in a log, not in the source.
    static let localAPIKeyEnvironment = "VOSSAINT_SPLASH_API_KEY"

    /// A port as it is written in the field a person types it in.
    static func portText(_ port: Int) -> String { String(port) }
    static let portRange = 1...65_535
    static let maximumHostCharacters = 253

    /// What a person typed, without a scheme, a path, a port, or a stray
    /// space: the address the settings keep.
    static func host(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["http://", "https://", "tcp://", "ws://", "wss://"] where value.hasPrefix(scheme) {
            value = String(value.dropFirst(scheme.count))
        }
        if value.hasPrefix("["), let close = value.firstIndex(of: "]") {
            // An address that carries its own brackets keeps them: the port
            // after the closing bracket is taken off with the scheme.
            value = String(value[...close])
        }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        // A trailing :port, kept only when it is a port: an IPv6 address ends
        // in a bracket for exactly this reason.
        if let colon = value.lastIndex(of: ":"), !value[..<colon].contains(":"),
           Int(value[value.index(after: colon)...]) != nil {
            value = String(value[..<colon])
        }
        return value
    }

    /// The port a person meant, or nil when the text is not one.
    static func port(_ text: String) -> Int? {
        let number = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let number, portRange.contains(number) else { return nil }
        return number
    }

    /// A host name is letters, digits, and the dots, dashes, colons and
    /// brackets a literal address and a local name are written with.
    static func isLegalHost(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= maximumHostCharacters else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 45, 46, 58, 91, 93, 95: return true
            default: return false
            }
        }
    }

    /// The address to read, and nil when the settings are not a server.
    static func statusURL(host: String, port: Int) -> URL? {
        let name = Self.host(host)
        guard isLegalHost(name), portRange.contains(port) else { return nil }
        return URL(string: "http://\(name):\(port)/status")
    }

    static func isConfigured(host: String, port: Int) -> Bool { statusURL(host: host, port: port) != nil }

    /// A key is sent as a bearer token only when it is worth sending.
    static func authorization(_ apiKey: String) -> String? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : "Bearer \(key)"
    }
}

// MARK: - Readings and their colours

/// The colour a reading is written in.
///
/// The reference draws the dashboard in a small, fixed palette: green for
/// what is fast, blue for what flows in, purple for what the cache holds,
/// amber and red for what is running out. Keeping the palette a value lets
/// the thresholds be decided, and tested, apart from the drawing.
enum NotchSplashTone: Equatable {
    case green, blue, amber, red, purple, orange, beige, neutral
}

/// The dashboard's numbers, thresholds and formatting.
enum NotchSplashSupport {
    /// The interval a dashboard with nothing set reads at.
    static let defaultInterval = 1
    static let intervalRange = 1...10
    /// How far back the metric charts look: ten minutes of readings.
    ///
    /// This is the charts' span and nothing else. It is not a window a rate is
    /// measured over - the figures are the engine's own, answered with the
    /// reading - and the history file keeps far more than the chart shows.
    /// A reading older than this leaves the line, and nothing older is drawn.
    static let chartWindowSeconds: TimeInterval = 600
    /// A reading older than this many intervals is stale: the server stopped
    /// answering, and its last words are not evidence about the present.
    static let staleIntervalFactor = 3

    /// How long the engine must have been quiet before the run of work being
    /// timed is called over.
    ///
    /// The endpoint says nothing about tasks: it counts requests. A coding
    /// agent's task is a run of them, with a pause after each while it runs a
    /// tool, waits for an approval, or composes the next prompt, and the
    /// request counters move inside the run, so a request ending is not a run
    /// ending and one pause is not the end of the work. The only signal the
    /// endpoint gives is a quiet that has outlasted the pauses, so the window
    /// is a confirmation period of five minutes, and the app says what it
    /// knows - the activity ended - rather than a completion it was never
    /// told. Short idle gaps keep the run open; five minutes of nothing closes
    /// it.
    ///
    /// This window belongs to the dashboard. It is not Splash's own
    /// `weights.idle_release_seconds`, which is the engine deciding when to put
    /// its weights to sleep; the two mechanisms are asked separately and one
    /// setting does not move the other.
    static let taskIdleSeconds: TimeInterval = 5 * 60
    /// Quiet readings needed, one: the window is five minutes, and waiting
    /// through two of them would be ten minutes of a run whose work has
    /// already stopped - and the clock the card shows stops with the work, not
    /// with the window.
    static let taskIdleReadings = 1
    /// How often a long session re-applies the thirty-day keeping to the file.
    static let historyCleanupInterval: TimeInterval = 6 * 60 * 60

    // MARK: Settings

    /// The interval a stored value means, in range, at the default when the
    /// stored value is not one.
    static func interval(_ stored: Int?, in range: ClosedRange<Int> = intervalRange,
                         fallback: Int = defaultInterval) -> Int {
        guard let stored, range.contains(stored) else { return fallback }
        return stored
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.notchSplash.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchSplashEnabled)
    }

    static func savedInterval(in defaults: UserDefaults = .standard) -> Int {
        interval(defaults.object(forKey: DefaultsKey.notchSplashIntervalSeconds) as? Int)
    }

    /// The key a reading is sent with: the one written into the settings, or
    /// the machine's own key handed to the app in the environment. The settings
    /// keep it and never show it; it goes only to the address the settings name.
    static func savedAPIKey(in defaults: UserDefaults = .standard,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let saved = trimmedKey(defaults.string(forKey: DefaultsKey.notchSplashAPIKey))
        if !saved.isEmpty { return saved }
        return trimmedKey(environment[NotchSplashEndpoint.localAPIKeyEnvironment])
    }

    /// Whether a key is in use, which is all the settings say about it.
    static func hasAPIKey(in defaults: UserDefaults = .standard,
                          environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        !savedAPIKey(in: defaults, environment: environment).isEmpty
    }

    /// Only a key written into the settings can be taken back from them. The
    /// machine's own key, handed over in the environment, stays where it was
    /// given and comes back when the field is cleared.
    static func hasWrittenAPIKey(in defaults: UserDefaults = .standard) -> Bool {
        !trimmedKey(defaults.string(forKey: DefaultsKey.notchSplashAPIKey)).isEmpty
    }

    private static func trimmedKey(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func endpoint(in defaults: UserDefaults = .standard) -> URL? {
        let stored = defaults.integer(forKey: DefaultsKey.notchSplashPort)
        return NotchSplashEndpoint.statusURL(host: defaults.string(forKey: DefaultsKey.notchSplashHost) ?? "",
                                             port: stored != 0 ? stored : NotchSplashEndpoint.defaultPort)
    }

    // MARK: The card's rule

    /// Whether the dashboard's Live Activities section has a Splash card.
    ///
    /// The card stands for the reading, so the reading is the rule. It appears
    /// the moment Start begins the reading, and because a task's ending leaves
    /// the reading running, the card keeps its place across the idle stretch
    /// between two prompts - holding the finished task's frozen clock and its
    /// last numbers - and it leaves when the way out ends the reading, or when
    /// the section leaves the island.
    static func showsDashboardCard(sectionVisible: Bool, isMonitoring: Bool) -> Bool {
        sectionVisible && isMonitoring
    }

    /// Whether the closed island draws a reading: the section is on the island,
    /// and the card's clock is advancing.
    ///
    /// The clock is the question the island answers - is a run of work being
    /// watched now - and it is the same clock the card shows: advanced while the
    /// engine works, stopped at the first reading that found it quiet, and the
    /// run kept open through the confirmation window after that, while the card
    /// and the island both show the number the work came to. The island leaves
    /// when the window closes, because a run confirmed over is news and not
    /// work: the reading goes on, the server keeps answering, the dashboard keeps
    /// its card and its frozen numbers, and none of that is an activity. Nothing
    /// here watches the server, times out, or guesses from numbers that stop
    /// moving: the island asks the tracker the single question the card asks.
    static func showsIslandActivity(sectionVisible: Bool, isTaskRunning: Bool) -> Bool {
        sectionVisible && isTaskRunning
    }

    // MARK: Thresholds

    /// Decode speed is green at 70 tokens a second and red below it.
    static let decodeGreenThreshold = 70.0
    /// Prefill is green above 600 tokens a second, and red at or under it.
    static let prefillGreenThreshold = 600.0
    /// Time to first token is green under a second, red at a second and over.
    static let ttftGreenThreshold = 1.0
    /// Cache hits are green above 98%, amber from 95% through 98%, red below.
    static let cacheGreenThreshold = 98.0
    static let cacheAmberThreshold = 95.0
    /// Governor charge: green under 80%, amber from 80% to under 90%, red from 90%.
    static let governorAmberThreshold = 80.0
    static let governorRedThreshold = 90.0
    /// Governor headroom: green above 20%, amber from 10% to 20%, red below 10%.
    static let headroomAmberThreshold = 20.0
    static let headroomRedThreshold = 10.0
    /// The cache's pages are scarce under this share of the pool, or under
    /// this many pages, whichever the server reports.
    static let pagesScarceFraction = 0.10
    static let pagesScarceMinimum = 2

    static func decodeTone(_ tokensPerSecond: Double?) -> NotchSplashTone {
        guard let tokensPerSecond, tokensPerSecond.isFinite else { return .neutral }
        return tokensPerSecond >= decodeGreenThreshold ? .green : .red
    }

    static func prefillTone(_ tokensPerSecond: Double?) -> NotchSplashTone {
        guard let tokensPerSecond, tokensPerSecond.isFinite else { return .neutral }
        return tokensPerSecond > prefillGreenThreshold ? .green : .red
    }

    static func ttftTone(_ seconds: Double?) -> NotchSplashTone {
        guard let seconds, seconds.isFinite else { return .neutral }
        return seconds < ttftGreenThreshold ? .green : .red
    }

    static func cacheTone(_ percent: Double?) -> NotchSplashTone {
        guard let percent, percent.isFinite else { return .neutral }
        if percent > cacheGreenThreshold { return .green }
        if percent >= cacheAmberThreshold { return .amber }
        return .red
    }

    /// The governor's charge, as a percent of its limit. This is not the
    /// memory in use: the governor's ledger is a measurement of its own.
    static func governorUtilization(chargedBytes: Int64?, limitBytes: Int64?) -> Double? {
        guard let chargedBytes, let limitBytes, limitBytes > 0, chargedBytes >= 0 else { return nil }
        return Double(chargedBytes) / Double(limitBytes) * 100
    }

    static func governorUtilizationTone(_ percent: Double?) -> NotchSplashTone {
        guard let percent, percent.isFinite else { return .neutral }
        if percent >= governorRedThreshold { return .red }
        if percent >= governorAmberThreshold { return .amber }
        return .green
    }

    /// How much of its limit the governor has left uncharged.
    static func governorHeadroom(chargedBytes: Int64?, limitBytes: Int64?) -> Double? {
        guard let percent = governorUtilization(chargedBytes: chargedBytes, limitBytes: limitBytes) else { return nil }
        return max(0, 100 - percent)
    }

    static func memoryPressureTone(headroomPercent: Double?) -> NotchSplashTone {
        guard let headroomPercent, headroomPercent.isFinite else { return .neutral }
        if headroomPercent < headroomRedThreshold { return .red }
        if headroomPercent <= headroomAmberThreshold { return .amber }
        return .green
    }

    /// The cache's own tone. Using the cache is its job, so a full cache is
    /// not a warning: what warns is the pool running short of pages, and what
    /// is an alarm is spilling and reservations that failed.
    static func kvTone(pagesFree: Int?, pagesTotal: Int?, spilling: Bool,
                       reservationFailures: Int?) -> NotchSplashTone {
        // A server that has run out of pages, and a server whose pages have
        // gone past being gone, are both out of room: the first spills, the
        // second says the arithmetic itself has broken.
        if (reservationFailures ?? 0) > 0 || spilling { return .red }
        if let pagesFree, pagesFree < 0 { return .red }
        if let pagesFree, pagesFree <= pagesScarceMinimum { return .amber }
        if let pagesFree, let pagesTotal, pagesTotal > 0,
           Double(pagesFree) / Double(pagesTotal) < pagesScarceFraction { return .amber }
        return .purple
    }

    /// The cache's hit rate from the counters: hits out of requests.
    ///
    /// A server that reports only its own rate is read as it writes it: a
    /// number at or below 1 is a fraction of the requests, a larger one is
    /// already a percent. Counters answer first, because they are the
    /// dashboard's rule.
    static func cacheHitPercent(hits: Int?, requests: Int?, reportedRate: Double? = nil) -> Double? {
        if let hits, let requests, requests > 0, hits >= 0 {
            return min(100, Double(hits) / Double(requests) * 100)
        }
        guard let reportedRate, reportedRate.isFinite, reportedRate >= 0 else { return nil }
        return min(100, reportedRate <= 1 ? reportedRate * 100 : reportedRate)
    }

    // MARK: Words

    static let placeholder = "\u{2014}"

    /// The figures follow the reader's region, as every other number in the
    /// app does: macOS keeps the region and the language apart, and a decimal
    /// is written with a comma in most of the languages here.
    static var locale: Locale { MetricFormat.locale }

    /// A throughput, as the reference reads it: two decimals under a hundred.
    static func speedText(_ tokensPerSecond: Double?, locale: Locale = locale) -> String {
        guard let tokensPerSecond, tokensPerSecond.isFinite else { return placeholder }
        let magnitude = abs(tokensPerSecond)
        if magnitude >= 1000 { return String(format: "%.0f", locale: locale, tokensPerSecond) }
        if magnitude >= 100 { return String(format: "%.1f", locale: locale, tokensPerSecond) }
        return String(format: "%.2f", locale: locale, tokensPerSecond)
    }

    // MARK: The pair of figures a measuring card shows

    /// Two figures on one line, `85.32 / 50.97`, in the order the card shows
    /// them. A figure the server did not answer keeps its place empty, so a
    /// pair is never shown as one figure and never as an invented one.
    static func pairText(_ first: String?, _ second: String?) -> String? {
        guard first != nil || second != nil else { return nil }
        return "\(first ?? placeholder) / \(second ?? placeholder)"
    }

    /// The two throughputs of a speed card: what is being measured now, and the
    /// engine's own average over the whole of its running.
    static func speedPairText(_ current: Double?, _ overall: Double?, locale: Locale = locale) -> String? {
        pairText(current == nil ? nil : speedText(current, locale: locale),
                 overall == nil ? nil : speedText(overall, locale: locale))
    }

    /// The first token's time at its two percentiles, in the order the card
    /// writes them: p50 first and p95 second, whatever order its lines draw
    /// them in.
    static func ttftPairText(_ p50: Double?, _ p95: Double?, locale: Locale = locale) -> String? {
        pairText(p50 == nil ? nil : ttftParts(p50, locale: locale)?.value,
                 p95 == nil ? nil : ttftParts(p95, locale: locale)?.value)
    }

    /// The decode speed the island's strip writes: a whole number, and the
    /// unit the splash page uses for a throughput, so the strip and the card
    /// name the same thing in the reader's language.
    ///
    /// The strip is the menu bar's room, so it writes the figure against the
    /// unit with no space in it - `53t/s` - where the card, which has room,
    /// keeps the space between a number and its unit. The strip's shape is
    /// measured from "888t/s", the widest reading of the widest language.
    static func stripSpeedText(_ tokensPerSecond: Double?,
                               language: AppLanguage = .enUS) -> String? {
        guard let tokensPerSecond, tokensPerSecond.isFinite, tokensPerSecond >= 0 else { return nil }
        return "\(Int(tokensPerSecond.rounded(.down)))\(FeatureStrings.notchSplash(language).tokensPerSecond)"
    }

    /// Time to first token, in seconds with its unit.
    static func ttftText(_ seconds: Double?, locale: Locale = locale) -> String {
        guard let parts = ttftParts(seconds, locale: locale) else { return placeholder }
        return parts.value + " " + parts.unit
    }

    /// The same figure split into its number and its unit, so a card can set
    /// the number at its own size and the unit at a smaller one. The two
    /// joined are what `ttftText` writes.
    static func ttftParts(_ seconds: Double?, locale: Locale = locale) -> (value: String, unit: String)? {
        guard let seconds, seconds.isFinite else { return nil }
        let format = seconds >= 10 ? "%.0f" : "%.1f"
        return (String(format: format, locale: locale, seconds), "s")
    }

    static func ttftSeconds(milliseconds: Double?) -> Double? {
        guard let milliseconds, milliseconds.isFinite, milliseconds >= 0 else { return nil }
        return milliseconds / 1000
    }

    /// A percent, to two decimals: `96.23%`.
    static func percentText(_ percent: Double?, locale: Locale = locale) -> String {
        guard let percent, percent.isFinite else { return placeholder }
        return String(format: "%.2f%%", locale: locale, percent)
    }

    /// A token count at the size the header has room for: `134K`, `1.2M`.
    static func tokensText(_ tokens: Int64?, locale: Locale = locale) -> String {
        guard let tokens, tokens >= 0 else { return placeholder }
        let value = Double(tokens)
        if value >= 1_000_000_000 { return compact(value / 1_000_000_000, "B", locale: locale) }
        if value >= 1_000_000 { return compact(value / 1_000_000, "M", locale: locale) }
        if value >= 1_000 { return compact(value / 1_000, "K", locale: locale) }
        return String(tokens)
    }

    /// A number written short, and without the zeros a whole number would get:
    /// a count of tokens is read as a figure, and "1.50" is written "1.5".
    private static func compact(_ value: Double, _ unit: String, locale: Locale) -> String {
        let text = value >= 100 ? String(format: "%.0f", locale: locale, value)
            : value >= 10 ? String(format: "%.1f", locale: locale, value)
            : String(format: "%.2f", locale: locale, value)
        return trimmed(text, locale: locale) + unit
    }

    private static func trimmed(_ text: String, locale: Locale) -> String {
        let separator = locale.decimalSeparator ?? "."
        guard text.contains(separator) else { return text }
        var value = text
        while value.hasSuffix("0") { value.removeLast() }
        if value.hasSuffix(separator) { value.removeLast() }
        return value
    }

    /// Bytes in the unit a card has room for.
    static func bytesText(_ bytes: Int64?, locale: Locale = locale) -> (value: String, unit: String)? {
        guard let bytes, bytes >= 0 else { return nil }
        let value = Double(bytes)
        if value >= 1_073_741_824 { return (String(format: "%.1f", locale: locale, value / 1_073_741_824), "GiB") }
        if value >= 1_048_576 { return (String(format: "%.1f", locale: locale, value / 1_048_576), "MiB") }
        if value >= 1024 { return (String(format: "%.1f", locale: locale, value / 1024), "KiB") }
        return (String(format: "%.0f", locale: locale, value), "B")
    }

    /// The task's clock: `23m 21s`, and `00:00` before a task has begun.
    /// A clock is a clock: its digits are the same in every region.
    static func taskClock(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else { return "00:00" }
        let whole = Int(interval.rounded(.down))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let seconds = whole % 60
        if hours > 0 { return String(format: "%dh %02dm %02ds", locale: Locale(identifier: "en_US_POSIX"), hours, minutes, seconds) }
        if minutes > 0 { return String(format: "%dm %02ds", locale: Locale(identifier: "en_US_POSIX"), minutes, seconds) }
        return String(format: "%02d:%02d", locale: Locale(identifier: "en_US_POSIX"), minutes, seconds)
    }

    /// The interval a monitoring session polls at, written short.
    static func intervalText(_ seconds: Int) -> String { "\(seconds)s" }

    /// The number written under a ruler's tick: the whole seconds alone. The
    /// unit belongs to the value read out beside the ruler and to the words
    /// about it, not to ten ticks that would overlap each other wearing it.
    static func tickIntervalText(_ seconds: Int) -> String { "\(seconds)" }
}

// MARK: - The card's colours

/// The reference's colours, as one small set.
///
/// The card is drawn on the island's black, so the palette is the set the
/// reference reads at that depth: the beige of its title, the blue and the
/// green of its arrows, the purple of the cache, the orange of the limit, and
/// the amber and the red of what is running out.
///
/// The palette is a rule and not a layout: a figure's colour follows from its
/// thresholds, so a page only asks what colour a reading is.
enum NotchSplashPalette {
    static let beige = Color(red: 0.827, green: 0.773, blue: 0.667)
    static let blue = Color(red: 0.376, green: 0.647, blue: 0.980)
    static let green = Color(red: 0.298, green: 0.784, blue: 0.286)
    static let purple = Color(red: 0.678, green: 0.467, blue: 0.925)
    static let orange = Color(red: 0.969, green: 0.580, blue: 0.157)
    static let amber = Color(red: 0.976, green: 0.749, blue: 0.271)
    static let red = Color(red: 0.949, green: 0.329, blue: 0.310)
    static let neutral = Color.white.opacity(0.55)

    /// The colour of a figure with no tone of its own rests in the reference's beige.
    static let resting = beige

    /// Which of a measuring card's two lines a figure belongs to.
    ///
    /// The decode and prefill cards write the batch in hand first and the average
    /// over the engine's running second; the first token's card writes the p50
    /// first and the p95 second, because the lower percentile is the case a person
    /// reads as usual and the tail is the one they read after it.
    enum NotchSplashMeasurement {
        case decode, prefill, ttft
    }

    /// The colour of a card's two figures, each the colour of the line it is
    /// drawn from, so a pair of numbers needs no key. A card's two figures keep
    /// the same two colours in the same two places: the figure written first is
    /// purple and the figure written second is green. The two throughput cards
    /// write the batch in hand first, in purple, and the average over the
    /// engine's running second, in green. The first token's card writes its
    /// percentiles in the other pair's words - p50 first, in purple, and p95
    /// second, in green - because the lower percentile is the case a person
    /// reads as usual and the tail is the one they read after it.
    static func figureTints(_ measurement: NotchSplashMeasurement) -> (first: Color, second: Color) {
        _ = measurement
        return (purple, green)
    }

    /// The colour of a card's two lines: the leading line, which is the batch in
    /// hand for the two throughputs and the p95 for the first token's time, and
    /// the average's line beside it, which for the first token's time is the
    /// p50. The batch in hand and the p50 are the purple line in all three cards
    /// and the average over the running and the p95 are the green, so a figure
    /// is the colour of the line it is drawn from in every card: the throughput
    /// cards' first figure is the purple batch in hand, and the first token's
    /// card's first figure is the purple p50.
    static func lineTints(_ measurement: NotchSplashMeasurement) -> (leading: Color, average: Color) {
        switch measurement {
        case .decode, .prefill: return (purple, green)
        // The first token's card draws its tail, the p95, in green and its
        // middle, the p50, in purple, which is the way round the figures are
        // written: p50 first in purple, p95 second in green.
        case .ttft: return (green, purple)
        }
    }

    /// The colour of a figure. `reference` is the colour the figure has when
    /// it carries no warning — the cache’s purple, the governor’s orange — so
    /// the cache is only recoloured when its pages run out, and the limit only
    /// deepens from its own orange as its headroom goes. A figure that needs no
    /// reference (a throughput, an arrow) keeps its own tone.
    static func tone(_ tone: NotchSplashTone, reference: Color? = nil) -> Color {
        switch tone {
        case .neutral: return reference ?? neutral
        case .green: return reference ?? green
        case .amber: return amber
        case .red: return red
        case .blue: return blue
        case .purple: return purple
        case .beige: return beige
        case .orange: return orange
        }
    }
}

// MARK: - Monitoring and task state

/// Why the last reading did not arrive.
enum NotchSplashFailure: Equatable {
    case notConfigured
    case unreachable
    case status(Int)
    case unreadable
    case stale
}

/// One reading, with the moment it was taken.
struct NotchSplashSnapshot: Equatable {
    let status: NotchSplashStatus
    let fetchedAt: Date

    /// The instance this reading belongs to, so a restart is visible.
    var instanceKey: String {
        if let id = status.instance.id, !id.isEmpty { return "id:\(id)" }
        if let started = status.instance.startedAt { return "started:\(Int64(started.timeIntervalSince1970))" }
        return "unidentified"
    }
}

/// The task the dashboard times, and what became of it.
///
/// Monitoring and a task are two things. Monitoring is the polling a person
/// started; a task is a run of work the engine is doing. The clock belongs to
/// the run: it begins at the first request, runs on through the pauses
/// between requests, and freezes at the last work seen once the server has
/// been quiet long enough for the quiet to be the end of the task. A next
/// request begins the next run, at zero.
///
/// The engine has no word for a task - it counts requests - so the run is
/// what the readings say: work on any count the server keeps, and a quiet
/// that has outlasted the pauses between turns. A request completing in the
/// middle of a run is a request completing, and moves nothing: that is the
/// whole point of the window.
///
/// The client's own conversation file was weighed as a second witness and left
/// out: the endpoint names requests and an instance and nothing that ties a
/// request to a conversation, the file is written at event boundaries and so
/// keeps still through a long generation, and one conversation is many
/// requests. `docs/decisions/0001-splash-task-liveness-from-status.md` keeps the
/// whole of that reasoning, and the readings' rule with it.
struct NotchSplashTaskTracker {
    enum Outcome: Equatable {
        case completed, failed, cancelled, lost
    }

    enum Phase: Equatable {
        case idle
        case running(id: String, startedAt: Date)
        case finished(id: String, outcome: Outcome, at: Date, elapsed: TimeInterval)
    }

    /// What a poll decided, so the service acts on it once.
    enum Event: Equatable {
        case started(id: String, at: Date)
        case finished(id: String, outcome: Outcome, at: Date, elapsed: TimeInterval)
    }

    /// The marks a card's header shows for one task: the tokens the engine
    /// moved across this task, and nothing else.
    ///
    /// The engine's own counters are cumulative over its whole life, and a card
    /// in a header is a glance at the work being timed. So the header is the
    /// difference between the counters as they stand and as they stood when the
    /// task began, kept over the task's several requests, and frozen when the
    /// task ends. The counters never go down: a run's total is only ever added
    /// to, and an engine that begins again is rebased where it began again.
    ///
    /// This is not the thirty days. The daily trend is the same engine's
    /// counters kept day by day in the app's own file, and a task beginning
    /// takes nothing away from it.
    struct TaskTokens: Equatable {
        let input: Int64
        let output: Int64

        static let zero = TaskTokens(input: 0, output: 0)
        var isEmpty: Bool { input == 0 && output == 0 }
        /// The task's whole: what the engine moved in and out across it.
        var total: Int64 { input + output }
    }

    /// The counters as they stood when the run began, and the server it was
    /// read from.
    private struct Baseline: Equatable {
        let completed: Int
        let failed: Int
        let cancelled: Int
        let instanceKey: String
    }

    private(set) var phase: Phase = .idle
    /// The task's tokens, as the header shows them: counted while the task
    /// runs, frozen at its end, and zero before a task has begun.
    private(set) var taskTokens = TaskTokens.zero
    /// The tokens the run has measured so far, and the counters the last
    /// reading carried. The two together are what makes a counter that went
    /// down - an engine restarted, a counter reset - a new baseline rather
    /// than a subtraction, and what keeps a run's figures from going negative.
    private var runInput = Int64(0)
    private var runOutput = Int64(0)
    private var lastInputTokens: Int64?
    private var lastOutputTokens: Int64?
    private var baseline: Baseline?
    /// The first reading that showed nothing running: the task's length is
    /// measured to it, because the work ended somewhere between the reading
    /// that saw it and this one, and a clock that measured to the last sight
    /// of the work would be short by the whole width of a reading.
    private var firstQuietAt: Date?
    /// Readings in a row that showed nothing running.
    private var quietReadings = 0
    /// The spill counter last seen, so a counter that grew is a spill now.
    private var lastSpillCount: Int?

    /// Spilling, sustained: the counter grew between two readings.
    private(set) var isSpilling = false

    private let quiescence: TimeInterval
    private let quietReadingsNeeded: Int
    /// The counters of the reading before this one, which is how a run is
    /// noticed at all when the server answers faster than the interval.
    private var lastRequests: NotchSplashStatus.Requests?

    init(quiescence: TimeInterval = NotchSplashSupport.taskIdleSeconds,
         quietReadingsNeeded: Int = NotchSplashSupport.taskIdleReadings) {
        self.quiescence = quiescence
        self.quietReadingsNeeded = max(1, quietReadingsNeeded)
    }

    /// A monitoring session beginning: the clock starts over, and so does the
    /// reading of the counters.
    mutating func begin() {
        phase = .idle
        lastRequests = nil
        baseline = nil
        firstQuietAt = nil
        quietReadings = 0
        lastSpillCount = nil
        isSpilling = false
        resetTaskTokens()
    }

    /// A finished task cleared, so a page returns to its Start state.
    mutating func clearFinished() {
        guard case .finished = phase else { return }
        phase = .idle
        baseline = nil
        firstQuietAt = nil
        quietReadings = 0
        resetTaskTokens()
    }

    /// The task's figures, back to nothing: the clock is back to nothing too,
    /// and a header that shows a task shows the task's own.
    private mutating func resetTaskTokens() {
        taskTokens = .zero
        runInput = 0
        runOutput = 0
        lastInputTokens = nil
        lastOutputTokens = nil
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    var isFinished: Bool {
        if case .finished = phase { return true }
        return false
    }

    /// The clock's value: a running task's length so far, a finished task's
    /// frozen length, and nothing at all with no task.
    ///
    /// A run that has gone quiet is timed to the first reading that found
    /// nothing running, and not to the moment its confirmation window closes:
    /// the idle confirmation is not task time, so a task that worked for eleven
    /// minutes is shown as eleven minutes while the window runs, and freezes at
    /// the same number the window closes on. Work seen again lifts the clock off
    /// that mark and it goes on from the work's own beginning.
    func elapsed(at date: Date) -> TimeInterval {
        switch phase {
        case .idle: return 0
        case .running(_, let startedAt):
            if let quiet = firstQuietAt { return max(0, quiet.timeIntervalSince(startedAt)) }
            return max(0, date.timeIntervalSince(startedAt))
        case .finished(_, _, _, let elapsed): return max(0, elapsed)
        }
    }

    /// The request being timed, if one is.
    var trackedID: String? {
        switch phase {
        case .idle: return nil
        case .running(let id, _): return id
        case .finished(let id, _, _, _): return id
        }
    }

    /// Whether the engine's counters moved since the reading before: a request
    /// completed, failed, or cancelled. A generation shorter than the interval
    /// between readings never appears as an active request in any reading, and
    /// its counters are all that is left of it, so the counters are how such a
    /// request is noticed at all - they open a run. They do not keep one open:
    /// the counters are cumulative, so a busy neighbour's work, measured
    /// against the reading before, would hold a finished run open forever. What
    /// a run is doing now is answered by the fields that name work in hand.
    private func countersGrew(_ incoming: NotchSplashStatus.Requests) -> Bool {
        guard let last = lastRequests else { return false }
        func grew(_ before: Int?, _ after: Int?) -> Bool {
            guard let before, let after else { return false }
            return after > before
        }
        return grew(last.completed, incoming.completed)
            || grew(last.failed, incoming.failed)
            || grew(last.cancelled, incoming.cancelled)
    }

    /// One reading, taken at `date`.
    ///
    /// Work seen while nothing is being timed opens a run. Work seen while a
    /// finished task holds the card opens the next run, at zero, with the
    /// counters read from where they stand: nothing about the finished task
    /// is carried into it, and a server that numbers its requests by position
    /// cannot make the second task look like the first.
    ///
    /// A run is called over only by a quiet that has outlasted the window,
    /// and what it was is decided by what the counters did across the whole
    /// run: a completed count that grew is a completion, a failed or
    /// cancelled count that grew with no completion is that, a server that
    /// restarted underneath the run is a run it cannot speak for, and a run
    /// the counters say nothing about is lost and is never announced as a
    /// completion.
    mutating func observe(_ snapshot: NotchSplashSnapshot, at date: Date) -> Event? {
        let status = snapshot.status
        isSpilling = spillsGrew(status.kv.spillCount)
        // What the engine says it is doing now: requests running, queued,
        // prefilling, decoding, waiting for resources, in flight over the
        // front end, pending in the transport, and a snapshot taken mid-loop.
        let work = status.hasWork
        // Counters that moved are how a request shorter than the polling
        // interval is noticed, and they open a run; they are not evidence that
        // a run is busy, which is what the quiet window measures.
        let openedWork = work || countersGrew(status.requests)
        lastRequests = status.requests
        switch phase {
        case .idle, .finished:
            guard openedWork else { return nil }
            return start(id: status.activeRequestIDs.first ?? NotchSplashTaskTracker.unnumbered,
                         at: date, snapshot: snapshot)

        case .running(let id, let startedAt):
            // The task's counters are read at every reading of the run, quiet
            // ones included: a counter that moved is work the engine did, and
            // a run's figures are the whole span of the run and not only the
            // readings that found it busy.
            advanceTokens(input: status.metrics.prefillInputTokens,
                          output: status.metrics.decodeOutputTokens)
            if work {
                // Work in hand cancels the confirmation window and the clock
                // lifts off the mark it had rested at.
                firstQuietAt = nil
                quietReadings = 0
                return nil
            }
            quietReadings += 1
            if quietReadings == 1 { firstQuietAt = date }
            let quietFrom = firstQuietAt ?? startedAt
            guard quietReadings >= quietReadingsNeeded,
                  date.timeIntervalSince(quietFrom) >= quiescence else { return nil }
            return finish(id: id, outcome: judge(status, snapshot: snapshot),
                          at: quietFrom, startedAt: startedAt)
        }
    }

    /// A server that reports work without naming it: the run is real, and it
    /// has no identity beyond its start.
    static let unnumbered = "unnumbered"

    private mutating func start(id: String, at date: Date, snapshot: NotchSplashSnapshot) -> Event {
        let counters = snapshot.status.requests
        phase = .running(id: id, startedAt: date)
        baseline = Baseline(completed: counters.completed ?? 0, failed: counters.failed ?? 0,
                            cancelled: counters.cancelled ?? 0, instanceKey: snapshot.instanceKey)
        firstQuietAt = nil
        quietReadings = 0
        // The task begins at nothing, and from here the engine's cumulative
        // counters are read against this moment: the header's figures and the
        // clock start together, at the same instant, and an intermediate request
        // of the same task adds to them without starting them over.
        resetTaskTokens()
        lastInputTokens = snapshot.status.metrics.prefillInputTokens
        lastOutputTokens = snapshot.status.metrics.decodeOutputTokens
        return .started(id: id, at: date)
    }

    /// One reading's tokens, added to the run.
    ///
    /// The rule is a difference, and the difference is kept honest four ways:
    /// a counter the server does not report adds nothing and asks for nothing;
    /// a counter that grew adds what it grew by; a counter that went down, or
    /// came from an engine the run did not begin in, is a fresh baseline at the
    /// reading and adds nothing - it is never subtracted, because a task that
    /// used sixty tokens does not un-use them; and a figure the run has already
    /// measured is never lowered, so the header never shows a negative and never
    /// shows less than the task did.
    private mutating func advanceTokens(input: Int64?, output: Int64?) {
        func advance(_ current: Int64?, _ last: inout Int64?, _ total: inout Int64) {
            guard let current, current >= 0 else { return }
            if let previous = last, current > previous {
                total += current - previous
            }
            // The next reading's difference is measured from this one, so a
            // run's tokens are counted once each. A counter that came in below
            // the mark is a counter begun again - an engine restarted, a
            // counter reset: the run keeps what it measured and is measured on
            // from here, which adds nothing and takes nothing away.
            last = current
        }
        advance(input, &lastInputTokens, &runInput)
        advance(output, &lastOutputTokens, &runOutput)
        taskTokens = TaskTokens(input: runInput, output: runOutput)
    }

    private func judge(_ status: NotchSplashStatus, snapshot: NotchSplashSnapshot) -> Outcome {
        // The server changed under the run: what became of it is not known.
        if let baseline, baseline.instanceKey != snapshot.instanceKey { return .lost }
        let counters = status.requests
        if counters.reportsNothing { return .lost }
        let previous = baseline ?? Baseline(completed: counters.completed ?? 0,
                                            failed: counters.failed ?? 0,
                                            cancelled: counters.cancelled ?? 0,
                                            instanceKey: snapshot.instanceKey)
        if (counters.completed ?? previous.completed) > previous.completed { return .completed }
        if (counters.failed ?? previous.failed) > previous.failed { return .failed }
        if (counters.cancelled ?? previous.cancelled) > previous.cancelled { return .cancelled }
        // The engine went quiet with no counter moved: a run this reading
        // cannot call a completion.
        return .lost
    }

    private mutating func finish(id: String, outcome: Outcome, at date: Date, startedAt: Date) -> Event {
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        phase = .finished(id: id, outcome: outcome, at: date, elapsed: elapsed)
        baseline = nil
        firstQuietAt = nil
        quietReadings = 0
        // The clock freezes at the task's length, and the task's tokens freeze
        // with it: the header keeps the figures of the task that ended until
        // the next one begins, which begins them again at nothing.
        taskTokens = TaskTokens(input: runInput, output: runOutput)
        return .finished(id: id, outcome: outcome, at: date, elapsed: elapsed)
    }

    /// The key a finished task is told by: its request's id and the second it
    /// began. A server that numbers its requests by position hands out the
    /// same id all day, so the id alone would make the second task's news
    /// old news, while the pair is the task itself - and one task, told once.
    static func announceKey(id: String, at date: Date, elapsed: TimeInterval) -> String {
        "\(id)@\(Int64(max(0, date.timeIntervalSince1970 - elapsed)))"
    }

    private mutating func spillsGrew(_ count: Int?) -> Bool {
        defer { if let count { lastSpillCount = count } }
        guard let count, let last = lastSpillCount else { return false }
        return count > last
    }
}

/// The rule for when the polling may end.
///
/// Monitoring is a promise the Start button makes and a person takes back.
/// It keeps reading while Splash sits idle between two prompts, and it keeps
/// reading through a task that finished, failed, or was cancelled: those are
/// the dashboard's news, not its end. The three reasons the reading ends are
/// a hand on the way out, the section switched off, and an address taken
/// away. The idle time and the last task's ending are carried in the
/// condition so that this rule, and not a timeout, is what the loop asks -
/// and so that a test can ask it about an idle afternoon.
enum NotchSplashMonitoringPolicy {
    struct Condition: Equatable {
        /// The person pressed the way out on the card or the page.
        var stoppedByHand = false
        /// The section is switched off.
        var sectionDisabled = false
        /// There is no server left to read.
        var noAddress = false
        /// How long the server has had nothing running, in seconds.
        var idleSeconds: TimeInterval = 0
        /// What became of the last task timed, if one was.
        var outcome: NotchSplashTaskTracker.Outcome?
    }

    static func endsMonitoring(_ condition: Condition) -> Bool {
        condition.stoppedByHand || condition.sectionDisabled || condition.noAddress
    }
}

/// Which finished tasks are announced, and once.
///
/// A completion is announced the first time it is confirmed and never again,
/// by the task's own key: its request's id and the second it began (see
/// `NotchSplashTaskTracker.announceKey`). A page reopened, a poll repeated,
/// and a status read twice are all reasons the same news could arrive twice;
/// a second task is a second key, and is news in its own right.
struct NotchSplashAnnouncements {
    private var announced: Set<String> = []

    /// Whether this finished task is news, taking it when it is.
    mutating func take(id: String, outcome: NotchSplashTaskTracker.Outcome) -> Bool {
        guard outcome == .completed, !announced.contains(id) else { return false }
        announced.insert(id)
        return true
    }

    /// Whether this failed or cancelled task is news, taking it when it is.
    mutating func takeUnsuccessful(id: String, outcome: NotchSplashTaskTracker.Outcome) -> Bool {
        guard outcome == .failed || outcome == .cancelled, !announced.contains(id) else { return false }
        announced.insert(id)
        return true
    }

    var announcedIDs: Set<String> { announced }

    mutating func reset() { announced.removeAll() }
}

// MARK: - The monitoring session

/// Reads Splash's `/status` on the interval a person chose, and keeps the
/// dashboard's two states apart: the monitoring the Start button began, and
/// the request the island times.
///
/// The monitoring is a reader only. It never sends Splash anything but the
/// request for a status, so starting it generates nothing, and stopping it
/// cancels nothing — a generation already running in Splash goes on running.
///
/// It is also a promise kept until a hand takes it back. The polling goes on
/// while Splash is idle, goes on through a task that finished, and is ended
/// only by the way out on the card, by the section switched off, or by its
/// address taken away. The clock belongs to the task and the reading belongs
/// to the person who started it, and neither one's ending is the other's.
///
/// Reading is asked off the main thread and reported on the main thread, and
/// the reading is turned into decisions by `NotchSplashTaskTracker`, which
/// holds no thread and no request of its own.
final class NotchSplashService: ObservableObject {
    /// A status asked and answered: the document, and the answer's code.
    typealias StatusAnswer = (data: Data, code: Int)
    /// How a status is asked, with the address, the time to wait, and the key.
    ///
    /// The app asks a server over HTTP. A test answers with a document it
    /// made. The polling, the task, the freezing, and the notices are the same
    /// code in both, which is the point: the promise that a reading goes on
    /// across an idle afternoon is tested as the promise, not as a description
    /// of it.
    typealias StatusReader = (URL, TimeInterval, String?) async throws -> StatusAnswer
    /// A notice the dashboard is allowed to send.
    struct Notice: Equatable {
        let title: String
        let body: String
    }

    /// The last reading that arrived, kept after monitoring ends so a frozen
    /// dashboard can be read.
    @Published private(set) var snapshot: NotchSplashSnapshot?
    /// Whether the polling is running, which is the Live Activity card's rule.
    @Published private(set) var isMonitoring = false
    /// The task being timed: idle, running, or finished and frozen.
    @Published private(set) var phase: NotchSplashTaskTracker.Phase = .idle
    /// The task's tokens: the engine's cumulative counters read against where
    /// they stood when the task began, frozen at its end. The card header's two
    /// arrows, and nothing else - the thirty days of tokens are the trend's,
    /// kept in the app's own file, and a task beginning leaves them where they
    /// are.
    @Published private(set) var taskTokens = NotchSplashTaskTracker.TaskTokens.zero
    /// Why the last reading did not arrive, while the polling is running.
    @Published private(set) var failure: NotchSplashFailure?
    /// The interval the polling runs at, in whole seconds.
    @Published private(set) var intervalSeconds: Int
    /// The measured past: the readings the four charts draw, and the daily
    /// tokens the trend draws. Kept locally for thirty days, and published as
    /// it grows, so the cards draw what has been measured and not a shape
    /// invented for the moment.
    @Published private(set) var history = NotchSplashHistory.empty

    /// The engine's own figures for the reading last answered: the batches in
    /// hand and the first token's percentiles.
    ///
    /// Nothing here is measured by the app. Each figure is one the endpoint
    /// answered, and a session clears them when the reading it came from stops
    /// being current, so a card never draws a figure from the past as the
    /// machine's present.
    @Published private(set) var live = NotchSplashLiveMetrics.empty

    /// A reading of the server's spilling and reservation pressure, which
    /// only the tracker can tell from two readings in a row.
    private(set) var isSpilling = false
    private(set) var reservationFailures: Int?

    private var tracker = NotchSplashTaskTracker()
    private var announcements = NotchSplashAnnouncements()
    /// The engine the figures last shown belong to, so an engine begun again
    /// starts from no measurements at all.
    private var liveInstanceKey: String?
    private var loop: Task<Void, Never>?
    private var generation = UUID()
    /// What became of the last task timed, so the polling loop can be asked
    /// whether a finished task is a reason to stop (it is not).
    private var lastOutcome: NotchSplashTaskTracker.Outcome?
    /// The moment a request was last seen running, and the moment the reading
    /// began: the two ways the loop measures how long Splash has been idle.
    private var lastActiveAt: Date?
    private var monitoringSince = Date()

    /// How many statuses the polling has asked for. The page does not read
    /// this; a person watching the polling can, and a test must.
    private(set) var reads = 0

    // The outside world, as functions: what answers a status, where the
    // server is, whether the section is on, what the interval and the key are,
    // what time it is, what words to speak, and how a notice is sent. The app
    // hands these over with its own session, settings, clock, and
    // notifications; a test hands them over with a document it made and a
    // clock of its own, and the reading, the task, and the notices run the
    // same way either way.
    private let read: StatusReader
    private let address: () -> URL?
    private let enabled: () -> Bool
    private let savedInterval: () -> Int
    private let savedKey: () -> String
    private let keepInterval: (Int) -> Void
    private let clock: () -> Date
    private let strings: () -> NotchSplashStrings
    private let deliver: (Notice) -> Void
    /// The history on disk: the readings are recorded as they arrive, the file
    /// is written at most twice a minute, and thirty days is kept.
    private let historyStore: NotchSplashHistoryStore
    /// The last time the file was pruned to its thirty days, so a session that
    /// runs for weeks prunes itself and not only at its start.
    private var historyCleaned: Date?

    /// A session with its world handed in, which is how a test runs one.
    init(read: @escaping StatusReader,
         address: @escaping () -> URL?,
         enabled: @escaping () -> Bool = { true },
         savedInterval: @escaping () -> Int,
         savedKey: @escaping () -> String = { "" },
         keepInterval: @escaping (Int) -> Void = { _ in },
         clock: @escaping () -> Date = Date.init,
         strings: @escaping () -> NotchSplashStrings = { FeatureStrings.notchSplash(.enUS) },
         deliver: @escaping (Notice) -> Void = { _ in },
         history: NotchSplashHistoryStore = NotchSplashHistoryStore()) {
        self.read = read
        self.address = address
        self.enabled = enabled
        self.savedInterval = savedInterval
        self.savedKey = savedKey
        self.keepInterval = keepInterval
        self.clock = clock
        self.strings = strings
        self.deliver = deliver
        historyStore = history
        intervalSeconds = savedInterval()
    }

    // MARK: What the page and the card ask for

    /// The clock's value now, by the clock the session is given.
    func elapsed() -> TimeInterval { tracker.elapsed(at: clock()) }
    /// The clock's value at a moment given.
    func elapsed(at date: Date) -> TimeInterval { tracker.elapsed(at: date) }
    var isTaskRunning: Bool { tracker.isRunning }
    var isTaskFinished: Bool { tracker.isFinished }
    var trackedID: String? { tracker.trackedID }
    /// The decode speed the island's strip shows: the batch in hand, and the
    /// engine's own average over its whole running while no batch is in hand.
    var stripDecodeSpeed: Double? {
        NotchSplashLiveMetrics.stripDecodeSpeed(current: live.decode,
                                                overall: snapshot?.status.metrics.decodeTokensPerSecond)
    }
    /// Whether the island's strip has a decode speed to show: a reading is in
    /// hand, and it is not so old that its numbers are about the past.
    var stripShowsDecodeSpeed: Bool {
        guard let snapshot, failure == nil, isMonitoring else { return false }
        return !isStale(snapshot) && stripDecodeSpeed != nil
    }
    var taskOutcome: NotchSplashTaskTracker.Outcome? {
        if case .finished(_, let outcome, _, _) = phase { return outcome }
        return nil
    }

    /// How long the server has had nothing running, as the polling loop is
    /// asked about it: the idle stretch between two prompts is the dashboard's
    /// normal state, and the number that grows across it is never a reason to
    /// stop reading.
    private var idleSeconds: TimeInterval {
        max(0, clock().timeIntervalSince(lastActiveAt ?? monitoringSince))
    }

    /// Whether the page has a dashboard to show: a session running, a task
    /// frozen at the end of one, or a reading that came back from a stop.
    var showsDashboard: Bool {
        isMonitoring || isTaskRunning || isTaskFinished || snapshot != nil
    }

    /// The address being read, for the page to name.
    var endpointDescription: String {
        guard let url = address() else { return NotchSplashSupport.placeholder }
        return "\(url.host ?? ""):\(url.port ?? 0)"
    }

    // MARK: The two switches

    /// Begin monitoring at the chosen interval. Nothing is asked of Splash
    /// beyond the status, so no generation starts.
    func start() {
        guard enabled(), !isMonitoring else { return }
        guard address() != nil else {
            failure = .notConfigured
            return
        }
        generation = UUID()
        tracker.begin()
        tracker.clearFinished()
        // A session begins with no measurements. The figures beside the chart
        // are the engine's, and the first reading of this session is the first
        // one this session can show.
        live = .empty
        liveInstanceKey = nil
        phase = tracker.phase
        taskTokens = tracker.taskTokens
        lastOutcome = nil
        monitoringSince = clock()
        lastActiveAt = nil
        failure = nil
        isMonitoring = true
        // What was measured before is read once, here, and pruned to its
        // thirty days; from the first reading on, the file only grows.
        openHistory(at: clock())
        startLoop()
    }

    /// Stop monitoring. The page returns to its Start state; a generation
    /// already running in Splash is left alone, because stopping the reading
    /// is not stopping the work. This is the only way a task's own ending
    /// never ends the reading: the way out is a hand on the way out.
    func stop() {
        guard isMonitoring || loop != nil else { return }
        isMonitoring = false
        generation = UUID()
        loop?.cancel()
        loop = nil
        tracker.clearFinished()
        phase = tracker.phase
        taskTokens = tracker.taskTokens
        lastOutcome = nil
        lastActiveAt = nil
        failure = nil
        // Whatever has been measured is written down on the way out.
        historyStore.flush(at: clock())
    }

    /// A finished task cleared, so the page is empty again.
    func clearFinishedTask() {
        tracker.clearFinished()
        phase = tracker.phase
        taskTokens = tracker.taskTokens
    }

    /// The chosen interval, applied to the running session at once.
    func setInterval(_ seconds: Int) {
        let chosen = NotchSplashSupport.interval(seconds)
        guard chosen != intervalSeconds else { return }
        intervalSeconds = chosen
        keepInterval(chosen)
        if isMonitoring, let loop {
            // The running nap is cut short, so the new interval is the
            // interval the session keeps from here.
            loop.cancel()
            self.loop = nil
            startLoop()
        }
    }

    // MARK: Lifecycle

    func syncWithPreferences() {
        intervalSeconds = savedInterval()
        let ends = NotchSplashMonitoringPolicy.endsMonitoring(
            NotchSplashMonitoringPolicy.Condition(sectionDisabled: !enabled(),
                                                  noAddress: address() == nil,
                                                  idleSeconds: idleSeconds,
                                                  outcome: lastOutcome))
        if isMonitoring, ends { stop() }
        // The address, the port, or the key moved under a running session:
        // read the new one, and let the tracker's instance rule decide what
        // the old request was. Nothing else about the settings ends a session
        // that a person started.
    }

    // MARK: The measured past

    /// Reads the file, keeps what is inside its thirty days, and lets the
    /// counters begin from the reading that is about to arrive, so the tokens
    /// of the time the app was away are not written as a day's work.
    private func openHistory(at date: Date) {
        historyStore.load(now: date)
        historyStore.clean(now: date)
        history = historyStore.history
        historyCleaned = date
    }

    /// Records one reading, and prunes the file again when a session has run
    /// long enough that a month of readings has to be thinned on its way in.
    private func recordHistory(snapshot: NotchSplashSnapshot, at date: Date) {
        historyStore.record(status: snapshot.status, instanceKey: snapshot.instanceKey, at: date)
        history = historyStore.history
        if let cleaned = historyCleaned,
           date.timeIntervalSince(cleaned) >= NotchSplashSupport.historyCleanupInterval {
            historyStore.clean(now: date)
            history = historyStore.history
            historyCleaned = date
        }
    }

    /// The engine's figures for one reading.
    ///
    /// Nothing is measured here: each figure is one the endpoint answered for
    /// the batch it has in hand, or the percentile of the requests it has
    /// finished. A batch the server marks not valid, and a field the server
    /// does not carry, answer nil, which is an empty line and an empty figure.
    ///
    /// An engine that is not the one the figures last shown came from -
    /// a restart, an address that moved - starts from no measurements, because
    /// the batches of one engine say nothing about another.
    private func recordLive(snapshot: NotchSplashSnapshot, at date: Date) {
        if liveInstanceKey != snapshot.instanceKey {
            liveInstanceKey = snapshot.instanceKey
            live = .empty
        }
        live = NotchSplashLiveMetrics.current(snapshot.status.metrics)
    }

    // MARK: The loop

    private func startLoop() {
        let generation = self.generation
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self, self.isMonitoring, self.generation == generation {
                await self.readOnce(generation: generation)
                if Task.isCancelled || !self.isMonitoring || self.generation != generation { return }
                // The two facts a polling loop is tempted to treat as its end:
                // how long the server has had nothing running, and what became
                // of the last task. The rule answers them the way the promise
                // says - keep reading - and only a hand, a section switched
                // off, or an address gone stops it.
                if NotchSplashMonitoringPolicy.endsMonitoring(
                    NotchSplashMonitoringPolicy.Condition(idleSeconds: idleSeconds, outcome: lastOutcome)) {
                    stop()
                    return
                }
                let seconds = max(0.2, TimeInterval(self.intervalSeconds))
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    /// One status, read and applied.
    private func readOnce(generation: UUID) async {
        guard let url = address() else {
            failure = .notConfigured
            stop()
            return
        }
        let timeout = min(10, max(2, TimeInterval(intervalSeconds) * 2))
        let started = clock()
        do {
            let answer = try await read(url, timeout, savedKey())
            // A read that belonged to a session that has since been stopped
            // or restarted has nothing to say about this one.
            guard generation == self.generation, !Task.isCancelled else { return }
            reads += 1
            guard answer.code == 200 else {
                report(.status(answer.code), at: started)
                return
            }
            guard let document = SplashJSON.document(answer.data) else {
                report(.unreadable, at: started)
                return
            }
            let status = NotchSplashStatus(document: document)
            guard status.isReadable else {
                report(.unreadable, at: started)
                return
            }
            apply(NotchSplashSnapshot(status: status, fetchedAt: clock()), at: clock())
        } catch {
            guard generation == self.generation else { return }
            // A cancelled read is the session ending by hand, which is not a
            // failure to report.
            if (error as? URLError)?.code == .cancelled, !isMonitoring { failure = nil; return }
            report(.unreachable, at: started)
        }
    }

    private func report(_ failure: NotchSplashFailure, at date: Date) {
        self.failure = failure
        // A reading that did not arrive: the last one stays on the card, and
        // once it is older than the polling should have moved, it stops
        // counting as evidence, so a server that comes back late cannot be
        // read as finishing a request it never saw. Its figures of the batch
        // in hand go with it: a batch measured a minute ago is not the batch in
        // hand, and a card that has no current figure leaves that line empty.
        if let snapshot, isStale(snapshot) {
            self.failure = .stale
            live = .empty
            liveInstanceKey = nil
        }
    }

    private func isStale(_ snapshot: NotchSplashSnapshot) -> Bool {
        clock().timeIntervalSince(snapshot.fetchedAt)
            > TimeInterval(intervalSeconds) * Double(NotchSplashSupport.staleIntervalFactor)
    }

    /// A reading applied to the task, the dashboard, and the notices.
    private func apply(_ snapshot: NotchSplashSnapshot, at date: Date) {
        self.snapshot = snapshot
        failure = nil
        // The reading is history from this moment on: the four charts draw
        // what has been recorded, and the day's tokens are the difference this
        // reading's counters make against the last.
        recordHistory(snapshot: snapshot, at: date)
        recordLive(snapshot: snapshot, at: date)
        if snapshot.status.hasWork { lastActiveAt = date }
        // A reading that is already old when it arrives says what the engine
        // was doing, not what it is doing: it is kept for the charts and the
        // card, and the task's quiet window is not measured from it, so a pause
        // in the polling, an answer that arrived late, and a machine that was
        // asleep are never counted as minutes of an engine doing nothing.
        let event = isStale(snapshot) ? nil : tracker.observe(snapshot, at: date)
        phase = tracker.phase
        taskTokens = tracker.taskTokens
        isSpilling = tracker.isSpilling
        reservationFailures = snapshot.status.kv.reservationFailures
        guard let event else { return }
        switch event {
        case .started:
            break
        case .finished(let id, let outcome, let at, let elapsed):
            finishTask(id: id, outcome: outcome, at: at, elapsed: elapsed)
        }
    }

    /// What the end of a task does: tell it once, freeze its clock, and keep
    /// reading.
    ///
    /// A finished task is the dashboard's news, not its end. The clock stops
    /// at the task's length, the readings it ended with stay on the card, and
    /// the polling goes on, so the idle stretch after a prompt is a dashboard
    /// still alive and the next prompt is timed as its own task with its own
    /// news. Only the way out on the card stops the reading.
    private func finishTask(id: String, outcome: NotchSplashTaskTracker.Outcome,
                            at date: Date, elapsed: TimeInterval) {
        lastOutcome = outcome
        let words = strings()
        let key = NotchSplashTaskTracker.announceKey(id: id, at: date, elapsed: elapsed)
        // The notice carries the task's own length, the number the card's clock
        // froze at - not the time the notice happens to be sent.
        let spoken = NotchSplashSupport.taskClock(max(0, elapsed))
        if announcements.take(id: key, outcome: outcome) {
            // The counters completed, and the endpoint said so. What the app
            // says is what it knows: the activity ended, outlasted by a quiet
            // of the whole window, and how long it lasted. It does not claim
            // a task was completed, which the endpoint never reported.
            deliver(Notice(title: words.notifyActivityEndedTitle,
                           body: words.notifyActivityEndedBody(spoken)))
        } else if announcements.takeUnsuccessful(id: key, outcome: outcome) {
            deliver(Notice(title: outcome == .failed ? words.notifyFailedTitle : words.notifyCancelledTitle,
                           body: outcome == .failed ? words.notifyFailedBody : words.notifyCancelledBody))
        }
        switch outcome {
        case .completed:
            // The task's clock stays frozen at its length and its readings
            // stay on the card, held until the next request the server reports
            // replaces them. The reading itself is not touched.
            break
        case .failed, .cancelled, .lost:
            // A task that ended without completing is cleared, so the card
            // reads as idle and the next request the server reports is timed
            // as the next task. The reading goes on either way.
            tracker.clearFinished()
            phase = tracker.phase
        }
    }
}
