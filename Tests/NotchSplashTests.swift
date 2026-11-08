// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Splash dashboard's own rules: the address it reads, the numbers it
/// reads out of a status, the colours its thresholds choose, the task it
/// times, and the notices it is allowed to send once.
enum NotchSplashTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func status(_ json: String) -> NotchSplashStatus {
        SplashJSON.document(Data(json.utf8)).map(NotchSplashStatus.init(document:))
            ?? NotchSplashStatus(document: .null)
    }

    private static func snapshot(_ json: String, at date: Date = start) -> NotchSplashSnapshot {
        NotchSplashSnapshot(status: status(json), fetchedAt: date)
    }

    /// A status of the reference's own numbers, all of them named the way the
    /// endpoint names them.
    private static let full = """
    {
      "instance": {"id": "splash-1", "started_at": "2026-11-08T10:00:00Z"},
      "active_requests": [{"id": "req-1", "model": "splash"}, {"id": "req-2"}],
      "requests": {"completed": 57, "failed": 0, "cancelled": 1},
      "metrics": {
        "decode_tokens_per_second": 85.65, "prefill_tokens_per_second": 622.18,
        "ttft_ms": {"p50": 1700}, "prefill_input_tokens": 134000, "decode_output_tokens": 5000
      },
      "cache": {"hit_rate": 0.9623, "hits": 55, "requests": 57},
      "kv": {"active_bytes": 1610612736, "pages_free": 40, "pages_total": 1000,
             "spilled_bytes": 0, "spill_count": 0, "reservation_failures": 0},
      "memory_actual": {"current_bytes": 97699258368},
      "memory_governor": {"limit_bytes": 112909213696, "charged_bytes": 90194313216}
    }
    """

    // MARK: - The settings

    static func settingsChecks(_ suite: TestSuite) {
        suite.expect(NotchSplashSupport.defaultInterval == 2 && NotchSplashSupport.intervalRange == 1...10,
                     "the interval defaults to 2 seconds between 1 and 10")
        for value in 1...10 {
            suite.expect(NotchSplashSupport.interval(value) == value, "every second from 1 to 10 is chosen as itself")
        }
        suite.expect(NotchSplashSupport.interval(nil) == 2 && NotchSplashSupport.interval(0) == 2
                         && NotchSplashSupport.interval(11) == 2 && NotchSplashSupport.interval(-3) == 2,
                     "a value out of range, or none at all, is the default")
        suite.expect(NotchSplashEndpoint.host("http://127.0.0.1:8000/status") == "127.0.0.1"
                         && NotchSplashEndpoint.host("  localhost ") == "localhost"
                         && NotchSplashEndpoint.host("https://splash.local/v1/") == "splash.local"
                         && NotchSplashEndpoint.host("[::1]:9000") == "[::1]"
                         && NotchSplashEndpoint.host("host:5000") == "host",
                     "a scheme, a path, a port and the spaces are taken off what a person typed")
        suite.expect(NotchSplashEndpoint.port("8000") == 8000
                         && NotchSplashEndpoint.port(" 80 ") == 80
                         && NotchSplashEndpoint.port("0") == nil && NotchSplashEndpoint.port("70000") == nil
                         && NotchSplashEndpoint.port("eighty") == nil && NotchSplashEndpoint.port("") == nil,
                     "a port is a whole number the system allows, and nothing else")
        let url = NotchSplashEndpoint.statusURL(host: "127.0.0.1", port: 8000)
        suite.expect(url?.absoluteString == "http://127.0.0.1:8000/status",
                     "the reading is the configured server's status")
        suite.expect(NotchSplashEndpoint.statusURL(host: "", port: 8000) == nil
                         && NotchSplashEndpoint.statusURL(host: "bad host", port: 8000) == nil
                         && NotchSplashEndpoint.statusURL(host: "ok", port: 0) == nil
                         && NotchSplashEndpoint.statusURL(host: "ok", port: 70_000) == nil,
                     "no address, a name with a space, and a port out of range are not a server")
        suite.expect(NotchSplashEndpoint.authorization(" sk-1 ") == "Bearer sk-1"
                         && NotchSplashEndpoint.authorization("") == nil
                         && NotchSplashEndpoint.authorization("   ") == nil,
                     "a key is sent as a bearer token, and an empty key sends nothing")
        suite.expect(NotchSplashEndpoint.isConfigured(host: "localhost", port: 8000)
                         && !NotchSplashEndpoint.isConfigured(host: "", port: 8000),
                     "the dashboard knows when it has a server to read")
    }

    // MARK: - The reading

    static func readingChecks(_ suite: TestSuite) {
        let read = status(full)
        suite.expect(read.instance.id == "splash-1", "the instance names itself")
        suite.expect(read.instance.startedAt == NotchSplashStatus.date(.string("2026-11-08T10:00:00Z")),
                     "the instance's start is read as the server writes it")
        suite.expect(read.activeRequestIDs == ["req-1", "req-2"],
                     "the running requests keep the ids the server gave them")
        suite.expect(read.requests.completed == 57 && read.requests.failed == 0
                         && read.requests.cancelled == 1,
                     "the request counters are read as three counts")
        suite.expect(read.metrics.decodeTokensPerSecond == 85.65
                         && read.metrics.prefillTokensPerSecond == 622.18,
                     "the two throughputs are read at the server's names")
        suite.expect(read.metrics.ttftMilliseconds == 1700, "the p50 of the time to first token is read")
        suite.expect(read.metrics.prefillInputTokens == 134_000 && read.metrics.decodeOutputTokens == 5_000,
                     "the cumulative tokens are read")
        suite.expect(read.cache.hits == 55 && read.cache.requests == 57,
                     "the cache's counters are read")
        suite.expect(read.kv.activeBytes == 1_610_612_736 && read.kv.pagesFree == 40
                         && read.kv.pagesTotal == 1_000 && read.kv.spillCount == 0
                         && read.kv.reservationFailures == 0,
                     "the cache's bytes, pages, spills and reservations are read")
        suite.expect(read.memoryActual.currentBytes == 97_699_258_368,
                     "the memory in use is read, not the governor's charge")
        suite.expect(read.governor.limitBytes == 112_909_213_696 && read.governor.chargedBytes == 90_194_313_216,
                     "the governor's limit and charge are read")
        suite.expect(read.isReadable, "a status with fields in it is a reading")

        // A server that spells its fields another way, or reports less.
        let other = status("""
        {"instance_id": "s2", "requests": {"completed_total": 3},
         "metrics": {"decode_tps": 12.5, "ttft_ms": 900, "input_tokens": 40},
         "cache": {"hits": 4, "misses": 1}, "kv": {"bytes": 1024, "pages": {"free": 1, "total": 20}},
         "memory": {"bytes": 4096}, "governor": {"limit": 8192, "charged": 6000}}
        """)
        suite.expect(other.instance.id == "s2", "an instance named at the top is still the instance")
        suite.expect(other.requests.completed == 3 && other.requests.failed == nil
                         && other.requests.cancelled == nil,
                     "a counter the server does not report stays unread, not zero")
        suite.expect(other.metrics.decodeTokensPerSecond == 12.5
                         && other.metrics.ttftMilliseconds == 900
                         && other.metrics.prefillInputTokens == 40,
                     "a throughput and a time spelled shortly are still read")
        suite.expect(other.cache.requests == 5 && other.cache.hits == 4,
                     "hits and misses together are the requests the rate is out of")
        suite.expect(other.kv.pagesFree == 1 && other.kv.pagesTotal == 20 && other.kv.activeBytes == 1024,
                     "pages in their own group are read")
        suite.expect(other.memoryActual.currentBytes == 4096 && other.governor.limitBytes == 8192
                         && other.governor.chargedBytes == 6000,
                     "memory and governor in their short spellings are read")

        let empty = status("{}")
        suite.expect(!empty.isReadable, "an empty document is not a reading")
        suite.expect(empty.activeRequestIDs.isEmpty && empty.requests.reportsNothing
                         && empty.metrics.decodeTokensPerSecond == nil
                         && empty.cache.hits == nil && empty.kv.activeBytes == nil
                         && empty.memoryActual.currentBytes == nil && empty.governor.limitBytes == nil,
                     "a status with nothing in it reads as nothing, and never as zero")
        suite.expect(SplashJSON.document(Data("<html>nope</html>".utf8)) == nil
                         && SplashJSON.document(Data()) == nil
                         && SplashJSON.document(Data("[1,2]".utf8)) == nil,
                     "an HTML page, an empty body and a bare array are not status documents")

        // Requests with no ids of their own keep a standing name of their place,
        // which is what a server that reports no ids allows.
        let unnamed = status(#"{"active_requests": [{"model": "m"}, "abc", 7]}"#)
        suite.expect(unnamed.activeRequestIDs == ["position.0", "abc", "7"],
                     "requests with no id are named by their place, and bare ones by themselves")

        let date = NotchSplashStatus.date
        suite.expect(date(.number(1_800_000_000)) == start, "epoch seconds are read")
        suite.expect(date(.number(1_800_000_000_500)) == start.addingTimeInterval(0.5),
                     "epoch milliseconds are read as milliseconds")
        suite.expect(date(.string("2026-11-08T10:00:00Z")) != nil
                         && date(.string("2026-11-08T10:00:00.250Z")) != nil
                         && date(.string("nonsense")) == nil && date(.null) == nil && date(nil) == nil,
                     "a timestamp is read as ISO 8601, and nonsense is no date")
    }

    // MARK: - Numbers and colours

    static func metricChecks(_ suite: TestSuite) {
        suite.expectClose(NotchSplashSupport.cacheHitPercent(hits: 55, requests: 57) ?? 0, 96.4912280, "55 of 57",
                          tol: 0.0001)
        suite.expect(NotchSplashSupport.cacheHitPercent(hits: 0, requests: 0) == nil
                         && NotchSplashSupport.cacheHitPercent(hits: 3, requests: nil) == nil
                         && NotchSplashSupport.cacheHitPercent(hits: nil, requests: nil) == nil,
                     "no counters is no rate, and never a made-up one")
        suite.expect(NotchSplashSupport.cacheHitPercent(hits: nil, requests: nil, reportedRate: 0.9623) == 96.23,
                     "a server's own rate under 1 is read as a fraction")
        suite.expect(NotchSplashSupport.cacheHitPercent(hits: nil, requests: nil, reportedRate: 96.23) == 96.23,
                     "a server's own rate above 1 is read as a percent")
        suite.expect(NotchSplashSupport.cacheHitPercent(hits: 100, requests: 57) == 100,
                     "counters that cannot be true are capped at a whole rate")

        // Decode: green at 70 and over, red below.
        suite.expect(NotchSplashSupport.decodeTone(69.99) == .red && NotchSplashSupport.decodeTone(70) == .green
                         && NotchSplashSupport.decodeTone(400) == .green,
                     "decode speed is red under 70 and green from 70")
        // Prefill: green above 600, red at 600 and under.
        suite.expect(NotchSplashSupport.prefillTone(600) == .red && NotchSplashSupport.prefillTone(600.01) == .green
                         && NotchSplashSupport.prefillTone(0) == .red,
                     "prefill is red at 600 and green above it")
        // TTFT: green under a second, red at a second.
        suite.expect(NotchSplashSupport.ttftTone(0.999) == .green && NotchSplashSupport.ttftTone(1) == .red
                         && NotchSplashSupport.ttftTone(1.7) == .red,
                     "time to first token is green under a second and red at it")
        suite.expect(NotchSplashSupport.ttftSeconds(milliseconds: 1700) == 1.7
                         && NotchSplashSupport.ttftSeconds(milliseconds: nil) == nil
                         && NotchSplashSupport.ttftSeconds(milliseconds: -1) == nil,
                     "milliseconds become seconds, and a missing time stays missing")
        // Cache: green above 98, amber 95 through 98, red below.
        suite.expect(NotchSplashSupport.cacheTone(98.01) == .green && NotchSplashSupport.cacheTone(98) == .amber
                         && NotchSplashSupport.cacheTone(96.23) == .amber
                         && NotchSplashSupport.cacheTone(95) == .amber && NotchSplashSupport.cacheTone(94.99) == .red,
                     "the cache is green above 98, amber from 95 to 98 inclusive, red below 95")
        suite.expect(NotchSplashSupport.decodeTone(nil) == .neutral
                         && NotchSplashSupport.prefillTone(nil) == .neutral
                         && NotchSplashSupport.ttftTone(nil) == .neutral
                         && NotchSplashSupport.cacheTone(nil) == .neutral,
                     "a reading that is not there is not coloured, in either direction")
        suite.expect(NotchSplashSupport.decodeTone(.nan) == .neutral && NotchSplashSupport.decodeTone(.infinity) == .neutral,
                     "a number that is not a number is not coloured")

        // Governor: charged over limit, as a percent.
        suite.expectClose(NotchSplashSupport.governorUtilization(chargedBytes: 90_194_313_216,
                                                                 limitBytes: 112_909_213_696) ?? 0,
                          79.88216, "charged over limit", tol: 0.0001)
        suite.expect(NotchSplashSupport.governorUtilization(chargedBytes: nil, limitBytes: 10) == nil
                         && NotchSplashSupport.governorUtilization(chargedBytes: 10, limitBytes: 0) == nil
                         && NotchSplashSupport.governorUtilization(chargedBytes: -1, limitBytes: 10) == nil,
                     "no charge, no limit, and a negative charge are no utilization")
        suite.expect(NotchSplashSupport.governorUtilizationTone(79.99) == .green
                         && NotchSplashSupport.governorUtilizationTone(80) == .amber
                         && NotchSplashSupport.governorUtilizationTone(89.99) == .amber
                         && NotchSplashSupport.governorUtilizationTone(90) == .red,
                     "the charge is green under 80, amber to under 90, red from 90")
        suite.expect(NotchSplashSupport.governorHeadroom(chargedBytes: 50, limitBytes: 100) ?? 0 == 50, "headroom")
        suite.expect(NotchSplashSupport.memoryPressureTone(headroomPercent: 21) == .green
                         && NotchSplashSupport.memoryPressureTone(headroomPercent: 20) == .amber
                         && NotchSplashSupport.memoryPressureTone(headroomPercent: 10) == .amber
                         && NotchSplashSupport.memoryPressureTone(headroomPercent: 9.99) == .red,
                     "headroom is green above 20, amber from 10 to 20, red below 10")

        // The cache is not red for being full: only for pages running out,
        // spilling, and reservations that failed.
        suite.expect(NotchSplashSupport.kvTone(pagesFree: 500, pagesTotal: 500, spilling: false,
                                               reservationFailures: 0) == .purple,
                     "a cache full of its own work is purple, not a warning")
        suite.expect(NotchSplashSupport.kvTone(pagesFree: nil, pagesTotal: nil, spilling: false,
                                               reservationFailures: nil) == .purple,
                     "a cache that reports no pages is read as calm")
        suite.expect(NotchSplashSupport.kvTone(pagesFree: 9, pagesTotal: 100, spilling: false,
                                               reservationFailures: 0) == .amber
                         && NotchSplashSupport.kvTone(pagesFree: 1, pagesTotal: 1000, spilling: false,
                                                      reservationFailures: 0) == .amber,
                     "scarce pages are amber")
        suite.expect(NotchSplashSupport.kvTone(pagesFree: 500, pagesTotal: 1000, spilling: true,
                                               reservationFailures: 0) == .red
                         && NotchSplashSupport.kvTone(pagesFree: 500, pagesTotal: 1000, spilling: false,
                                                      reservationFailures: 1) == .red,
                     "spilling and failed reservations are red")
    }

    // MARK: - Words

    static func textChecks(_ suite: TestSuite) {
        let us = Locale(identifier: "en_US")
        let de = Locale(identifier: "de_DE")
        suite.expect(NotchSplashSupport.speedText(85.65, locale: us) == "85.65",
                     "a small throughput keeps two decimals: \(NotchSplashSupport.speedText(85.65, locale: us))")
        suite.expect(NotchSplashSupport.speedText(622.18, locale: us) == "622.2",
                     "a hundredfold throughput keeps one: \(NotchSplashSupport.speedText(622.18, locale: us))")
        suite.expect(NotchSplashSupport.speedText(1234.6, locale: us) == "1,235"
                         && NotchSplashSupport.speedText(1234.6, locale: de) == "1.235",
                     "a thousandfold throughput is a whole number, grouped as the region groups it")
        suite.expect(NotchSplashSupport.speedText(nil) == NotchSplashSupport.placeholder
                         && NotchSplashSupport.speedText(.nan) == NotchSplashSupport.placeholder,
                     "a throughput nobody reported leaves its place empty, and is never written as zero")
        suite.expect(NotchSplashSupport.speedText(85.65, locale: de) == "85,65"
                         && NotchSplashSupport.ttftText(1.7, locale: de) == "1,7 s"
                         && NotchSplashSupport.percentText(96.23, locale: de) == "96,23%"
                         && NotchSplashSupport.tokensText(1_500_000, locale: de) == "1,5M"
                         && NotchSplashSupport.bytesText(112_909_213_696, locale: de)?.value == "105,2",
                     "the figures follow the reader's region, and a decimal is written with a comma there")
        suite.expect(NotchSplashSupport.ttftText(1.7, locale: us) == "1.7 s"
                         && NotchSplashSupport.ttftText(12.4, locale: us) == "12 s"
                         && NotchSplashSupport.ttftText(nil) == NotchSplashSupport.placeholder,
                     "a time is written in seconds with its unit")
        suite.expect(NotchSplashSupport.percentText(96.2345, locale: us) == "96.23%"
                         && NotchSplashSupport.percentText(nil) == NotchSplashSupport.placeholder,
                     "a rate keeps two decimals and its percent sign")
        suite.expect(NotchSplashSupport.tokensText(134_000, locale: us) == "134K"
                         && NotchSplashSupport.tokensText(5_000, locale: us) == "5K"
                         && NotchSplashSupport.tokensText(999) == "999"
                         && NotchSplashSupport.tokensText(1_500_000, locale: us) == "1.5M"
                         && NotchSplashSupport.tokensText(2_000_000_000, locale: us) == "2B"
                         && NotchSplashSupport.tokensText(nil) == NotchSplashSupport.placeholder,
                     "a token count is written short, in the unit it needs, without zeros it does not need")
        suite.expect(NotchSplashSupport.bytesText(112_909_213_696, locale: us)?.unit == "GiB"
                         && NotchSplashSupport.bytesText(112_909_213_696, locale: us)?.value == "105.2"
                         && NotchSplashSupport.bytesText(2_097_152, locale: us)?.unit == "MiB"
                         && NotchSplashSupport.bytesText(2048, locale: us)?.unit == "KiB"
                         && NotchSplashSupport.bytesText(512, locale: us)?.value == "512"
                         && NotchSplashSupport.bytesText(nil) == nil
                         && NotchSplashSupport.bytesText(-5) == nil,
                     "bytes are written in the unit that fits, and negative bytes are no reading")
        suite.expect(NotchSplashSupport.taskClock(0) == "00:00"
                         && NotchSplashSupport.taskClock(-3) == "00:00"
                         && NotchSplashSupport.taskClock(45) == "00:45"
                         && NotchSplashSupport.taskClock(61) == "1m 01s"
                         && NotchSplashSupport.taskClock(1_401) == "23m 21s"
                         && NotchSplashSupport.taskClock(3_723) == "1h 02m 03s",
                     "the task's clock is 00:00 before a task, and m s once there is one")
        suite.expect(NotchSplashSupport.locale == MetricFormat.locale,
                     "the dashboard's figures are written in the region the app's other numbers use")
        suite.expect(NotchSplashSupport.intervalText(2) == "2s", "the interval is written short")
    }

    // MARK: - The task and its clock

    static func taskChecks(_ suite: TestSuite) {
        let idle = #"{"instance": {"id": "a"}, "requests": {"completed": 3}, "active_requests": []}"#
        let busy = #"{"instance": {"id": "a"}, "requests": {"completed": 3}, "active_requests": [{"id": "r1"}]}"#
        let done = #"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": []}"#

        var tracker = NotchSplashTaskTracker()
        suite.expect(tracker.phase == .idle && tracker.elapsed(at: start) == 0,
                     "a session begun over an idle server has no task and no clock")
        suite.expect(tracker.observe(snapshot(idle), at: start) == nil,
                     "an empty active list starts nothing")
        suite.expect(tracker.observe(snapshot(busy), at: start) == .started(id: "r1", at: start),
                     "a request seen is a task begun")
        suite.expect(tracker.elapsed(at: start.addingTimeInterval(7)) == 7,
                     "the clock runs with the request")
        suite.expect(tracker.observe(snapshot(busy), at: start.addingTimeInterval(8)) == nil,
                     "the same request in the next reading adds no news")
        suite.expect(tracker.observe(snapshot(done), at: start.addingTimeInterval(10))
                         == .finished(id: "r1", outcome: .completed, at: start.addingTimeInterval(10), elapsed: 10),
                     "a completed count that grew confirms the completion, and the clock freezes at its length")
        suite.expect(tracker.elapsed(at: start.addingTimeInterval(600)) == 10,
                     "a finished task's clock stays at the length it froze at")
        // The completion does not start a new task by itself; the page clears it.
        suite.expect(tracker.observe(snapshot(busy), at: start.addingTimeInterval(601)) == nil,
                     "a finished task holds until it is cleared")
        tracker.clearFinished()
        suite.expect(tracker.phase == .idle, "clearing a finished task returns the tracker to idle")
        suite.expect(tracker.observe(snapshot(busy), at: start.addingTimeInterval(602))
                         == .started(id: "r1", at: start.addingTimeInterval(602)),
                     "the next request begins the next task, its clock at zero")
        suite.expect(tracker.elapsed(at: start.addingTimeInterval(604)) == 2, "the new task is timed on its own")

        // A request that vanishes with nothing moved is not a completion.
        var vanished = NotchSplashTaskTracker()
        suite.expect(vanished.observe(snapshot(busy), at: start) != nil, "the task begins")
        suite.expect(vanished.observe(snapshot(idle), at: start.addingTimeInterval(2)) == nil,
                     "one reading with the request gone is not proof of anything")
        suite.expect(vanished.observe(snapshot(idle), at: start.addingTimeInterval(4))
                         == .finished(id: "r1", outcome: .lost, at: start.addingTimeInterval(4), elapsed: 4),
                     "a request gone with every counter where it was is lost, never completed")

        // A server that restarted lost the request; that is not a completion.
        let restarted = #"{"instance": {"id": "b"}, "requests": {"completed": 9}, "active_requests": []}"#
        var restart = NotchSplashTaskTracker()
        suite.expect(restart.observe(snapshot(busy), at: start) != nil, "the task begins")
        suite.expect(restart.observe(snapshot(restarted), at: start.addingTimeInterval(3))
                         == .finished(id: "r1", outcome: .lost, at: start.addingTimeInterval(3), elapsed: 3),
                     "a new instance is a lost request, and its higher counters are not its own completion")

        // A server with no counters cannot confirm an ending.
        var mute = NotchSplashTaskTracker()
        let muteBusy = #"{"instance": {"id": "a"}, "active_requests": [{"id": "r1"}]}"#
        let muteIdle = #"{"instance": {"id": "a"}, "active_requests": []}"#
        suite.expect(mute.observe(snapshot(muteBusy), at: start) != nil, "the task begins with no counters in sight")
        suite.expect(mute.observe(snapshot(muteIdle), at: start.addingTimeInterval(2))
                         == .finished(id: "r1", outcome: .lost, at: start.addingTimeInterval(2), elapsed: 2),
                     "a server that reports no counters says nothing about how a request ended")

        // Failure and cancellation are their own endings.
        var failed = NotchSplashTaskTracker()
        suite.expect(failed.observe(snapshot(busy), at: start) != nil, "the task begins")
        suite.expect(failed.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3, "failed": 1}, "active_requests": []}"#),
                                     at: start.addingTimeInterval(5))
                         == .finished(id: "r1", outcome: .failed, at: start.addingTimeInterval(5), elapsed: 5),
                     "a failed count that grew is a failure, not a completion")
        var cancelled = NotchSplashTaskTracker()
        suite.expect(cancelled.observe(snapshot(busy), at: start) != nil, "the task begins")
        suite.expect(cancelled.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3, "cancelled": 2}, "active_requests": []}"#),
                                        at: start.addingTimeInterval(5))
                         == .finished(id: "r1", outcome: .cancelled, at: start.addingTimeInterval(5), elapsed: 5),
                     "a cancelled count that grew is a cancellation")

        // Overlapping requests: the one being timed keeps its own clock, and
        // a request that joins does not replace it.
        var overlap = NotchSplashTaskTracker()
        _ = overlap.observe(snapshot(busy), at: start)
        suite.expect(overlap.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3}, "active_requests": [{"id": "r1"}, {"id": "r2"}]}"#),
                                     at: start.addingTimeInterval(4)) == nil,
                     "a request that joins leaves the tracked one alone")
        suite.expect(overlap.trackedID == "r1" && overlap.elapsed(at: start.addingTimeInterval(9)) == 9,
                     "the tracked request keeps its own clock")
        // r1 leaves while r2 goes on, and the counters moved once: that one
        // ending is read as r1's, and the next request starts afresh.
        suite.expect(overlap.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": [{"id": "r2"}]}"#),
                                     at: start.addingTimeInterval(10))
                         == .finished(id: "r1", outcome: .completed, at: start.addingTimeInterval(10), elapsed: 10),
                     "one completed count moved is attributed to the request being timed")

        // Spilling is told by a counter that grew between two readings.
        var spilling = NotchSplashTaskTracker()
        suite.expect(!spilling.isSpilling, "nothing has spilled before the first reading")
        _ = spilling.observe(snapshot(#"{"kv": {"spill_count": 0}}"#, at: start), at: start)
        suite.expect(!spilling.isSpilling, "a counter that starts at nothing and stays there is quiet")
        _ = spilling.observe(snapshot(#"{"kv": {"spill_count": 0}}"#, at: start), at: start)
        suite.expect(!spilling.isSpilling, "a counter that does not move is quiet")
        _ = spilling.observe(snapshot(#"{"kv": {"spill_count": 3}}"#, at: start), at: start)
        suite.expect(spilling.isSpilling, "a counter that grew is spilling now")
        _ = spilling.observe(snapshot(#"{"kv": {"spill_count": 3}}"#, at: start), at: start)
        suite.expect(!spilling.isSpilling, "a counter that stopped growing is not spilling any more")

        // A session begun again starts the clock over.
        var begun = NotchSplashTaskTracker()
        _ = begun.observe(snapshot(busy), at: start)
        begun.begin()
        suite.expect(begun.phase == .idle && begun.elapsed(at: start.addingTimeInterval(100)) == 0,
                     "beginning a session leaves no task and no clock")

        let reading = NotchSplashSnapshot(status: status(busy), fetchedAt: start)
        suite.expect(reading.instanceKey == "id:a", "a reading belongs to its instance")
        suite.expect(NotchSplashSnapshot(status: status(#"{"instance": {"started_at": 100}}"#),
                                         fetchedAt: start).instanceKey == "started:100",
                     "an instance with no id is its start")
        suite.expect(NotchSplashSnapshot(status: status(#"{"requests": {"completed": 1}}"#),
                                         fetchedAt: start).instanceKey == "unidentified",
                     "an instance that names itself nowhere is unidentified, and its reading is treated with care")
        let later = NotchSplashSnapshot(status: status(#"{"instance": {"id": "a"}}"#),
                                        fetchedAt: start.addingTimeInterval(600))
        suite.expect(later.instanceKey == reading.instanceKey,
                     "the same server is named the same way an hour later, so its task is not lost")
    }

    // MARK: - Notices, once each

    static func noticeChecks(_ suite: TestSuite) {
        var notices = NotchSplashAnnouncements()
        suite.expect(notices.take(id: "r1", outcome: .completed), "a completion is news the first time")
        suite.expect(!notices.take(id: "r1", outcome: .completed),
                     "the same request is never announced twice, however often its status is read")
        suite.expect(!notices.take(id: "r2", outcome: .lost) && !notices.takeUnsuccessful(id: "r2", outcome: .lost),
                     "a task the reading cannot account for is never announced")
        suite.expect(notices.takeUnsuccessful(id: "r2", outcome: .failed), "a failed task is its own news")
        suite.expect(!notices.takeUnsuccessful(id: "r2", outcome: .failed), "a failed task is announced once")
        suite.expect(notices.takeUnsuccessful(id: "r3", outcome: .cancelled), "a cancellation is news")
        suite.expect(!notices.takeUnsuccessful(id: "r3", outcome: .cancelled), "a cancellation is news once")
        suite.expect(!notices.takeUnsuccessful(id: "r4", outcome: .completed),
                     "a completion is not told as a failure")
        suite.expect(notices.announcedIDs.isSuperset(of: ["r1", "r2", "r3"]), "the ids announced are kept")
        notices.reset()
        suite.expect(notices.announcedIDs.isEmpty, "a new session announces afresh")
    }

    // MARK: - The ruler shared with the timer

    static func rulerChecks(_ suite: TestSuite) {
        let seconds = NotchRulerScale.seconds
        suite.expect(seconds.minimum == 1 && seconds.maximum == 10 && seconds.count == 10,
                     "the interval ruler holds the whole seconds from 1 to 10")
        for value in 1...10 {
            suite.expect(seconds.value(Double(value)) == value && seconds.value(Double(value) + 0.4) == value,
                         "the ruler rests on a whole second")
        }
        suite.expect(seconds.value(0) == 1 && seconds.value(-5) == 1 && seconds.value(11) == 10
                         && seconds.value(.nan) == 1,
                     "a drag past either end stays at the end, and a number that is not a number is the first value")
        suite.expect(seconds.moving(5, by: seconds.spacing) == 4 && seconds.moving(5, by: -seconds.spacing) == 6,
                     "dragging one spacing is one second, in the direction the ruler moves")
        suite.expect(seconds.moving(1, by: 500) == 1 && seconds.moving(10, by: -500) == 10,
                     "a long drag never leaves the range")
        suite.expect(seconds.offset(of: 3, selected: 5) == -2 * seconds.spacing,
                     "a value two seconds behind the one in effect sits two spacings left")
        // A short range is centred inside the ruler, so the 1s and 10s ticks
        // both show, as the timer's do near their ends.
        let centre = seconds.selectionX(selected: 5, width: 300)
        suite.expect(centre == (300 - 9 * seconds.spacing) / 2 + 4 * seconds.spacing,
                     "the middle of a short range sits in the middle of the ruler")
        let first = seconds.selectionX(selected: 1, width: 300)
        suite.expect(first == (300 - 9 * seconds.spacing) / 2, "the first second sits where its ticks fit")
        suite.expect(seconds.selectionX(selected: 1, width: 60) >= 0
                         && seconds.selectionX(selected: 10, width: 60) <= 60,
                     "a narrow ruler keeps its pointer inside itself")
        suite.expect(seconds.showsLabel(1) && seconds.showsLabel(7) && seconds.showsLabel(10),
                     "every second of the interval ruler is written")
        let minutes = NotchRulerScale.minutes
        suite.expect(minutes.minimum == 1 && minutes.maximum == 180 && minutes.labelEvery == 5,
                     "the timer's ruler keeps its own range and labelling")
        suite.expect(minutes.showsLabel(1) && minutes.showsLabel(5) && !minutes.showsLabel(7),
                     "the timer writes every fifth minute, and the first")
        suite.expect(minutes.selectionX(selected: 5, width: 300) == 80
                         && minutes.selectionX(selected: 90, width: 300) == 150,
                     "the shared arithmetic answers the timer's ruler as it always did")
        suite.expect(NotchTimerRulerScale.minute(200) == 180
                         && NotchTimerRulerScale.moving(1, by: -3_000) == 180
                         && NotchTimerRulerScale.moving(180, by: 3_000) == 1,
                     "the timer's own wrapper keeps the old names and their range")
    }

    // MARK: - The dashboard's composition

    static func dashboardChecks(_ suite: TestSuite) {
        suite.expect(NotchDashboardSupport.activities(players: [7], timer: true, splash: true)
                         == [.player(id: 7), .timer, .splash],
                     "the Splash card follows the timer's in the Live Activities section")
        suite.expect(NotchDashboardSupport.activities(players: [], timer: false, splash: true) == [.splash],
                     "a session with no players and no timer is a card of its own")
        suite.expect(NotchDashboardSupport.activities(players: [], timer: true, splash: false) == [.timer],
                     "no session leaves the section as it was")
        suite.expect(NotchDashboardSupport.activities(players: [7, 9], timer: true).last != .splash,
                     "a session that ended takes its card away, and the cards before it stay")
        suite.expect(NotchDashboardActivity.splash.id == "splash", "the card has a stable identity")
        suite.expect(NotchDashboardLayout.activityHeight(.splash) == NotchSplashLayout.cardHeight,
                     "the island measures the card as the card measures itself")
        suite.expect(NotchDashboardLayout.liveActivitiesHeight([.timer, .splash])
                         == NotchDashboardLayout.timerCardHeight + NotchSplashLayout.cardHeight
                            + NotchDashboardLayout.cardSpacing,
                     "two cards are their heights and the gap between them")
        suite.expect(NotchSplashLayout.cardHeight > NotchSplashLayout.metricCardHeight
                         && NotchSplashLayout.metricCardHeight > NotchSplashLayout.valueSize,
                     "the card is taller than the reading inside it, and the reading taller than its figure")
        suite.expect(NotchSplashLayout.pageHeight >= NotchSplashLayout.cardHeight
                         && NotchSplashLayout.pageMinimumHeight < NotchSplashLayout.pageHeight,
                     "the page is as tall as the card it carries, with a floor beneath it")
    }

    // MARK: - Every language

    /// The words of one language, by field name.
    private static func fields(_ value: NotchSplashStrings) -> [String: String] {
        var result: [String: String] = [:]
        for child in Mirror(reflecting: value).children {
            guard let name = child.label, let text = child.value as? String else { continue }
            result[name] = text
        }
        return result
    }

    /// The fields whose words carry numbers, so their places can be compared.
    private static let countedFields: Set<String> = [
        "everyInterval", "hitsAndRequests", "noAnswer", "serverAnswered",
        "notifyCompletedBody",
    ]

    static func localizationChecks(_ suite: TestSuite) {
        let english = FeatureStrings.notchSplash(.enUS)
        let base = fields(english)
        suite.expect(!base.isEmpty, "the dashboard's words are read as fields")
        suite.expect(base["notifyCompletedBody"].map { TestFormat.parse($0)?.arguments == [1: "@"] } ?? false,
                     "the completion notice carries the task's clock in its place")
        for language in AppLanguage.allCases {
            let value = fields(FeatureStrings.notchSplash(language))
            suite.expect(Set(value.keys) == Set(base.keys), "every language answers to the same words")
            var blanks: [String] = []
            for (key, text) in value where text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blanks.append(key)
            }
            suite.expect(blanks.isEmpty, "no word is left empty in \(language.rawValue)")
            for key in countedFields {
                guard let expected = base[key].flatMap(TestFormat.parse) else {
                    suite.expect(false, "English.\(key) is a field with a readable format")
                    continue
                }
                let actual = value[key].flatMap(TestFormat.parse)
                suite.expect(actual?.arguments == expected.arguments,
                             "\(language.rawValue).\(key): the numbers keep their places")
            }
        }
        suite.expect(english.notifyCompletedTitle == "Splash Task Completed",
                     "the completion notice is titled as the task's own")
        suite.expect(english.decode == "Decode Speed" && english.prefill == "Prefill Speed"
                         && english.ttft == "TTFT" && english.cacheHitRate == "Cache Hit Rate",
                     "the four readings are named as the reference names them")
        suite.expect(english.tokensPerSecond == "tok/s", "the throughput's unit is the reference's")
        suite.expect(english.hitsAndRequests(55, 57) == "55 hits / 57 requests",
                     "the counters are read out with both counts named")
        suite.expect(english.intervalLabel(2) == "Every 2 seconds", "the interval is spoken in seconds")
    }

    // MARK: - Colour, as one set

    static func paletteChecks(_ suite: TestSuite) {
        // The governor's limit is orange first; its headroom only deepens it.
        suite.expect(NotchSplashPalette.tone(.green, reference: NotchSplashPalette.orange)
                         == NotchSplashPalette.tone(.orange, reference: NotchSplashPalette.orange),
                     "the limit is written in its own colour while it has headroom")
        suite.expect(NotchSplashPalette.tone(.amber, reference: NotchSplashPalette.orange) == NotchSplashPalette.amber
                         && NotchSplashPalette.tone(.red, reference: NotchSplashPalette.orange) == NotchSplashPalette.red,
                     "a limit running out is coloured by its pressure")
        suite.expect(NotchSplashPalette.tone(.green) == NotchSplashPalette.green
                         && NotchSplashPalette.tone(.blue) == NotchSplashPalette.blue
                         && NotchSplashPalette.tone(.purple) == NotchSplashPalette.purple
                         && NotchSplashPalette.tone(.beige) == NotchSplashPalette.beige,
                     "each tone has its own colour")
        suite.expect(NotchSplashPalette.tone(.neutral) != NotchSplashPalette.green
                         && NotchSplashPalette.red != NotchSplashPalette.green,
                     "a missing reading is not shown as a good one")
    }

    // MARK: - The session's rules

    /// What the page may do before it reads anything: the switch that lets it
    /// read at all, the address it needs, and the interval it keeps. These
    /// are the guards the session's Start button answers with, stated where
    /// they live.
    static func sessionChecks(_ suite: TestSuite) {
        let suiteName = "vorss.tests.splash.session.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let keys = [DefaultsKey.notchSplashEnabled, DefaultsKey.notchSplashHost,
                    DefaultsKey.notchSplashPort, DefaultsKey.notchSplashAPIKey,
                    DefaultsKey.notchSplashIntervalSeconds]
        for key in keys { defaults.removeObject(forKey: key) }
        defaults.register(defaults: [
            DefaultsKey.notchSplashEnabled: false,
            DefaultsKey.notchSplashHost: "",
            DefaultsKey.notchSplashPort: 8000,
            DefaultsKey.notchSplashAPIKey: "",
            DefaultsKey.notchSplashIntervalSeconds: 2,
        ])

        suite.expect(!NotchSplashSupport.isEnabled(in: defaults),
                     "a dashboard nobody switched on reads nothing")
        suite.expect(NotchSplashSupport.endpoint(in: defaults) == nil,
                     "without an address there is nothing to start, and no request is made")
        suite.expect(NotchSplashSupport.savedInterval(in: defaults) == 2,
                     "a dashboard left alone is polled every two seconds")

        defaults.set(true, forKey: DefaultsKey.notchSplashEnabled)
        defaults.set("127.0.0.1", forKey: DefaultsKey.notchSplashHost)
        defaults.set(8000, forKey: DefaultsKey.notchSplashPort)
        defaults.set(" sk-7 ", forKey: DefaultsKey.notchSplashAPIKey)
        suite.expect(NotchSplashSupport.isEnabled(in: defaults)
                         == AppFeature.notchSplash.isAvailable(in: defaults)
                         && NotchSplashSupport.endpoint(in: defaults)?.absoluteString
                             == "http://127.0.0.1:8000/status",
                     "an address configured, on a feature installed, is a server the session can read")
        suite.expect(NotchSplashEndpoint.authorization(defaults.string(forKey: DefaultsKey.notchSplashAPIKey) ?? "")
                         == "Bearer sk-7",
                     "a stored key is sent as a bearer token, trimmed of its spaces")

        defaults.set(11, forKey: DefaultsKey.notchSplashIntervalSeconds)
        suite.expect(NotchSplashSupport.savedInterval(in: defaults) == 2,
                     "an interval out of range is polled at the default, not at the stored nonsense")
        defaults.set(7, forKey: DefaultsKey.notchSplashIntervalSeconds)
        suite.expect(NotchSplashSupport.savedInterval(in: defaults) == 7,
                     "the interval chosen is the one the session keeps")

        defaults.set(false, forKey: DefaultsKey.notchSplashEnabled)
        suite.expect(!NotchSplashSupport.isEnabled(in: defaults),
                     "switching the dashboard off is heard at once, and stops nothing that is running")
        defaults.set(true, forKey: DefaultsKey.notchSplashEnabled)
        defaults.set("bad host", forKey: DefaultsKey.notchSplashHost)
        suite.expect(NotchSplashSupport.endpoint(in: defaults) == nil,
                     "an address with a space in it is no server, and the session says so")
        for key in keys { defaults.removeObject(forKey: key) }
    }

    static func run(_ suite: TestSuite) {
        suite.run("splash settings") { settingsChecks(suite) }
        suite.run("splash reading") { readingChecks(suite) }
        suite.run("splash metrics") { metricChecks(suite) }
        suite.run("splash text") { textChecks(suite) }
        suite.run("splash task") { taskChecks(suite) }
        suite.run("splash notices") { noticeChecks(suite) }
        suite.run("splash session") { sessionChecks(suite) }
        suite.run("splash ruler") { rulerChecks(suite) }
        suite.run("splash dashboard") { dashboardChecks(suite) }
        suite.run("splash strings") { localizationChecks(suite) }
        suite.run("splash palette") { paletteChecks(suite) }
    }
}
