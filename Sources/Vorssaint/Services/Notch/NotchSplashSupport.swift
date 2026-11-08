// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

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
    static let headerHeight: CGFloat = 18
    static let headerSpacing: CGFloat = 8
    /// The gap between the four readings: one gap, four columns, one row.
    static let metricSpacing: CGFloat = 8
    /// A reading is a label, a figure and a line under it, so it is taller
    /// than a row of text.
    static let metricCardHeight: CGFloat = 76
    static let labelSize: CGFloat = 8.5
    static let valueSize: CGFloat = 22
    static let footerSize: CGFloat = 9.5
    static let headerSize: CGFloat = 12
    static let readingSize: CGFloat = 11
    /// The hairline under the header.
    static let ruleHeight: CGFloat = 1
    /// The card as the page and the section measure it.
    static var cardHeight: CGFloat {
        padding * 2 + headerHeight + headerSpacing + ruleHeight + headerSpacing + metricCardHeight
    }

    /// The page: the ruler's row, the card under it, and the gap between.
    static var pageHeight: CGFloat {
        NotchLayout.timerRulerHeight + NotchLayout.rowSpacing + cardHeight
    }

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
        let decodeTokensPerSecond: Double?
        let prefillTokensPerSecond: Double?
        /// Time to first token, in milliseconds, at the p50 the server names.
        let ttftMilliseconds: Double?
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

    let instance: Instance
    let activeRequestIDs: [String]
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
            ttftMilliseconds: ttft.readDouble(["p50", "median", "p50_ms", "value"])
                ?? stats.readDouble(["ttft_ms", "ttft_ms_p50", "ttft"]),
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
    /// The port offered when nothing has been typed yet.
    static let defaultPort = 8000

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
    static let defaultInterval = 2
    static let intervalRange = 1...10
    /// A reading older than this many intervals is stale: the server stopped
    /// answering, and its last words are not evidence about the present.
    static let staleIntervalFactor = 3

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

    static func endpoint(in defaults: UserDefaults = .standard) -> URL? {
        let stored = defaults.integer(forKey: DefaultsKey.notchSplashPort)
        return NotchSplashEndpoint.statusURL(host: defaults.string(forKey: DefaultsKey.notchSplashHost) ?? "",
                                             port: stored != 0 ? stored : NotchSplashEndpoint.defaultPort)
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
        if (reservationFailures ?? 0) > 0 || spilling { return .red }
        if let pagesFree, pagesFree < 0 { return .amber }
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

    /// Time to first token, in seconds with its unit.
    static func ttftText(_ seconds: Double?, locale: Locale = locale) -> String {
        guard let seconds, seconds.isFinite else { return placeholder }
        let format = seconds >= 10 ? "%.0f" : "%.1f"
        return String(format: format, locale: locale, seconds) + " s"
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

    /// A figure with no tone of its own rests in the reference's beige.
    static let resting = beige

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
/// started; a task is one request Splash is running. The clock belongs to the
/// task: it begins when a request is seen, freezes at its own length when the
/// request finishes, and starts again at zero for the next one. A monitoring
/// session begun over an idle server therefore shows a clock that has not
/// begun, and a server that restarted does not "finish" the request it lost.
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

    /// The counters as they stood when a request was first seen.
    private struct Baseline: Equatable {
        let completed: Int
        let failed: Int
        let cancelled: Int
        let instanceKey: String
    }

    private(set) var phase: Phase = .idle
    private var baseline: Baseline?
    /// Readings in a row that have not named the tracked request. One is a
    /// response caught mid-flight; two say the request is gone.
    private var missingReadings = 0
    /// The spill counter last seen, so a counter that grew is a spill now.
    private var lastSpillCount: Int?

    /// Spilling, sustained: the counter grew between two readings.
    private(set) var isSpilling = false

    /// A monitoring session beginning: the clock starts over, and so does the
    /// reading of the counters.
    mutating func begin() {
        phase = .idle
        baseline = nil
        missingReadings = 0
        lastSpillCount = nil
        isSpilling = false
    }

    /// A finished task cleared, so a page returns to its Start state.
    mutating func clearFinished() {
        guard case .finished = phase else { return }
        phase = .idle
        baseline = nil
        missingReadings = 0
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
    func elapsed(at date: Date) -> TimeInterval {
        switch phase {
        case .idle: return 0
        case .running(_, let startedAt): return max(0, date.timeIntervalSince(startedAt))
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

    /// One reading, taken at `date`.
    ///
    /// A request that leaves the active list is only called finished by what
    /// the counters moved with it: a completed count that grew is a
    /// completion, a failed or cancelled count that grew is that, and a
    /// request that vanishes with every counter where it was is a request
    /// this reading cannot speak for — a restart, a snapshot that arrived
    /// late, a server that forgot it. That is reported as lost, and it is
    /// never announced as a completion.
    mutating func observe(_ snapshot: NotchSplashSnapshot, at date: Date) -> Event? {
        let status = snapshot.status
        isSpilling = spillsGrew(status.kv.spillCount)
        switch phase {
        case .idle:
            guard let id = status.activeRequestIDs.first else { return nil }
            phase = .running(id: id, startedAt: date)
            baseline = Baseline(completed: status.requests.completed ?? 0,
                                failed: status.requests.failed ?? 0,
                                cancelled: status.requests.cancelled ?? 0,
                                instanceKey: snapshot.instanceKey)
            missingReadings = 0
            return .started(id: id, at: date)

        case .finished:
            // A finished task holds its frozen clock until the page clears
            // it, which is what a completion asks for. A task that ended
            // without completing is cleared by the service, so the next
            // request the server reports is timed as the next task.
            return nil

        case .running(let id, let startedAt):
            guard !status.activeRequestIDs.contains(id) else {
                missingReadings = 0
                return nil
            }
            missingReadings += 1
            let counters = status.requests
            // The server itself changed under the request: the request is
            // gone and nothing about it is known.
            if let baseline, baseline.instanceKey != snapshot.instanceKey {
                return finish(id: id, outcome: .lost, at: date, startedAt: startedAt)
            }
            // No counters at all: the request is gone and nothing confirms
            // what it did.
            if counters.reportsNothing {
                return finish(id: id, outcome: .lost, at: date, startedAt: startedAt)
            }
            let previous = baseline ?? Baseline(completed: counters.completed ?? 0,
                                                failed: counters.failed ?? 0,
                                                cancelled: counters.cancelled ?? 0,
                                                instanceKey: snapshot.instanceKey)
            let completedGrew = (counters.completed ?? previous.completed) > previous.completed
            let failedGrew = (counters.failed ?? previous.failed) > previous.failed
            let cancelledGrew = (counters.cancelled ?? previous.cancelled) > previous.cancelled
            if completedGrew { return finish(id: id, outcome: .completed, at: date, startedAt: startedAt) }
            if failedGrew { return finish(id: id, outcome: .failed, at: date, startedAt: startedAt) }
            if cancelledGrew { return finish(id: id, outcome: .cancelled, at: date, startedAt: startedAt) }
            // Nothing moved and the request is out of the list in two
            // readings in a row: the server dropped it without a counter to
            // say why, which is as near to "unknown" as the endpoint allows.
            guard missingReadings >= 2 else { return nil }
            return finish(id: id, outcome: .lost, at: date, startedAt: startedAt)
        }
    }

    private mutating func finish(id: String, outcome: Outcome, at date: Date, startedAt: Date) -> Event {
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        phase = .finished(id: id, outcome: outcome, at: date, elapsed: elapsed)
        baseline = nil
        missingReadings = 0
        return .finished(id: id, outcome: outcome, at: date, elapsed: elapsed)
    }

    private mutating func spillsGrew(_ count: Int?) -> Bool {
        defer { if let count { lastSpillCount = count } }
        guard let count, let last = lastSpillCount else { return false }
        return count > last
    }
}

/// Which finished tasks are announced, and once.
///
/// A completion is announced the first time it is confirmed and never again,
/// by the request's own id. A page reopened, a poll repeated, and a status
/// read twice are all reasons the same news could arrive twice.
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
