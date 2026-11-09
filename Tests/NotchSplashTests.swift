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
        // The window is shortened so a whole task, with its pauses, fits in a
        // minute of the test's clock. The app's window is the long one, and it
        // is checked below at its own value.
        func task() -> NotchSplashTaskTracker { NotchSplashTaskTracker(quiescence: 30, quietReadingsNeeded: 2) }
        suite.expect(NotchSplashSupport.taskQuiescenceSeconds == 60
                         && NotchSplashSupport.taskQuiescenceReadings == 2,
                     "the app's window is a minute of quiet and two quiet readings, which is longer than the pauses a task takes between its turns")

        let busy = #"{"instance": {"id": "a"}, "requests": {"completed": 3}, "active_requests": [{"id": "r1"}]}"#
        let turn = #"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": []}"#
        let nextTurn = #"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": [{"id": "r2"}]}"#
        let lastTurn = #"{"instance": {"id": "a"}, "requests": {"completed": 5}, "active_requests": []}"#

        var tracker = task()
        suite.expect(tracker.phase == .idle && tracker.elapsed(at: start) == 0,
                     "a session begun over an idle server has no task and no clock")
        suite.expect(tracker.observe(snapshot(busy), at: start) == .started(id: "r1", at: start),
                     "work seen is a task begun")
        suite.expect(tracker.elapsed(at: start.addingTimeInterval(7)) == 7,
                     "the clock runs with the work")
        suite.expect(tracker.observe(snapshot(busy), at: start.addingTimeInterval(8)) == nil,
                     "the same work in the next reading adds no news")

        // The heart of the rule. A coding agent's task is a run of requests:
        // one answers, the engine goes quiet while its client thinks and runs
        // a tool, the next request arrives. The counters move, one request
        // ends, and the task is not over - so nothing is announced and the
        // clock does not freeze.
        suite.expect(tracker.observe(snapshot(turn), at: start.addingTimeInterval(10)) == nil,
                     "a request answered in the middle of a task is not the task's end")
        suite.expect(tracker.isRunning && tracker.trackedID == "r1",
                     "the task is still the same task after a turn answered")
        suite.expect(tracker.observe(snapshot(turn), at: start.addingTimeInterval(20)) == nil,
                     "a quiet stretch inside the window says nothing")
        suite.expect(tracker.elapsed(at: start.addingTimeInterval(21)) == 21,
                     "and its clock keeps running across the pause")
        suite.expect(tracker.observe(snapshot(nextTurn), at: start.addingTimeInterval(22)) == nil,
                     "the next request of the same task is not a new task")
        suite.expect(tracker.isRunning && tracker.trackedID == "r1"
                         && tracker.elapsed(at: start.addingTimeInterval(25)) == 25,
                     "the task goes on as one task, its clock never reset by a turn")
        suite.expect(tracker.observe(snapshot(lastTurn), at: start.addingTimeInterval(26)) == nil,
                     "the first quiet reading is not yet the end")
        suite.expect(tracker.observe(snapshot(lastTurn), at: start.addingTimeInterval(50)) == nil,
                     "a quiet of 24 seconds is inside the window, and says nothing")
        suite.expect(tracker.observe(snapshot(lastTurn), at: start.addingTimeInterval(60))
                         == .finished(id: "r1", outcome: .completed, at: start.addingTimeInterval(26), elapsed: 26),
                     "a quiet that outlasts the window ends the task, timed to where the quiet began")
        suite.expect(tracker.elapsed(at: start.addingTimeInterval(600)) == 26,
                     "a finished task's clock stays at the length it froze at")
        suite.expect(tracker.observe(snapshot(lastTurn), at: start.addingTimeInterval(300)) == nil,
                     "an idle reading after a completion says nothing")
        suite.expect(tracker.phase == .finished(id: "r1", outcome: .completed,
                                                at: start.addingTimeInterval(26), elapsed: 26),
                     "the finished task is held across the idle stretch, its clock where it froze")
        // The next prompt the server works on is the next task, at once, with
        // its own clock from zero - no clearing asked of the page, and the
        // counters read from where they stand now.
        suite.expect(tracker.observe(snapshot(nextTurn), at: start.addingTimeInterval(301))
                         == .started(id: "r2", at: start.addingTimeInterval(301)),
                     "work seen after a finished task begins the next task with no clearing")
        suite.expect(tracker.elapsed(at: start.addingTimeInterval(303)) == 2,
                     "the new task is timed on its own, from zero")
        // Two tasks the server named the same are two news, keyed by the
        // second each began - which is what lets the second one be told.
        let firstKey = NotchSplashTaskTracker.announceKey(id: "r1", at: start.addingTimeInterval(26), elapsed: 26)
        let secondKey = NotchSplashTaskTracker.announceKey(id: "r1", at: start.addingTimeInterval(326), elapsed: 25)
        suite.expect(firstKey != secondKey,
                     "two tasks under one id are keyed apart, so the second completion is news")
        suite.expect(NotchSplashTaskTracker.announceKey(id: "r1", at: start.addingTimeInterval(326), elapsed: 25)
                         == secondKey,
                     "one task's key is the same every time it is asked, so it is never told twice")
        // Clearing is the way out's doing, and it works on a finished task:
        // a running task is the person's own business and is left alone.
        var cleared = task()
        _ = cleared.observe(snapshot(busy), at: start)
        _ = cleared.observe(snapshot(turn), at: start.addingTimeInterval(10))
        _ = cleared.observe(snapshot(turn), at: start.addingTimeInterval(60))
        suite.expect(cleared.isFinished, "a task that ran out its quiet window is finished")
        cleared.clearFinished()
        suite.expect(cleared.phase == .idle && cleared.elapsed(at: start) == 0,
                     "clearing a finished task returns the tracker to idle, which is what the way out does")
        var runningCleared = task()
        _ = runningCleared.observe(snapshot(busy), at: start)
        runningCleared.clearFinished()
        suite.expect(runningCleared.isRunning,
                     "a task still running is not cleared by a page reopening, so its clock survives")

        // A server that numbers its requests by position hands the same id to
        // every request, and consecutive tasks must still be two tasks.
        let positionalBusy = #"{"instance": {"id": "a"}, "requests": {"completed": 3}, "active_requests": [{"model": "splash"}]}"#
        var positional = task()
        suite.expect(positional.observe(snapshot(positionalBusy), at: start)
                         == .started(id: "position.0", at: start),
                     "a request with no id of its own is timed by its place")
        suite.expect(positional.observe(snapshot(turn), at: start.addingTimeInterval(6)) == nil,
                     "a turn answered inside the window is not the end of a positional task")
        suite.expect(positional.observe(snapshot(turn), at: start.addingTimeInterval(40))
                         == .finished(id: "position.0", outcome: .completed,
                                      at: start.addingTimeInterval(6), elapsed: 6),
                     "the first positional task is completed on its counters")
        suite.expect(positional.observe(snapshot(positionalBusy), at: start.addingTimeInterval(70))
                         == .started(id: "position.0", at: start.addingTimeInterval(70)),
                     "the next request is a new task even when the server's only name for it is the same place")
        suite.expect(NotchSplashTaskTracker.announceKey(id: "position.0", at: start.addingTimeInterval(6), elapsed: 6)
                         != NotchSplashTaskTracker.announceKey(id: "position.0",
                                                                at: start.addingTimeInterval(76), elapsed: 6),
                     "two positional tasks are keyed apart, so each one's news is told")

        // Work is work on any count the server keeps, not only in the list of
        // requests it names: the scheduler's own figures, what the transport
        // holds, what HTTP has in flight, and a snapshot the engine answered
        // from while it was mid-loop, all say the server is busy.
        suite.expect(status(#"{"instance": {"id": "a"}, "scheduler": {"decoding": 1}}"#).hasWork,
                     "the scheduler decoding is work")
        suite.expect(status(#"{"instance": {"id": "a"}, "scheduler": {"queued": 2}}"#).hasWork,
                     "a request queued behind another is work")
        suite.expect(status(#"{"instance": {"id": "a"}, "transport": {"pending": 1}}"#).hasWork,
                     "a request the server has accepted is work")
        suite.expect(status(#"{"instance": {"id": "a"}, "http": {"requests": {"active": 1}}}"#).hasWork,
                     "a client request in flight is work, before the engine names it")
        suite.expect(status(#"{"instance": {"id": "a"}, "transport": {"status_stale": true}}"#).hasWork,
                     "a snapshot answered from mid-loop is not proof of quiet")
        suite.expect(!status(#"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": [], "scheduler": {"decoding": 0}, "http": {"requests": {"active": 0}}}"#).hasWork,
                     "a server with nothing in hand is quiet, and the counts say so")
        var unnumbered = task()
        suite.expect(unnumbered.observe(snapshot(#"{"instance": {"id": "a"}, "scheduler": {"prefilling": 1}}"#), at: start)
                         == .started(id: NotchSplashTaskTracker.unnumbered, at: start),
                     "work the server does not name is a task too, timed from its start")

        // A server that restarted, a server with no counters, and a run that
        // moved nothing are not completions.
        var vanished = task()
        suite.expect(vanished.observe(snapshot(busy), at: start) != nil, "the task begins")
        suite.expect(vanished.observe(snapshot(busy), at: start.addingTimeInterval(2)) == nil,
                     "work seen in the next reading is the task going on")
        suite.expect(vanished.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3}, "active_requests": []}"#),
                                      at: start.addingTimeInterval(4)) == nil,
                     "one quiet reading with every counter where it was is not proof of anything")
        suite.expect(vanished.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3}, "active_requests": []}"#),
                                      at: start.addingTimeInterval(40))
                         == .finished(id: "r1", outcome: .lost, at: start.addingTimeInterval(4), elapsed: 4),
                     "work gone with every counter where it was is lost, never completed")

        let restarted = #"{"instance": {"id": "b"}, "requests": {"completed": 9}, "active_requests": []}"#
        var restart = task()
        suite.expect(restart.observe(snapshot(busy), at: start) != nil, "the task begins")
        suite.expect(restart.observe(snapshot(restarted), at: start.addingTimeInterval(3)) == nil,
                     "a new instance mid-task is not an ending yet")
        suite.expect(restart.observe(snapshot(restarted), at: start.addingTimeInterval(35))
                         == .finished(id: "r1", outcome: .lost, at: start.addingTimeInterval(3), elapsed: 3),
                     "a new instance is a lost task, and its higher counters are not its own completion")

        var mute = task()
        let muteBusy = #"{"instance": {"id": "a"}, "active_requests": [{"id": "r1"}]}"#
        let muteQuiet = #"{"instance": {"id": "a"}, "active_requests": []}"#
        suite.expect(mute.observe(snapshot(muteBusy), at: start) != nil, "the task begins with no counters in sight")
        suite.expect(mute.observe(snapshot(muteQuiet), at: start.addingTimeInterval(3)) == nil,
                     "no counters and one quiet reading say nothing")
        suite.expect(mute.observe(snapshot(muteQuiet), at: start.addingTimeInterval(34))
                         == .finished(id: "r1", outcome: .lost, at: start.addingTimeInterval(3), elapsed: 3),
                     "a server that reports no counters says nothing about how a task ended")

        // Failure and cancellation are their own endings, told once, and they
        // are told only when the counters say so across the whole run.
        var failed = task()
        suite.expect(failed.observe(snapshot(busy), at: start) != nil, "the task begins")
        suite.expect(failed.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3, "failed": 1}, "active_requests": []}"#),
                                     at: start.addingTimeInterval(3)) == nil,
                     "a failure inside the window is not told yet")
        suite.expect(failed.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3, "failed": 1}, "active_requests": []}"#),
                                     at: start.addingTimeInterval(35))
                         == .finished(id: "r1", outcome: .failed, at: start.addingTimeInterval(3), elapsed: 3),
                     "a failed count that grew is a failure, not a completion")
        var cancelled = task()
        suite.expect(cancelled.observe(snapshot(busy), at: start) != nil, "the task begins")
        suite.expect(cancelled.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3, "cancelled": 2}, "active_requests": []}"#),
                                        at: start.addingTimeInterval(3)) == nil,
                     "a cancellation inside the window is not told yet")
        suite.expect(cancelled.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3, "cancelled": 2}, "active_requests": []}"#),
                                        at: start.addingTimeInterval(35))
                         == .finished(id: "r1", outcome: .cancelled, at: start.addingTimeInterval(3), elapsed: 3),
                     "a cancelled count that grew is a cancellation")
        // A run in which a turn failed and a later turn answered is a task
        // that produced an answer: the completed count outranks the failed.
        var retried = task()
        _ = retried.observe(snapshot(busy), at: start)
        suite.expect(retried.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3, "failed": 1}, "active_requests": [{"id": "r2"}]}"#),
                                     at: start.addingTimeInterval(5)) == nil,
                     "a failed turn with the next turn already running is not an ending")
        suite.expect(retried.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 4, "failed": 1}, "active_requests": []}"#),
                                     at: start.addingTimeInterval(40)) == nil,
                     "the quiet after the retried turn has to outlast the window before it is told")
        suite.expect(retried.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 4, "failed": 1}, "active_requests": []}"#),
                                     at: start.addingTimeInterval(75))
                         == .finished(id: "r1", outcome: .completed, at: start.addingTimeInterval(40), elapsed: 40),
                     "a task that answered after a failed turn is a completion, not a failure")

        // Overlapping requests: the run being timed keeps its own clock, and
        // a request that joins does not replace it.
        var overlap = task()
        _ = overlap.observe(snapshot(busy), at: start)
        suite.expect(overlap.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3}, "active_requests": [{"id": "r1"}, {"id": "r2"}]}"#),
                                     at: start.addingTimeInterval(4)) == nil,
                     "a request that joins leaves the tracked one alone")
        suite.expect(overlap.trackedID == "r1" && overlap.elapsed(at: start.addingTimeInterval(9)) == 9,
                     "the tracked request keeps its own clock")
        // One of the two answers while the other goes on: the run is not over,
        // and the counters that moved are not the run's ending.
        suite.expect(overlap.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": [{"id": "r2"}]}"#),
                                     at: start.addingTimeInterval(10)) == nil,
                     "one of two requests answering, with work still in hand, ends nothing")
        suite.expect(overlap.isRunning && overlap.trackedID == "r1",
                     "the run goes on with the request that stayed")

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
        var begun = task()
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
        // Two tasks of one server, whose only name for a request is its
        // place: the key carries the second each began, so the second task is
        // told and told once.
        suite.expect(notices.take(id: "position.0@1800000000", outcome: .completed),
                     "the first task of a server that names its requests by place is news")
        suite.expect(notices.take(id: "position.0@1800000060", outcome: .completed),
                     "the second task is news too, because its key is its own")
        suite.expect(!notices.take(id: "position.0@1800000060", outcome: .completed),
                     "and the second task is told once, like the first")
        suite.expect(!notices.takeUnsuccessful(id: "r4", outcome: .completed),
                     "a completion is not told as a failure")
        suite.expect(notices.announcedIDs.isSuperset(of: ["r1", "r2", "r3"]), "the ids announced are kept")
        notices.reset()
        suite.expect(notices.announcedIDs.isEmpty, "a new session announces afresh")
    }

    // MARK: - The reading that keeps going

    /// The rule the polling loop is asked, tested for the states a running
    /// session is really in. The dashboard promises to read until a hand takes
    /// the way out, and the idle stretch between two prompts - which is where
    /// a person spends most of an afternoon - is the state the rule must
    /// answer "keep reading" to, for as long as it lasts, and after any task's
    /// ending.
    static func monitoringChecks(_ suite: TestSuite) {
        typealias Rule = NotchSplashMonitoringPolicy
        suite.expect(!Rule.endsMonitoring(.init(idleSeconds: 5 * 60)),
                     "an idle five minutes is not a reason to stop reading")
        suite.expect(!Rule.endsMonitoring(.init(idleSeconds: 60 * 60 * 9)),
                     "an idle morning is not a reason to stop reading")
        for outcome: NotchSplashTaskTracker.Outcome in [.completed, .failed, .cancelled, .lost] {
            suite.expect(!Rule.endsMonitoring(.init(idleSeconds: 600, outcome: outcome)),
                         "a task that ended - and this one ended \(outcome) - is not a reason to stop reading")
        }
        suite.expect(!Rule.endsMonitoring(.init(idleSeconds: 10 * 60, outcome: .completed)),
                     "the state a session is in ten minutes after a prompt: idle, completed, and reading")
        suite.expect(!Rule.endsMonitoring(.init(stoppedByHand: false, sectionDisabled: false, noAddress: false)),
                     "nothing happening is not a reason to stop")
        suite.expect(Rule.endsMonitoring(.init(stoppedByHand: true, idleSeconds: 5, outcome: .completed)),
                     "a hand on the way out ends the reading")
        suite.expect(Rule.endsMonitoring(.init(sectionDisabled: true, idleSeconds: 600)),
                     "the section switched off ends the reading")
        suite.expect(Rule.endsMonitoring(.init(noAddress: true)),
                     "an address taken away ends the reading")
        suite.expect(Rule.endsMonitoring(.init(noAddress: true, idleSeconds: 0, outcome: nil))
                         && !Rule.endsMonitoring(.init(noAddress: false, idleSeconds: 0, outcome: nil)),
                     "the three reasons are the whole rule: nothing else in the condition ends a reading")
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
        // A range that fits the row is drawn as a fixed strip across four
        // fifths of it, so the ten numbers use the row they stand in, the
        // numbers do not touch each other, and the two ends keep the same
        // margin. This is the ruler's own arithmetic, not a smaller font.
        let width = 400.0
        let pitch = seconds.spacing(width: width)
        suite.expect(seconds.fitsEntireScale(width: width),
                     "the ten seconds are known to fit a row, which is what makes the ruler fixed and not sliding")
        suite.expect(abs(pitch - width * NotchRulerScale.fixedSpanFraction / 9) < 0.001,
                     "the ten ticks stand four fifths of the row apart, start to end")
        let widestLabel = Double(NotchRulerScale.widestLabelWidth(digits: 2))
        suite.expect(pitch >= widestLabel + 6,
                     "the pitch between ticks is wider than the widest number it carries, so 10 does not touch 9")
        suite.expect(pitch >= NotchRulerScale.minimumLabelPitch,
                     "ticks are never packed closer than the floor a label needs")
        let firstX = seconds.selectionX(selected: 1, width: width)
        let lastX = seconds.selectionX(selected: 10, width: width)
        suite.expect(abs((lastX - firstX) - width * NotchRulerScale.fixedSpanFraction) < 0.001,
                     "the first and last ticks are four fifths of the row apart")
        suite.expect(abs(firstX - (width - lastX)) < 0.001,
                     "the first and last ticks keep the same margin at either end")
        for value in 1...10 {
            suite.expect(abs(seconds.selectionX(selected: value, width: width)
                                 - (firstX + Double(value - 1) * pitch)) < 0.001,
                         "second \(value) stands on the pitch its neighbours use, so its number lines up with its tick")
        }
        suite.expect(seconds.selectionX(selected: 5, width: width) == seconds.pointerX(selected: 5, width: width),
                     "the pointer is above the tick in effect")
        suite.expect(seconds.moving(5, by: pitch, width: width) == 4
                         && seconds.moving(5, by: -pitch, width: width) == 6,
                     "a drag and a wheel travel by the ticks as they are drawn")
        suite.expect(seconds.offset(of: 3, selected: 5, width: width) == -2 * pitch,
                     "two seconds behind the tick in effect stand two pitches to the left")
        suite.expect(seconds.selectionX(selected: 1, width: 60) >= 0
                         && seconds.selectionX(selected: 10, width: 60) <= 60,
                     "a narrow ruler keeps its pointer inside itself")
        suite.expect(seconds.showsLabel(1) && seconds.showsLabel(7) && seconds.showsLabel(10),
                     "every second of the interval ruler is written")
        suite.expect(NotchSplashSupport.tickIntervalText(1) == "1"
                         && NotchSplashSupport.tickIntervalText(9) == "9"
                         && NotchSplashSupport.tickIntervalText(10) == "10",
                     "a tick's number is the whole seconds alone")
        suite.expect((1...10).allSatisfy { !NotchSplashSupport.tickIntervalText($0).contains("s") },
                     "no tick carries the unit, which is what was crowding the row")
        suite.expect(NotchSplashSupport.intervalText(2) == "2s",
                     "the value read beside the ruler keeps the unit, and the default is two seconds")
        let minutes = NotchRulerScale.minutes
        suite.expect(minutes.minimum == 1 && minutes.maximum == 180 && minutes.labelEvery == 5,
                     "the timer's ruler keeps its own range and labelling")
        suite.expect(minutes.showsLabel(1) && minutes.showsLabel(5) && !minutes.showsLabel(7),
                     "the timer writes every fifth minute, and the first")
        suite.expect(!minutes.fitsEntireScale(width: 300) && !minutes.fitsEntireScale(width: 1_000),
                     "180 minutes never fit a row, so the timer's ruler slides as it always has")
        suite.expect(minutes.spacing(width: 300) == 14 && minutes.spacing(width: 1_000) == 14
                         && minutes.spacing(width: 60) == 14,
                     "the timer's ruler keeps its own spacing at every width")
        suite.expect(minutes.selectionX(selected: 5, width: 300) == 80
                         && minutes.selectionX(selected: 90, width: 300) == 150,
                     "the shared arithmetic answers the timer's ruler as it always did")
        suite.expect(minutes.offset(of: 91, selected: 90) == 14
                         && minutes.offset(of: 91, selected: 90, width: 300) == 14
                         && minutes.moving(90, by: 14) == 89
                         && minutes.moving(90, by: 14, width: 300) == 89,
                     "the timer's dragging and its tick spacing are the numbers they were")
        suite.expect(NotchTimerRulerScale.minute(200) == 180
                         && NotchTimerRulerScale.moving(1, by: -3_000) == 180
                         && NotchTimerRulerScale.moving(180, by: 3_000) == 1,
                     "the timer's own wrapper keeps the old names and their range")
    }

    // MARK: - The dashboard's composition

    static func dashboardChecks(_ suite: TestSuite) {
        suite.expect(NotchSplashSupport.showsDashboardCard(sectionVisible: true, isMonitoring: true),
                     "a reading begun at Start has its card in Live Activities at once")
        suite.expect(NotchSplashSupport.showsDashboardCard(sectionVisible: true, isMonitoring: true),
                     "the same card stands through the idle stretch after a task, because a task's ending leaves the reading running")
        suite.expect(!NotchSplashSupport.showsDashboardCard(sectionVisible: true, isMonitoring: false),
                     "the way out ends the reading and takes the card with it")
        suite.expect(!NotchSplashSupport.showsDashboardCard(sectionVisible: false, isMonitoring: true),
                     "a section not in the island has no card, reading or not")
        // The three rules as the service puts them together, for the state a
        // session is in right after a prompt finishes: the task froze, the
        // reading is not asked to stop, and the rule keeps the card.
        var finished = NotchSplashTaskTracker(quiescence: 30, quietReadingsNeeded: 2)
        _ = finished.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3}, "active_requests": [{"id": "r1"}]}"#),
                             at: start)
        suite.expect(finished.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": []}"#),
                                      at: start.addingTimeInterval(10)) == nil,
                     "a prompt answered inside the window keeps the card on a task that is still running")
        let ended = finished.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": []}"#),
                                     at: start.addingTimeInterval(45))
        suite.expect(ended == .finished(id: "r1", outcome: .completed, at: start.addingTimeInterval(10), elapsed: 10)
                         && finished.elapsed(at: start.addingTimeInterval(600)) == 10
                         && !NotchSplashMonitoringPolicy.endsMonitoring(.init(idleSeconds: 600, outcome: .completed))
                         && NotchSplashSupport.showsDashboardCard(sectionVisible: true, isMonitoring: true),
                     "a completed task freezes its clock, leaves the reading running, and keeps its card across the idle stretch")
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
        suite.expect(NotchSplashLayout.cardHeight
                         == NotchSplashLayout.padding * 2 + NotchSplashLayout.headerHeight
                            + NotchSplashLayout.headerSpacing + NotchSplashLayout.metricCardHeight,
                     "the card is the header's line, one gap, and the four readings: the rule under the header is gone from the measure")
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
        suite.expect(english.title == "Splash Dashboard",
                     "the header is written as the words of a heading, and the card writes them as they are")
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

    // MARK: - A whole session, read

    /// The promise the dashboard makes, tested as a session that runs: the
    /// reading begins at Start, goes on across an idle afternoon, times a
    /// request, freezes at its end, tells its news once, keeps reading, takes
    /// up the next request as its own task with its own news, and stops only
    /// when a hand stops it.
    ///
    /// The session is the app's own class, given a world it can be asked
    /// questions about: the status documents are made here, the clock is
    /// turned forward by hand, and the notices are caught in a list. The
    /// polling, the task, the freezing and the notices are the code the island
    /// runs.
    static func pollingChecks(_ suite: TestSuite) {
        let server = URL(string: "http://127.0.0.1:8010/status")!
        let idle = #"{"instance": {"id": "a"}, "requests": {"completed": 3, "failed": 0, "cancelled": 0}, "active_requests": []}"#
        func running(_ id: String, completed: Int) -> String {
            "{\"instance\": {\"id\": \"a\"}, \"requests\": {\"completed\": \(completed), \"failed\": 0, \"cancelled\": 0}, "
                + "\"active_requests\": [{\"id\": \"\(id)\"}]}"
        }
        func done(_ completed: Int, failed: Int = 0) -> String {
            "{\"instance\": {\"id\": \"a\"}, \"requests\": {\"completed\": \(completed), \"failed\": \(failed), \"cancelled\": 0}, "
                + "\"active_requests\": []}"
        }

        let world = PollingWorld(start: start, documents: [idle])
        let service = NotchSplashService(
            read: { _, _, key in
                world.keys.append(key ?? "")
                return (Data(world.nextDocument().utf8), world.code)
            },
            address: { world.address },
            enabled: { world.enabled },
            savedInterval: { world.interval },
            savedKey: { world.key },
            keepInterval: { world.kept.append($0) },
            clock: { world.now },
            strings: { FeatureStrings.notchSplash(.enUS) },
            deliver: { world.notices.append($0) })

        func spin(_ seconds: TimeInterval) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }

        MainActor.assumeIsolated {
            service.start()
            suite.expect(service.isMonitoring, "Start begins the reading")
            spin(1.4)
            suite.expect(service.reads >= 1 && service.snapshot != nil,
                         "the reading asks the server and has its first answer")
            suite.expect(service.phase == .idle && service.trackedID == nil && service.elapsed() == 0,
                         "a reading begun over an idle server times nothing and shows no clock")
            suite.expect(world.notices.isEmpty, "an idle server has nothing to announce")

            // An idle afternoon: the clock is turned forward by five minutes,
            // which is the state a person is in between two prompts, and the
            // reading is asked what it does.
            world.now = world.now.addingTimeInterval(5 * 60)
            let before = service.reads
            spin(2.4)
            suite.expect(service.reads > before + 1 && service.isMonitoring,
                         "an idle five minutes does not stop the reading: it is still asking")
            suite.expect(service.phase == .idle && service.snapshot != nil,
                         "and it is still showing what it last read")

            // A prompt begins: the request appears, and the task is timed.
            world.documents = [running("req-a", completed: 3)]
            spin(1.4)
            suite.expect(service.phase == .running(id: "req-a", startedAt: world.now)
                             && service.isTaskRunning && service.trackedID == "req-a",
                         "a request the server reports is taken up as a task")
            world.now = world.now.addingTimeInterval(34)
            spin(1.4)
            suite.expect(service.elapsed() >= 34 && service.isMonitoring,
                         "the task's clock runs with the request")

            // One request answers and the engine goes quiet for ten seconds:
            // the shape of a coding task between two of its turns. The
            // completed count moved, and the task is not over - so nothing is
            // announced, the clock does not freeze, and the card keeps
            // counting. This is the false completion the dashboard must not
            // tell.
            world.documents = [done(4)]
            world.now = world.now.addingTimeInterval(10)
            spin(1.4)
            suite.expect(service.isTaskRunning && service.taskOutcome == nil,
                         "a request answered in the middle of a task leaves the task running")
            suite.expect(world.notices.isEmpty,
                         "and no completion is told, however much the counters moved")
            suite.expect(service.elapsed() >= 44, "the clock keeps running through the pause")

            // The next turn arrives inside the window: the same task, one
            // clock, no second task begun and no second notice.
            world.documents = [running("req-a2", completed: 4)]
            spin(1.4)
            suite.expect(service.isTaskRunning && service.trackedID == "req-a",
                         "the next request inside the window does not begin a second task")
            suite.expect(service.isMonitoring && world.notices.isEmpty,
                         "the reading goes on and nothing is told")

            // The engine answers and stays quiet. The task is over when the
            // quiet has outlasted the window: its clock freezes at where the
            // quiet began, its news is told once with that length, and the
            // reading goes on - which is the whole of what the dashboard
            // promises.
            world.documents = [done(5)]
            world.now = world.now.addingTimeInterval(5)
            spin(1.4)
            suite.expect(service.isTaskRunning && world.notices.isEmpty,
                         "the first quiet reading is not the end of the task")
            world.now = world.now.addingTimeInterval(61)
            spin(2.6)
            suite.expect(service.taskOutcome == .completed && service.isTaskFinished,
                         "a quiet that outlasts the window is the task's end, confirmed by its counter")
            suite.expect(Int(service.elapsed()) == 49,
                         "the clock froze at where the quiet began, not at where the notice was sent")
            suite.expect(service.isMonitoring, "the completion did not stop the reading")
            suite.expect(world.notices.count == 1,
                         "one task is one notice, whatever turns it had")
            suite.expect(world.notices.first?.title == "Splash Task Completed"
                             && world.notices.first?.body.contains("00:49") == true,
                         "the notice names the task and carries its frozen length")
            let afterCompletion = service.reads
            world.now = world.now.addingTimeInterval(6 * 60)
            spin(2.4)
            suite.expect(service.reads > afterCompletion && service.isMonitoring,
                         "the reading goes on across the idle stretch after a task")
            suite.expect(service.taskOutcome == .completed && Int(service.elapsed()) == 49,
                         "the finished task holds its clock and its numbers across that stretch")
            spin(1.4)
            suite.expect(world.notices.count == 1, "the same completion is not told twice")

            // The next prompt: its own request, its own clock from zero, its
            // own news - and the same card, since the reading never ended.
            world.documents = [running("req-b", completed: 5)]
            spin(1.4)
            suite.expect(service.trackedID == "req-b" && service.isTaskRunning
                             && service.elapsed(at: world.now) < 2,
                         "the second request is a second task, its clock at zero")
            world.now = world.now.addingTimeInterval(7)
            spin(1.4)
            world.documents = [done(6)]
            world.now = world.now.addingTimeInterval(5)
            spin(1.4)
            world.now = world.now.addingTimeInterval(61)
            spin(2.6)
            suite.expect(service.taskOutcome == .completed && Int(service.elapsed()) == 12,
                         "the second task is timed and frozen on its own length")
            suite.expect(world.notices.count == 2 && world.notices.last?.body.contains("00:12") == true,
                         "the second completion is its own notice")
            suite.expect(service.isMonitoring, "and the reading is still running")

            // A task that fails is told as a failure, and the reading goes on
            // to take up the next request. The completed count does not move:
            // only the failed one does, which is what makes this a failure.
            world.documents = [running("req-c", completed: 5)]
            spin(1.4)
            world.documents = [done(5, failed: 1)]
            world.now = world.now.addingTimeInterval(5)
            spin(1.4)
            world.now = world.now.addingTimeInterval(61)
            spin(2.6)
            suite.expect(world.notices.count == 3 && world.notices.last?.title.contains("Failed") == true
                             && service.isMonitoring && service.phase == .idle,
                         "a failed task is told as a failure, the clock is cleared, and the reading goes on")

            // A server that does not answer is a reason to say so, never a
            // reason to stop reading.
            world.code = 401
            spin(1.4)
            suite.expect(service.failure == .status(401) && service.isMonitoring,
                         "an answer that is not 200 is named on the card, and the reading goes on")
            world.code = 200
            world.documents = ["not a document at all"]
            spin(1.4)
            suite.expect(service.failure == .unreadable && service.isMonitoring,
                         "an answer that is not a status is named, and the reading goes on")
            world.documents = [idle]
            spin(1.4)
            suite.expect(service.failure == nil, "an answer that arrives again clears the word about the one that did not")

            // The interval the ruler is set to is kept, and the running
            // session takes it up.
            service.setInterval(7)
            suite.expect(service.intervalSeconds == 7 && world.kept == [7],
                         "the interval is kept, and the running session reads at it")
            world.interval = 4
            service.syncWithPreferences()
            suite.expect(service.intervalSeconds == 4 && service.isMonitoring,
                         "the interval moved under the session is taken up, and the session is not ended")

            // The key goes with the reading, and nothing else is asked.
            world.key = "sk-test"
            spin(1.4)
            suite.expect(world.keys.contains("sk-test"),
                         "the reading carries the key, and it is the only thing the reading sends")

            // The way out.
            service.stop()
            suite.expect(!service.isMonitoring && service.phase == .idle,
                         "the way out ends the reading and the task")
            let stopped = service.reads
            spin(2.4)
            suite.expect(service.reads == stopped, "after the way out nothing is asked any more")
            suite.expect(service.snapshot != nil && service.showsDashboard,
                         "the card keeps what was last read, as the page has always done")

            // Start again: the reading begins afresh.
            service.start()
            spin(1.4)
            suite.expect(service.isMonitoring && service.reads > stopped, "Start reads again")
            service.stop()

            // A section switched off is a reason to stop, and the page's own
            // rule about it is the settings'.
            world.enabled = false
            service.start()
            suite.expect(!service.isMonitoring, "a section switched off cannot begin a reading")
            world.enabled = true
            service.start()
            spin(1.2)
            service.syncWithPreferences()
            suite.expect(service.isMonitoring, "settings that are simply still there do not end a reading")
            world.address = nil
            service.syncWithPreferences()
            suite.expect(!service.isMonitoring, "an address taken away ends the reading")
            service.stop()
        }
    }

    /// The world a polling session is asked to run in: the documents it
    /// answers with, the clock it is told, and the list its notices land in.
    final class PollingWorld {
        var documents: [String]
        var code = 200
        var address: URL? = URL(string: "http://127.0.0.1:8010/status")
        var enabled = true
        var interval = 1
        var key = ""
        var now: Date
        var keys: [String] = []
        var kept: [Int] = []
        var notices: [NotchSplashService.Notice] = []

        init(start: Date, documents: [String]) {
            self.now = start
            self.documents = documents
        }

        /// The next answer: the last document the test left, so a state holds
        /// across the readings between two of the test's own moves.
        func nextDocument() -> String { documents.last ?? "{}" }
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

        // The dashboard's own beginning: this Mac's Splash server, the port it
        // answers on, and the key it hands out. A person switches the section
        // on and the dashboard reads, with nothing typed and no key shown.
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchSplashHost] as? String
                         == NotchSplashEndpoint.localHost
                         && Defaults.registeredDefaults[DefaultsKey.notchSplashPort] as? Int
                             == NotchSplashEndpoint.defaultPort
                         && Defaults.registeredDefaults[DefaultsKey.notchSplashAPIKey] as? String
                             == NotchSplashEndpoint.localAPIKey,
                     "the settings begin at the local Splash server, its port, and its key")
        suite.expect(NotchSplashEndpoint.localHost == "127.0.0.1"
                         && NotchSplashEndpoint.defaultPort == 8001
                         && NotchSplashEndpoint.statusURL(host: NotchSplashEndpoint.localHost,
                                                          port: NotchSplashEndpoint.defaultPort)?
                             .absoluteString == "http://127.0.0.1:8001/status",
                     "that is the local engine, on the port it answers on")

        let localName = "vorss.tests.splash.local.\(ProcessInfo.processInfo.processIdentifier)"
        let local = UserDefaults(suiteName: localName) ?? .standard
        for key in keys { local.removeObject(forKey: key) }
        local.register(defaults: [
            DefaultsKey.notchSplashHost: NotchSplashEndpoint.localHost,
            DefaultsKey.notchSplashPort: NotchSplashEndpoint.defaultPort,
            DefaultsKey.notchSplashAPIKey: NotchSplashEndpoint.localAPIKey,
            DefaultsKey.notchSplashIntervalSeconds: NotchSplashSupport.defaultInterval,
        ])
        suite.expect(NotchSplashSupport.endpoint(in: local)?.absoluteString == "http://127.0.0.1:8001/status",
                     "a dashboard switched on with nothing typed reads this Mac's Splash server")
        suite.expect(NotchSplashSupport.savedAPIKey(in: local) == NotchSplashEndpoint.localAPIKey
                         && NotchSplashSupport.hasAPIKey(in: local)
                         && !NotchSplashSupport.hasWrittenAPIKey(in: local),
                     "the key the app starts with is used, is known to be there, and is not reported as written by hand")
        local.set("sk-written", forKey: DefaultsKey.notchSplashAPIKey)
        suite.expect(NotchSplashSupport.savedAPIKey(in: local) == "sk-written"
                         && NotchSplashSupport.hasWrittenAPIKey(in: local),
                     "a key written into the settings takes the place of the one the app starts with")
        local.set("  sk-padded  ", forKey: DefaultsKey.notchSplashAPIKey)
        suite.expect(NotchSplashSupport.savedAPIKey(in: local) == "sk-padded",
                     "a key is sent as it stands, without the spaces around it")
        local.set("", forKey: DefaultsKey.notchSplashAPIKey)
        suite.expect(NotchSplashSupport.savedAPIKey(in: local) == NotchSplashEndpoint.localAPIKey
                         && !NotchSplashSupport.hasWrittenAPIKey(in: local),
                     "clearing the field leaves the key the app starts with in place")
        local.set("splash.local", forKey: DefaultsKey.notchSplashHost)
        local.set(9009, forKey: DefaultsKey.notchSplashPort)
        suite.expect(NotchSplashSupport.endpoint(in: local)?.absoluteString == "http://splash.local:9009/status",
                     "an address written by hand outlasts the default, which is what a saved setting is for")
        for key in keys { local.removeObject(forKey: key) }
    }

    static func run(_ suite: TestSuite) {
        suite.run("splash settings") { settingsChecks(suite) }
        suite.run("splash reading") { readingChecks(suite) }
        suite.run("splash metrics") { metricChecks(suite) }
        suite.run("splash text") { textChecks(suite) }
        suite.run("splash task") { taskChecks(suite) }
        suite.run("splash notices") { noticeChecks(suite) }
        suite.run("splash session") { sessionChecks(suite) }
        suite.run("splash polling") { pollingChecks(suite) }
        suite.run("splash monitoring") { monitoringChecks(suite) }
        suite.run("splash ruler") { rulerChecks(suite) }
        suite.run("splash dashboard") { dashboardChecks(suite) }
        suite.run("splash strings") { localizationChecks(suite) }
        suite.run("splash palette") { paletteChecks(suite) }
    }
}
