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
        suite.expect(NotchSplashSupport.defaultInterval == 1 && NotchSplashSupport.intervalRange == 1...10,
                     "the interval defaults to a second, the pace the charts are drawn at, between 1 and 10")
        for value in 1...10 {
            suite.expect(NotchSplashSupport.interval(value) == value, "every second from 1 to 10 is chosen as itself")
        }
        suite.expect(NotchSplashSupport.interval(nil) == 1 && NotchSplashSupport.interval(0) == 1
                         && NotchSplashSupport.interval(11) == 1 && NotchSplashSupport.interval(-3) == 1,
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

    // MARK: - What the engine measures

    /// The figures the dashboard draws are the engine's own: the batch it has in
    /// hand, the rate of its whole running, and the first token's two percentiles.
    /// The app measures no throughput of its own, so what is tested is that every
    /// figure is read at the engine's name, that a batch the engine marks invalid
    /// is no figure, and that a figure the engine does not carry is missing - not
    /// zero, not the last reading's number, not the lifetime average borrowed into
    /// the line for the present.
    static func liveMetricChecks(_ suite: TestSuite) {
        // The engine's own figures, read at the engine's names.
        let running = status("""
        {"instance": {"id": "a"},
         "metrics": {"current_decode_batch": {"valid": true, "tokens_per_second": 85.32},
                     "current_prefill_batch": {"valid": true, "tokens_per_second": 600.5},
                     "decode_tokens_per_second": 50.97, "prefill_tokens_per_second": 480,
                     "ttft_ms": {"p50": 700, "p95": 1900}}}
        """)
        suite.expectClose(running.metrics.currentDecodeBatchTokensPerSecond ?? 0, 85.32,
                          "the decode speed of the batch in hand is the engine's figure", tol: 0.0001)
        suite.expectClose(running.metrics.currentPrefillBatchTokensPerSecond ?? 0, 600.5,
                          "the prefill speed of the batch in hand is the engine's figure", tol: 0.0001)
        suite.expectClose(running.metrics.decodeTokensPerSecond ?? 0, 50.97,
                          "the decode speed over the engine's whole running is the engine's figure", tol: 0.0001)
        suite.expectClose(running.metrics.prefillTokensPerSecond ?? 0, 480,
                          "the prefill speed over the engine's whole running is the engine's figure", tol: 0.0001)
        suite.expect(running.metrics.ttftMilliseconds == 700 && running.metrics.ttftP95Milliseconds == 1_900,
                     "a p50 and a p95 in one group are read as the two they are")

        // The current line is the batch in hand and nothing else. A batch the
        // engine marks not valid is no measurement of the present, and the
        // average over the running is not borrowed to fill the line in.
        let invalid = status("""
        {"instance": {"id": "a"},
         "metrics": {"current_decode_batch": {"valid": false, "tokens_per_second": 85.32},
                     "decode_tokens_per_second": 50.97}}
        """)
        suite.expect(invalid.metrics.currentDecodeBatchTokensPerSecond == nil
                         && invalid.metrics.decodeTokensPerSecond == 50.97,
                     "a batch the engine marks invalid is no current figure, and the average keeps its own line")
        let batchless = status("""
        {"instance": {"id": "a"}, "metrics": {"decode_tokens_per_second": 50.97}}
        """)
        suite.expect(batchless.metrics.currentDecodeBatchTokensPerSecond == nil
                         && batchless.metrics.currentPrefillBatchTokensPerSecond == nil,
                     "a server that carries no batch block has no current figure, and the card leaves the line empty")
        for json in ["{\"metrics\":{\"current_decode_batch\":{\"valid\":true,\"tokens_per_second\":0}}}",
                     "{\"metrics\":{\"current_decode_batch\":{\"valid\":true,\"tokens_per_second\":-2}}}",
                     "{\"metrics\":{\"current_decode_batch\":{\"valid\":true}}}",
                     "{\"metrics\":{\"current_decode_batch\":null}}",
                     "{\"metrics\":{\"current_decode_batch\":{\"valid\":true,\"tokens_per_second\":null}}}",
                     "{\"metrics\":{\"current_decode_batch\":{\"valid\":true,\"tokens_per_second\":\"not a number\"}}}",
                     "{\"metrics\":{\"current_decode_batch\":{\"valid\":true,\"tokens_per_second\":\"nan\"}}}"] {
            suite.expect(status(json).metrics.currentDecodeBatchTokensPerSecond == nil,
                         "a batch rate that is absent, not a number, or not a positive one is no figure")
        }
        // A rate written as a number in a string is the number the engine wrote,
        // and the JSON node reads it as one; a rate written as a word is not.
        suite.expect(status("{\"metrics\":{\"current_decode_batch\":{\"valid\":true,\"tokens_per_second\":\"85\"}}}")
                         .metrics.currentDecodeBatchTokensPerSecond == 85,
                     "a server that writes its rate quoted is read as the number it says")
        // A server that carries none of these figures answers with nothing.
        let bare = status("{\"instance\": {\"id\": \"a\"}, \"metrics\": {}}")
        suite.expect(bare.metrics.currentDecodeBatchTokensPerSecond == nil
                         && bare.metrics.currentPrefillBatchTokensPerSecond == nil
                         && bare.metrics.decodeTokensPerSecond == nil
                         && bare.metrics.prefillTokensPerSecond == nil
                         && bare.metrics.ttftMilliseconds == nil
                         && bare.metrics.ttftP95Milliseconds == nil,
                     "figures the server does not carry are missing, and not zero")
        suite.expect(NotchSplashLiveMetrics.current(bare.metrics, present: false) == NotchSplashLiveMetrics.empty
                         && NotchSplashLiveMetrics.current(bare.metrics, present: true) == .empty,
                     "a reading with no figures leaves the card's current figures empty, at rest or at work, "
                     + "and keeps nothing of the last")

        // The strip's number is the batch in hand and nothing else. The engine's
        // average over its whole running is the card's second figure, and is never
        // taken in the batch's place on the island: it is a figure of what the
        // engine has done, and an engine at rest keeps both of them forever.
        suite.expect(NotchSplashLiveMetrics.stripDecodeSpeed(current: 53.9) == 53.9,
                     "the strip writes the batch in hand while the engine has one")
        suite.expect(NotchSplashLiveMetrics.stripDecodeSpeed(current: nil) == nil,
                     "with no batch in hand the strip writes nothing, whatever the engine's average over its running")
        suite.expect(NotchSplashLiveMetrics.stripDecodeSpeed(current: 0) == nil
                         && NotchSplashLiveMetrics.stripDecodeSpeed(current: nil) == nil,
                     "an engine that has decoded nothing, and a server that answers no rate, leave the strip empty")

        // The pair of a card, in the order the card writes it: the batch in hand
        // first and the average second for the two throughputs, the p50 first and
        // the p95 second for the first token's time.
        let us = Locale(identifier: "en_US")
        suite.expect(NotchSplashSupport.speedPairText(85.32, 50.97, locale: us) == "85.32 / 50.97",
                     "two throughputs are one pair, to two decimals under a hundred")
        suite.expect(NotchSplashSupport.speedPairText(120.4, 5000, locale: us) == "120.4 / 5,000",
                     "a pair keeps each figure's own writing: a hundred and above takes one decimal, a thousand none")
        suite.expect(NotchSplashSupport.speedPairText(nil, 50.97, locale: us)
                         == "\(NotchSplashSupport.placeholder) / 50.97",
                     "a figure the engine has not given keeps its place empty, and the pair is not shown as one number")
        suite.expect(NotchSplashSupport.speedPairText(nil, nil, locale: us) == nil,
                     "a pair of nothing is no text at all")
        suite.expect(NotchSplashSupport.ttftPairText(1.3, 2.1, locale: us) == "1.3 / 2.1",
                     "the first token's time is written p50 first and p95 second")
        suite.expect(NotchSplashSupport.ttftPairText(nil, 2.1, locale: us)
                         == "\(NotchSplashSupport.placeholder) / 2.1",
                     "the pair keeps the order of the percentiles when one of them is missing")
        // The strip is a glance: the whole number stands against the unit with no
        // space between them, and the unit is the page's own, in the reader's
        // language. Nowhere on the island is the older, longer unit written.
        suite.expect(NotchSplashSupport.stripSpeedText(53.9, language: .enUS) == "53t/s"
                         && NotchSplashSupport.stripSpeedText(53.4, language: .ru) == "53т/с"
                         && NotchSplashSupport.stripSpeedText(0, language: .enUS) == "0t/s"
                         && NotchSplashSupport.stripSpeedText(nil) == nil
                         && NotchSplashSupport.stripSpeedText(-1) == nil
                         && NotchSplashSupport.stripSpeedText(.nan) == nil,
                     "the strip writes a whole number against the page's unit with no space, in the reader's "
                     + "language, and nothing for what is not a rate")
    }

    /// The three cards that measure, and the fourth that does not.
    static func pairChecks(_ suite: TestSuite) {
        // The measure of a card is the measure of the card it replaces: a pair
        // of figures in a card that is the same size as its neighbours, with the
        // same chart and the same ground, is only a pair and not a redesign.
        suite.expect(NotchSplashLayout.metricCardHeight > NotchSplashLayout.pairValueSize
                         + NotchSplashLayout.sparklineHeight + NotchSplashLayout.labelSize,
                     "a card of two figures is tall enough for its name, its pair, and its two lines")
        suite.expect(NotchSplashLayout.pairValueSize < NotchSplashLayout.valueSize,
                     "a pair is set under a single figure, so two figures fit the card's width")
        suite.expect(NotchSplashLayout.metricCardHeight == 86 && NotchSplashLayout.metricSpacing == 8
                         && NotchSplashLayout.padding == 10 && NotchSplashLayout.sparklineHeight == 22,
                     "the card's measure is the reference's, unchanged: four cards, one row, one gap")
        // The two lines of a measuring card are the reference's two colours: the
        // current figure purple, the engine's own average blue, and the cache's
        // rate untouched in its green.
        suite.expect(NotchSplashPalette.purple != NotchSplashPalette.blue
                         && NotchSplashPalette.purple != NotchSplashPalette.orange,
                     "the two lines of a measuring card are two colours, and not the colour of the card that went before")
    }

    /// The decode speed as an activity of the island: a strip with a page of
    /// its own, a mark, and a reading the strip writes. The order of the
    /// activities on the strip is the island's own rule and is tested with the
    /// other activities; what belongs here is that the speed is an activity the
    /// island answers, not a picture drawn over one.
    static func priorityChecks(_ suite: TestSuite) {
        suite.expect(NotchCompactActivity.splash.title(.enUS).isEmpty == false
                         && NotchCompactActivity.splash.module == .splash
                         && NotchCompactActivity.splash.symbol.isEmpty == false,
                     "the decode speed is a strip with a page of its own, like every other activity")
        suite.expect(NotchCompactActivity.splash.module == .splash
                         && NotchModule.splash.symbol.isEmpty == false,
                     "the speed is one of the activities and one of the pages, so the island's answers reach it")
    }

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
        suite.expect(NotchSplashSupport.ttftParts(NotchSplashSupport.ttftSeconds(milliseconds: 800))?.value == "0.8"
                         && NotchSplashSupport.ttftParts(NotchSplashSupport.ttftSeconds(milliseconds: 800))?.unit == "s",
                     "a first token's time splits into its figure and its unit, for a card to set them apart")
        for seconds in [0.8, 1.2, 12.0] {
            let parts = NotchSplashSupport.ttftParts(seconds)!
            suite.expect(parts.value + " " + parts.unit == NotchSplashSupport.ttftText(seconds),
                         "the two parts joined are the words the sentence writes")
        }
        suite.expect(NotchSplashSupport.ttftParts(nil) == nil && NotchSplashSupport.ttftParts(.nan) == nil,
                     "a time the server did not report, or reported as nothing, has no figure and no unit")
        suite.expect(NotchSplashSupport.locale == MetricFormat.locale,
                     "the dashboard's figures are written in the region the app's other numbers use")
        suite.expect(NotchSplashSupport.intervalText(2) == "2s", "the interval is written short")
    }

    // MARK: - The measured past

    /// The history: what a reading leaves behind, how a day's tokens are made
    /// from a difference, how long it is kept, how thin it is kept, and what
    /// the file says when it is read back.
    static func historyChecks(_ suite: TestSuite) {
        let calendar = Calendar(identifier: .gregorian)
        let base = Date(timeIntervalSince1970: 1_767_225_600)   // a whole day's start, in UTC
        func reading(decode: Double, prefill: Double, ttftMs: Double, hits: Int, requests: Int,
                     input: Int, output: Int, id: String = "a",
                     active: Bool = false) -> NotchSplashStatus {
            let document = #"{"instance": {"id": "\#(id)"}, "requests": {"completed": 1, "failed": 0, "cancelled": 0}, "active_requests": \#(active ? #"[{"id": "r1"}]"# : "[]"), "metrics": {"decode_tokens_per_second": \#(decode), "prefill_tokens_per_second": \#(prefill), "ttft_ms": {"p50": \#(ttftMs)}, "prefill_input_tokens": \#(input), "decode_output_tokens": \#(output)}, "cache": {"hits": \#(hits), "requests": \#(requests)}}"#
            return NotchSplashStatus(document: SplashJSON.document(Data(document.utf8))!)
        }

        suite.run("splash history begins empty") {
            let history = NotchSplashHistory.empty
            suite.expect(!history.hasSamples && !history.hasTokens,
                         "nothing has been measured, and the cards say so")
            suite.expect(history.samples.isEmpty && history.days.isEmpty, "no readings, no days")
            suite.expect(history.series(endingAt: base).isEmpty,
                         "a chart asked for a window with nothing in it is given nothing, and draws no line")
            suite.expect(history.trend(calendar: calendar, now: base, count: 30).allSatisfy { !$0.hasActivity },
                         "the trend of a month never measured is thirty days of nothing")
            suite.expect(history.total(of: history.trend(calendar: calendar, now: base, count: 30)) == 0,
                         "and the month's total is nothing, not a number out of the engine's life")
        }

        suite.run("splash history records what a reading measured") {
            var history = NotchSplashHistory()
            history.record(status: reading(decode: 91.234, prefill: 612.094, ttftMs: 800, hits: 48_700,
                                           requests: 51_300, input: 10_500_000, output: 284_000),
                           instanceKey: "id:a", at: base, calendar: calendar)
            suite.expect(history.samples.count == 1, "one reading is one sample")
            let sample = history.samples[0]
            suite.expect(sample.decode == 91.23 && sample.prefill == 612.1 && sample.ttftSeconds == 0.8
                             && sample.cachePercent != nil,
                         "the sample carries the four figures, at the size a chart can show")
            suite.expect(history.trend(calendar: calendar, now: base, count: 30).last?.total == 0,
                         "the first reading of an engine adds no tokens: there is nothing to take a difference from")
            history.record(status: reading(decode: 70, prefill: 601, ttftMs: 900, hits: 48_800,
                                           requests: 51_400, input: 10_500_300, output: 284_120),
                           instanceKey: "id:a", at: base.addingTimeInterval(2), calendar: calendar)
            let today = history.trend(calendar: calendar, now: base, count: 30).last
            suite.expect(today?.input == 300 && today?.output == 120,
                         "a day's tokens are the difference of the counters, and not the total the engine has reached")
            suite.expect(history.samples.count == 2, "both readings are kept")
        }

        suite.run("splash charts carry the engine's two lines over ten minutes") {
            // A reading with both of a card's figures: the batch in hand, and the
            // average over the engine's running, and both of the first token's
            // percentiles.
            func dual(current: Double?, average: Double?, currentPrefill: Double?, averagePrefill: Double?,
                      p50: Double?, p95: Double?, id: String = "a", valid: Bool = true, cache: Bool = true) -> NotchSplashStatus {
                func number(_ value: Double?) -> String { value.map { String($0) } ?? "null" }
                let document = """
                {"instance": {"id": "\(id)"},
                 "requests": {"completed": 1, "failed": 0, "cancelled": 0}, "active_requests": [],
                 "metrics": {
                   "current_decode_batch": {"valid": \(valid), "tokens_per_second": \(number(current))},
                   "current_prefill_batch": {"valid": \(valid), "tokens_per_second": \(number(currentPrefill))},
                   "decode_tokens_per_second": \(number(average)),
                   "prefill_tokens_per_second": \(number(averagePrefill)),
                   "ttft_ms": {"p50": \(number(p50)), "p95": \(number(p95))}}\(cache ? ", \"cache\": {\"hits\": 48, \"requests\": 50}" : "")}
                """
                return NotchSplashStatus(document: SplashJSON.document(Data(document.utf8))!)
            }
            var history = NotchSplashHistory()
            history.record(status: dual(current: 85.32, average: 50.97, currentPrefill: 600, averagePrefill: 480,
                                        p50: 700, p95: 1900),
                           instanceKey: "id:a", at: base, calendar: calendar)
            let kept = history.samples[0]
            suite.expect(kept.decodeCurrent == 85.32 && kept.decode == 50.97
                             && kept.prefillCurrent == 600 && kept.prefill == 480
                             && kept.ttftSeconds == 0.7 && kept.ttftP95Seconds == 1.9
                             && kept.cachePercent == 96,
                         "one reading carries both of each card's lines, at the size a chart can show")
            // Ten minutes of history, and no further: the chart's window is the
            // ten minutes the cards show, and a reading older than it is not drawn.
            suite.expect(NotchSplashSupport.chartWindowSeconds == 600,
                         "the window the cards ask for is ten minutes")
            suite.expect(history.series(endingAt: base.addingTimeInterval(599)).count == 1,
                         "a reading nine minutes and fifty-nine seconds old is still drawn")
            suite.expect(history.series(endingAt: base.addingTimeInterval(601)).isEmpty,
                         "a reading ten minutes and one second old has left the cards' window")
            suite.expect(history.series(endingAt: base.addingTimeInterval(300)).count
                             == history.series(window: 600, endingAt: base.addingTimeInterval(300)).count,
                         "the cards ask for the window by default, and the default is the ten minutes")
            // Each line is read from its own field: the current line from the
            // batch, the average line from the engine's running, and neither line
            // borrows from the other.
            suite.expect(history.values({ $0.decodeCurrent }, endingAt: base) == [85.32]
                             && history.values({ $0.decode }, endingAt: base) == [50.97],
                         "the decode card's two lines read the two figures the engine gave")
            suite.expect(history.values({ $0.ttftP95Seconds }, endingAt: base) == [1.9]
                             && history.values({ $0.ttftSeconds }, endingAt: base) == [0.7],
                         "the first token's card draws the p95 as the upper line and the p50 as the lower")
            // A reading whose batch the engine invalidates keeps the average's
            // point and draws no current point: the line stops, and does not
            // continue on the strength of the figure it last had.
            var stopped = NotchSplashHistory()
            stopped.record(status: dual(current: 85.32, average: 50.97, currentPrefill: 600, averagePrefill: 480,
                                        p50: 700, p95: 1900),
                           instanceKey: "id:a", at: base, calendar: calendar)
            stopped.record(status: dual(current: nil, average: 50.97, currentPrefill: nil, averagePrefill: 480,
                                        p50: 700, p95: 1900, valid: false),
                           instanceKey: "id:a", at: base.addingTimeInterval(2), calendar: calendar)
            suite.expect(stopped.values({ $0.decodeCurrent }, endingAt: base.addingTimeInterval(2)) == [85.32]
                             && stopped.values({ $0.decode }, endingAt: base.addingTimeInterval(2)).count == 2,
                         "an invalidated batch draws no current point, and the average's line goes on")
            // A reading with no figures at all - no batch, no average, no
            // percentile, no counter - is no point on any line.
            var silent = NotchSplashHistory()
            silent.record(status: dual(current: nil, average: nil, currentPrefill: nil, averagePrefill: nil,
                                       p50: nil, p95: nil, cache: false),
                          instanceKey: "id:a", at: base, calendar: calendar)
            suite.expect(silent.samples.isEmpty
                             && silent.values({ $0.decode }, endingAt: base).isEmpty
                             && silent.values({ $0.cachePercent }, endingAt: base).isEmpty,
                         "a reading that measured nothing adds no point to any line, and invents none")
        }

        suite.run("splash history is not fooled by a reset, a restart, or a counter that went down") {
            var history = NotchSplashHistory()
            history.record(status: reading(decode: 70, prefill: 601, ttftMs: 900, hits: 1, requests: 2,
                                           input: 5_000, output: 500),
                           instanceKey: "id:a", at: base, calendar: calendar)
            history.record(status: reading(decode: 70, prefill: 601, ttftMs: 900, hits: 1, requests: 2,
                                           input: 6_000, output: 600),
                           instanceKey: "id:a", at: base.addingTimeInterval(2), calendar: calendar)
            let grown = history.trend(calendar: calendar, now: base, count: 30).last
            suite.expect(grown?.input == 1_000 && grown?.output == 100, "the first difference is counted")
            // A server that restarted: its counters begin again, and the
            // tokens of the time between say nothing about today.
            history.record(status: reading(decode: 70, prefill: 601, ttftMs: 900, hits: 1, requests: 2,
                                           input: 10, output: 5, id: "b"),
                           instanceKey: "id:b", at: base.addingTimeInterval(4), calendar: calendar)
            suite.expect(history.trend(calendar: calendar, now: base, count: 30).last == grown,
                         "a new engine adds nothing to the day")
            // The same engine, and counters that went down: a reset, and the
            // difference is nothing, never a negative taken from the day.
            history.record(status: reading(decode: 70, prefill: 601, ttftMs: 900, hits: 1, requests: 2,
                                           input: 3, output: 1, id: "b"),
                           instanceKey: "id:b", at: base.addingTimeInterval(6), calendar: calendar)
            suite.expect(history.trend(calendar: calendar, now: base, count: 30).last == grown,
                         "a counter that went down adds nothing, and takes nothing away from the day")
            history.record(status: reading(decode: 70, prefill: 601, ttftMs: 900, hits: 1, requests: 2,
                                           input: 900, output: 90, id: "b"),
                           instanceKey: "id:b", at: base.addingTimeInterval(8), calendar: calendar)
            let after = history.trend(calendar: calendar, now: base, count: 30).last
            suite.expect(after?.input == 1_897 && after?.output == 189,
                         "and the same engine's next reading is counted from where its counters stand now")
        }

        suite.run("splash history keeps thirty days and thins what it keeps") {
            var history = NotchSplashHistory()
            let longAgo = base.addingTimeInterval(-45 * 24 * 60 * 60)
            history.record(status: reading(decode: 70, prefill: 601, ttftMs: 900, hits: 1, requests: 2,
                                           input: 100, output: 10),
                           instanceKey: "id:a", at: longAgo, calendar: calendar)
            history.record(status: reading(decode: 70, prefill: 601, ttftMs: 900, hits: 1, requests: 2,
                                           input: 200, output: 20),
                           instanceKey: "id:a", at: longAgo.addingTimeInterval(2), calendar: calendar)
            history.record(status: reading(decode: 70, prefill: 601, ttftMs: 900, hits: 2, requests: 3,
                                           input: 300, output: 30),
                           instanceKey: "id:a", at: base, calendar: calendar)
            suite.expect(history.days.count == 2, "a day 45 days ago, and today")
            suite.expect(history.clean(now: base, calendar: calendar),
                         "pruning a month of readings has something to do")
            suite.expect(history.days.count == 1 && history.days.first?.start == calendar.startOfDay(for: base),
                         "the month's keeping drops the day outside it, and the file is written again")
            suite.expect(history.samples.count == 1,
                         "and the readings outside the keeping are dropped, while today's stays")
            // Thinness: a day of readings a second apart, kept whole for the
            // last half hour, a minute apiece for the day, ten minutes
            // apiece beyond that.
            var day = NotchSplashHistory()
            for second in 0..<3600 {
                day.record(status: reading(decode: 90, prefill: 600, ttftMs: 900, hits: 1, requests: 2,
                                           input: 1_000 + second, output: 100 + second),
                           instanceKey: "id:a", at: base.addingTimeInterval(TimeInterval(second)),
                           calendar: calendar)
            }
            suite.expect(day.samples.count == 3_600, "an hour of readings a second apart, whole")
            day.compact(now: base.addingTimeInterval(3600))
            let kept = day.samples
            suite.expect(kept.count < 3_600 && kept.count > 1_800,
                         "a day of readings is thinned, and the last half hour of it is kept whole")
            suite.expect((kept.last?.at.timeIntervalSince1970 ?? 0)
                             >= base.addingTimeInterval(3_540).timeIntervalSince1970,
                         "the newest readings are the last ones")
            suite.expect((kept.first?.at.timeIntervalSince1970 ?? .infinity)
                             < base.addingTimeInterval(60).timeIntervalSince1970,
                         "and the oldest of them stand for the oldest of the readings")
            let thinned = kept.filter {
                $0.at.timeIntervalSince1970 < base.addingTimeInterval(1_800).timeIntervalSince1970
            }
            suite.expect(thinned.count == 30,
                         "the hour's oldest half hour is kept to a reading a minute, and not a reading a second")
            let pitches = Set(zip(thinned, thinned.dropFirst()).map { Int($1.at.timeIntervalSince1970
                - $0.at.timeIntervalSince1970) })
            suite.expect(pitches == [60], "and each thinned reading stands for a minute, at the minute's own start")
        }

        suite.run("splash history is written, read back, and not invented") {
            let path = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("vorss-tests-splash-store-\(ProcessInfo.processInfo.processIdentifier).json")
            try? FileManager.default.removeItem(at: path)
            let store = NotchSplashHistoryStore(url: path)
            suite.expect(store.history.samples.isEmpty,
                         "a file that is not there is a past that was not kept, and no reading is invented")
            store.record(status: reading(decode: 91.2, prefill: 612, ttftMs: 800, hits: 48_700,
                                         requests: 51_300, input: 1_000, output: 100),
                         instanceKey: "id:a", at: base, calendar: calendar)
            store.record(status: reading(decode: 91.2, prefill: 612, ttftMs: 800, hits: 48_700,
                                         requests: 51_300, input: 1_500, output: 180),
                         instanceKey: "id:a", at: base.addingTimeInterval(2), calendar: calendar)
            store.flush(at: base)
            suite.expect(FileManager.default.fileExists(atPath: path.path), "the past is written")
            let read = NotchSplashHistoryStore(url: path)
            suite.expect(read.load(now: base), "and read back")
            suite.expect(read.history.samples.count == 2, "every reading is there")
            suite.expect(read.history.trend(calendar: calendar, now: base, count: 30).last?.input == 500
                             && read.history.trend(calendar: calendar, now: base, count: 30).last?.output == 80,
                         "and the day's tokens are there, in the day they were earned in")
            suite.expect(read.history.counters?.instanceKey == "id:a",
                         "the counters' baseline comes back too, so the next reading is a difference")
            // A file that is not a document: measuring begins again, and the
            // cards say they have no past.
            try? "not a document at all".write(to: path, atomically: true, encoding: .utf8)
            let broken = NotchSplashHistoryStore(url: path)
            suite.expect(!broken.load(now: base) && broken.history.samples.isEmpty,
                         "a file that cannot be read is a past that has not been kept, said as it is")
            try? FileManager.default.removeItem(at: path)
        }
    }

    // MARK: - The task and its clock

    static func taskChecks(_ suite: TestSuite) {
        // The window is shortened so a whole task, with its pauses, fits in a
        // minute of the test's clock. The app's window is the long one, and it
        // is checked below at its own value.
        func task() -> NotchSplashTaskTracker { NotchSplashTaskTracker(quiescence: 30, quietReadingsNeeded: 2) }
        suite.expect(NotchSplashSupport.taskIdleSeconds == 10 * 60 && NotchSplashSupport.taskIdleReadings == 1,
                     "the dashboard's idle confirmation is one unbroken ten-minute quiet, and it is the dashboard's "
                     + "own number: Splash's weights.idle_release_seconds, which puts the engine's weights to sleep, is "
                     + "a separate mechanism asked of the server, and this setting does not move it")
        suite.expect(NotchSplashSupport.chartWindowSeconds == 10 * 60,
                     "the three measuring charts look back over ten minutes, and no further")

        let busy = #"{"instance": {"id": "a"}, "requests": {"completed": 3}, "active_requests": [{"id": "r1"}]}"#
        let turn = #"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": []}"#
        let nextTurn = #"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": [{"id": "r2"}]}"#
        let lastTurn = #"{"instance": {"id": "a"}, "requests": {"completed": 5}, "active_requests": []}"#

        // What a run is doing now is answered by the fields that name work in
        // hand - a request, a queue, a schedule, a front end holding a prompt, a
        // live connection, a model being loaded. The counters are cumulative:
        // they are how a request shorter than the interval is noticed at all, and
        // they open a run, but they cannot keep one open. A busy neighbour moving
        // them, measured against the reading before, would hold a finished task
        // open forever - and the card's clock would run on a machine at rest.
        let frontEnd = #"{"instance": {"id": "a"}, "requests": {"completed": 3}, "frontend": {"active": 1}, "active_requests": []}"#
        let neighbour = #"{"instance": {"id": "a"}, "requests": {"completed": 99}, "active_requests": []}"#
        let stale = #"{"instance": {"id": "a"}, "requests": {"completed": 99}, "transport": {"status_stale": true}, "active_requests": []}"#
        var live = task()
        suite.expect(live.observe(snapshot(frontEnd), at: start) == .started(id: NotchSplashTaskTracker.unnumbered, at: start),
                     "a prompt the front end holds is work the engine has, and it opens a task")
        suite.expect(live.observe(snapshot(frontEnd), at: start.addingTimeInterval(5)) == nil
                         && live.isRunning && live.elapsed(at: start.addingTimeInterval(5)) == 5,
                     "a front-end count is a live field, and the clock runs while it stands")
        suite.expect(live.observe(snapshot(neighbour), at: start.addingTimeInterval(10)) == nil
                         && live.isRunning && live.elapsed(at: start.addingTimeInterval(40)) == 10,
                     "a neighbour's counters, with nothing in hand, open the confirmation window and rest the clock: "
                         + "cumulative counts are not a task at work")
        suite.expect(live.observe(snapshot(stale), at: start.addingTimeInterval(20)) == nil
                         && live.elapsed(at: start.addingTimeInterval(25)) == 25,
                     "a server that reports its own state stale is not idle: the window does not close on a reading "
                         + "that cannot say, and the clock lifts off its mark")
        suite.expect(live.observe(snapshot(neighbour), at: start.addingTimeInterval(30)) == nil
                         && live.elapsed(at: start.addingTimeInterval(300)) == 30,
                     "the window is measured from the reading that found nothing in hand, and the clock rests there")

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
        suite.expect(tracker.elapsed(at: start.addingTimeInterval(21)) == 10,
                     "the clock rests at the last work while the confirmation window runs: a quiet reading fixes it, "
                     + "and the window's own minutes are never added to the task's length")
        suite.expect(tracker.isRunning,
                     "the run is open while its window runs, with the clock at rest: the two timers answer separately")
        suite.expect(tracker.observe(snapshot(nextTurn), at: start.addingTimeInterval(22)) == nil,
                     "the next request of the same task is not a new task")
        suite.expect(tracker.isRunning && tracker.trackedID == "r1"
                         && tracker.elapsed(at: start.addingTimeInterval(25)) == 25,
                     "the task goes on as one task, its clock never reset by a turn")
        // The last turn's answer moves the counters and leaves nothing in hand.
        // That is the engine at rest, not the engine working: the confirmation
        // window opens at that reading and the task's clock rests at 26 seconds,
        // while the run stays open for the window's length.
        suite.expect(tracker.observe(snapshot(lastTurn), at: start.addingTimeInterval(26)) == nil
                         && tracker.isRunning
                         && tracker.elapsed(at: start.addingTimeInterval(26)) == 26,
                     "a turn answered with nothing in hand opens the confirmation window and rests the clock; the run is not over")
        suite.expect(tracker.observe(snapshot(lastTurn), at: start.addingTimeInterval(50)) == nil
                         && tracker.elapsed(at: start.addingTimeInterval(50)) == 26,
                     "24 quiet seconds is inside the window: nothing is told, and the clock stays where the work ended")
        suite.expect(tracker.observe(snapshot(lastTurn), at: start.addingTimeInterval(60))
                         == .finished(id: "r1", outcome: .completed, startedAt: start,
                                      at: start.addingTimeInterval(26), elapsed: 26),
                     "a quiet that outlasts the window ends the task, timed to where the quiet began")
        suite.expect(tracker.elapsed(at: start.addingTimeInterval(600)) == 26,
                     "a finished task's clock stays at the length it froze at, and the window's minutes are not in it")
        suite.expect(tracker.observe(snapshot(lastTurn), at: start.addingTimeInterval(300)) == nil,
                     "an idle reading after a completion says nothing")
        suite.expect(tracker.phase == .finished(id: "r1", outcome: .completed,
                                                startedAt: start, at: start.addingTimeInterval(26), elapsed: 26),
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
        _ = cleared.observe(snapshot(turn), at: start.addingTimeInterval(95))
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
        suite.expect(positional.observe(snapshot(turn), at: start.addingTimeInterval(6)) == nil
                         && positional.isRunning,
                     "a turn answered with nothing in hand opens the confirmation window, and the positional task is not over")
        suite.expect(positional.observe(snapshot(turn), at: start.addingTimeInterval(20)) == nil
                         && positional.elapsed(at: start.addingTimeInterval(20)) == 6,
                     "14 quiet seconds is inside the window: nothing is told, and the clock rests at six seconds")
        suite.expect(positional.observe(snapshot(turn), at: start.addingTimeInterval(40))
                         == .finished(id: "position.0", outcome: .completed,
                                      startedAt: start, at: start.addingTimeInterval(6), elapsed: 6),
                     "the first positional task is told on its counters, its clock at the length of the work")
        suite.expect(positional.observe(snapshot(positionalBusy), at: start.addingTimeInterval(100))
                         == .started(id: "position.0", at: start.addingTimeInterval(100)),
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
                         == .finished(id: "r1", outcome: .lost, startedAt: start,
                                      at: start.addingTimeInterval(4), elapsed: 4),
                     "work gone with every counter where it was is lost, never completed")

        let restarted = #"{"instance": {"id": "b"}, "requests": {"completed": 9}, "active_requests": []}"#
        var restart = task()
        suite.expect(restart.observe(snapshot(busy), at: start) != nil, "the task begins")
        suite.expect(restart.observe(snapshot(restarted), at: start.addingTimeInterval(3)) == nil
                         && restart.isRunning,
                     "a new instance mid-task is not an ending yet: the confirmation window opens and the run stays open")
        suite.expect(restart.observe(snapshot(restarted), at: start.addingTimeInterval(20)) == nil
                         && restart.elapsed(at: start.addingTimeInterval(20)) == 3,
                     "17 quiet seconds inside the window says nothing, and the clock rests at three seconds")
        suite.expect(restart.observe(snapshot(restarted), at: start.addingTimeInterval(35))
                         == .finished(id: "r1", outcome: .lost, startedAt: start,
                                      at: start.addingTimeInterval(3), elapsed: 3),
                     "a new instance is a lost task, told when the quiet outlasts the window, its clock at the length of the work")

        var mute = task()
        let muteBusy = #"{"instance": {"id": "a"}, "active_requests": [{"id": "r1"}]}"#
        let muteQuiet = #"{"instance": {"id": "a"}, "active_requests": []}"#
        suite.expect(mute.observe(snapshot(muteBusy), at: start) != nil, "the task begins with no counters in sight")
        suite.expect(mute.observe(snapshot(muteQuiet), at: start.addingTimeInterval(3)) == nil,
                     "no counters and one quiet reading say nothing")
        suite.expect(mute.observe(snapshot(muteQuiet), at: start.addingTimeInterval(34))
                         == .finished(id: "r1", outcome: .lost, startedAt: start,
                                      at: start.addingTimeInterval(3), elapsed: 3),
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
                         == .finished(id: "r1", outcome: .failed, startedAt: start,
                                      at: start.addingTimeInterval(3), elapsed: 3),
                     "a failed count that grew is a failure, not a completion")
        var cancelled = task()
        suite.expect(cancelled.observe(snapshot(busy), at: start) != nil, "the task begins")
        suite.expect(cancelled.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3, "cancelled": 2}, "active_requests": []}"#),
                                        at: start.addingTimeInterval(3)) == nil,
                     "a cancellation inside the window is not told yet")
        suite.expect(cancelled.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3, "cancelled": 2}, "active_requests": []}"#),
                                        at: start.addingTimeInterval(35))
                         == .finished(id: "r1", outcome: .cancelled, startedAt: start,
                                      at: start.addingTimeInterval(3), elapsed: 3),
                     "a cancelled count that grew is a cancellation")
        // A run in which a turn failed and a later turn answered is a task
        // that produced an answer: the completed count outranks the failed.
        var retried = task()
        _ = retried.observe(snapshot(busy), at: start)
        suite.expect(retried.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3, "failed": 1}, "active_requests": [{"id": "r2"}]}"#),
                                     at: start.addingTimeInterval(5)) == nil,
                     "a failed turn with the next turn already running is not an ending")
        suite.expect(retried.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 4, "failed": 1}, "active_requests": []}"#),
                                     at: start.addingTimeInterval(40)) == nil
                         && retried.isRunning && retried.elapsed(at: start.addingTimeInterval(40)) == 40,
                     "the retried turn answered with nothing in hand: the window opens and the clock rests at the answer's moment")
        suite.expect(retried.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 4, "failed": 1}, "active_requests": []}"#),
                                     at: start.addingTimeInterval(75))
                         == .finished(id: "r1", outcome: .completed, startedAt: start,
                                      at: start.addingTimeInterval(40), elapsed: 40),
                     "a task that answered after a failed turn is a completion, not a failure, told at the window's close")

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

        // A prompt answered between two readings. The server is read once a
        // second and the generation took a third of a second, so no reading
        // ever names an active request: its counters are all that is left of
        // it, and without the counters the whole task would be missed.
        let idleCounters = #"{"instance": {"id": "a"}, "requests": {"completed": 3, "failed": 0, "cancelled": 0}, "active_requests": []}"#
        let oneMore = #"{"instance": {"id": "a"}, "requests": {"completed": 4, "failed": 0, "cancelled": 0}, "active_requests": []}"#
        var quick = task()
        suite.expect(quick.observe(snapshot(idleCounters, at: start), at: start) == nil,
                     "a first reading, with no reading before it, opens no run")
        suite.expect(quick.observe(snapshot(idleCounters, at: start.addingTimeInterval(1)),
                                   at: start.addingTimeInterval(1)) == nil,
                     "counters that did not move are not work")
        suite.expect(quick.observe(snapshot(oneMore, at: start.addingTimeInterval(2)),
                                   at: start.addingTimeInterval(2))
                         == .started(id: NotchSplashTaskTracker.unnumbered, at: start.addingTimeInterval(2)),
                     "a request that completed between two readings is taken up as a run, by its counters")
        let quietAgain = #"{"instance": {"id": "a"}, "requests": {"completed": 4, "failed": 0, "cancelled": 0}, "active_requests": []}"#
        suite.expect(quick.observe(snapshot(quietAgain, at: start.addingTimeInterval(3)),
                                   at: start.addingTimeInterval(3)) == nil && quick.isRunning,
                     "a run begun on its counters is a run, and its first quiet reading is not its end")
        let endedQuick = quick.observe(snapshot(quietAgain, at: start.addingTimeInterval(40)),
                                       at: start.addingTimeInterval(40))
        suite.expect(endedQuick == .finished(id: NotchSplashTaskTracker.unnumbered, outcome: .lost,
                                             startedAt: start.addingTimeInterval(2),
                                             at: start.addingTimeInterval(3), elapsed: 1),
                     "a run the counters cannot speak for is lost, and is never announced as a completion")
        suite.expect(quick.elapsed(at: start.addingTimeInterval(600)) == 1,
                     "and its clock froze at the first reading that saw no work")
        // A counter that went down - a restart - is not work, and is not an
        // ending: the run it belongs to is judged lost, never completed.
        let lowerCounters = #"{"instance": {"id": "a"}, "requests": {"completed": 2, "failed": 0, "cancelled": 0}, "active_requests": []}"#
        var dropped = task()
        _ = dropped.observe(snapshot(busy), at: start)
        suite.expect(dropped.isRunning, "a request the server names begins a run")
        suite.expect(dropped.observe(snapshot(lowerCounters, at: start.addingTimeInterval(2)),
                                     at: start.addingTimeInterval(2)) == nil && dropped.isRunning,
                     "counters that went down are not work, and not a completion: a restart says nothing")

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

    // MARK: - The task's own tokens

    /// A moment of the task, on the clock the readings are taken at.
    private static func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// A reading of an engine that has been running, at the counters asked for.
    private static func engine(_ input: Int64?, _ output: Int64?, active: [String], completed: Int,
                               instance: String = "splash-1", at date: Date = start) -> NotchSplashSnapshot {
        let ids = active.map { #"{"id": "\#($0)"}"# }.joined(separator: ", ")
        let json = """
        {"instance": {"id": "\(instance)", "started_at": "2026-11-08T10:00:00Z"},
         "active_requests": [\(ids)],
         "requests": {"completed": \(completed), "failed": 0, "cancelled": 0},
         "metrics": {"prefill_input_tokens": \(input.map(String.init) ?? "null"),
                     "decode_output_tokens": \(output.map(String.init) ?? "null")}}
        """
        return snapshot(json, at: date)
    }

    static func taskTokenChecks(_ suite: TestSuite) {
        let tokens = NotchSplashTaskTracker.TaskTokens.self
        suite.expect(tokens.zero.input == 0 && tokens.zero.output == 0 && tokens.zero.isEmpty
                         && tokens.zero.total == 0,
                     "a task with no tokens counted is nothing, and says nothing")

        // A task begun on an engine that has done a hundred thousand tokens of
        // other people's work begins its own figures at nothing: the header is
        // the task, and not the engine's whole life.
        var tracker = NotchSplashTaskTracker(quiescence: 30, quietReadingsNeeded: 2)
        suite.expect(tracker.observe(engine(100_000, 60_000, active: ["r1"], completed: 57), at: start)
                         == .started(id: "r1", at: start)
                         && tracker.taskTokens.isEmpty,
                     "the figures begin at nothing, at the instant the clock does")

        // The task's own work, and only that.
        _ = tracker.observe(engine(102_000, 60_000, active: ["r1"], completed: 57), at: at(2))
        suite.expect(tracker.taskTokens.input == 2_000 && tracker.taskTokens.output == 0
                         && tracker.taskTokens.total == 2_000,
                     "the input the task moved: \(tracker.taskTokens)")
        _ = tracker.observe(engine(102_000, 61_500, active: ["r1"], completed: 57), at: at(4))
        suite.expect(tracker.taskTokens.input == 2_000 && tracker.taskTokens.output == 1_500
                         && tracker.taskTokens.total == 3_500,
                     "the output joins it, and the two are the task's total")

        // A second request of the same task is the same task: the figures keep
        // counting and do not start over.
        _ = tracker.observe(engine(104_000, 63_000, active: ["r2"], completed: 58), at: at(6))
        suite.expect(tracker.taskTokens.input == 4_000 && tracker.taskTokens.output == 3_000
                         && tracker.taskTokens.total == 7_000,
                     "an intermediate request adds to a task's figures and does not reset them: \(tracker.taskTokens)")

        // A reading with no counters adds nothing and asks for nothing.
        _ = tracker.observe(engine(nil, nil, active: ["r2"], completed: 58), at: at(8))
        suite.expect(tracker.taskTokens.input == 4_000 && tracker.taskTokens.output == 3_000,
                     "a server that reports no counters neither adds nor takes away")

        // A counter that went down in the middle of a run - an engine restarted,
        // a counter reset - is a new baseline. It never takes a run's tokens
        // back, so a figure shown is never negative and never goes down.
        _ = tracker.observe(engine(10, 4, active: ["r2"], completed: 58), at: at(10))
        suite.expect(tracker.taskTokens.input == 4_000 && tracker.taskTokens.output == 3_000,
                     "a counter that went down leaves a run's figures where they are: \(tracker.taskTokens)")
        _ = tracker.observe(engine(900, 700, active: ["r2"], completed: 58), at: at(12))
        suite.expect(tracker.taskTokens.input == 4_890 && tracker.taskTokens.output == 3_696,
                     "and the run is measured on from where the counter began again: \(tracker.taskTokens)")

        // A request completed inside the quiet is counted in the run's figures -
        // the run's tokens are read at every reading - while the engine having
        // nothing in hand opens the confirmation window.
        _ = tracker.observe(engine(1_000, 800, active: [], completed: 59), at: at(40))
        suite.expect(tracker.taskTokens == tokens.init(input: 4_990, output: 3_796) && tracker.isRunning,
                     "a reading that reports a request completed is counted, and its counters do not keep the run open: \(tracker.taskTokens)")

        // The task ends at the second quiet reading, once the window has been
        // outlasted: the figures of every reading up to that one are kept, and
        // the clock freezes at where the quiet began - not at the moment the
        // window closed.
        _ = tracker.observe(engine(9_000, 9_000, active: [], completed: 59), at: at(80))
        let frozen = tracker.taskTokens
        suite.expect(frozen == tokens.init(input: 12_990, output: 11_996),
                     "the quiet reading is measured like any other, so the run's figures include it: \(frozen)")
        suite.expect(tracker.phase == .finished(id: "r1", outcome: .completed, startedAt: start, at: at(40), elapsed: 40),
                     "the run is called over, and its figures freeze with its clock, at the length of the work: \(frozen)")
        _ = tracker.observe(engine(500_000, 400_000, active: [], completed: 59), at: at(120))
        _ = tracker.observe(engine(600_000, 500_000, active: [], completed: 59), at: at(160))
        suite.expect(tracker.taskTokens == frozen && tracker.elapsed(at: at(600)) == 40,
                     "an idle stretch after a task, however busy the engine, adds nothing to a finished task")

        // The next task on the same engine begins its figures at nothing, on an
        // engine that has done six hundred thousand.
        suite.expect(tracker.observe(engine(700_000, 600_000, active: ["r9"], completed: 60), at: at(200))
                         == .started(id: "r9", at: at(200))
                         && tracker.taskTokens.isEmpty,
                     "a new task's figures begin at nothing, whatever the engine has already done")
        _ = tracker.observe(engine(700_500, 600_250, active: ["r9"], completed: 60), at: at(202))
        suite.expect(tracker.taskTokens.input == 500 && tracker.taskTokens.output == 250,
                     "and they are measured from where the engine stood: \(tracker.taskTokens)")

        // The header's words: a task that has counted nothing reads as nothing,
        // and a task that has counted is read in the same compact figures.
        suite.expect(NotchSplashSupport.tokensText(nil) == NotchSplashSupport.placeholder
                         && NotchSplashSupport.tokensText(tokens.zero.total) == "0"
                         && NotchSplashSupport.tokensText(tracker.taskTokens.total) == "750"
                         && NotchSplashSupport.tokensText(1_234_567) == "1.23M",
                     "a figure of a task's tokens is read in the header's own words")

        // A page cleared back to its Start state loses the clock and the figures
        // together, and a monitoring session begun again starts both over.
        var over = NotchSplashTaskTracker(quiescence: 0, quietReadingsNeeded: 1)
        _ = over.observe(engine(1_000, 1_000, active: ["r1"], completed: 1), at: at(0))
        _ = over.observe(engine(2_000, 1_500, active: [], completed: 2), at: at(40))
        suite.expect(over.isFinished && over.elapsed(at: at(100)) == 40,
                     "counters alone are not a task at work: the window closes at the reading that found nothing in hand, "
                     + "and the clock rests at the length of the work, forty seconds")
        _ = over.observe(engine(2_000, 1_500, active: [], completed: 2), at: at(60))
        suite.expect(over.isFinished && over.taskTokens == tokens.init(input: 1_000, output: 500),
                     "a task that ended keeps the figures it measured")
        over.clearFinished()
        suite.expect(over.taskTokens.isEmpty && over.elapsed(at: start) == 0,
                     "the way out clears a task's figures with its clock")
        var mid = NotchSplashTaskTracker(quiescence: 30, quietReadingsNeeded: 2)
        _ = mid.observe(engine(10_000, 10_000, active: ["r1"], completed: 1), at: start)
        _ = mid.observe(engine(12_000, 11_000, active: ["r1"], completed: 1), at: at(2))
        suite.expect(mid.taskTokens.total == 3_000, "a run measured across two readings")
        mid.begin()
        suite.expect(mid.taskTokens.isEmpty && mid.trackedID == nil && mid.elapsed(at: start) == 0,
                     "a monitoring session begun again starts the clock and the figures over, together")

        // The two ledgers stay two. The thirty days are the engine's counters
        // kept day by day, and a task beginning, running, and ending takes
        // nothing from them: the same readings give the day its whole day, and
        // the header its task.
        var history = NotchSplashHistory()
        let calendar = Calendar(identifier: .gregorian)
        let day = start
        history.record(status: engine(100_000, 60_000, active: ["r1"], completed: 57, at: day).status,
                       instanceKey: "splash-1", at: day, calendar: calendar)
        history.record(status: engine(104_000, 63_000, active: ["r2"], completed: 58, at: day).status,
                       instanceKey: "splash-1", at: day, calendar: calendar)
        let trend = history.trend(calendar: calendar, now: day, count: 30)
        suite.expect(trend.last?.total == 7_000 && history.total(of: trend) == 7_000,
                     "the day keeps the counters' whole difference, and the task moved the same 7,000")
        history.record(status: engine(500_000, 400_000, active: ["r9"], completed: 60, at: day).status,
                       instanceKey: "splash-1", at: day, calendar: calendar)
        suite.expect(history.trend(calendar: calendar, now: day, count: 30).last?.total == 740_000,
                     "a new task adds to the day's tokens and starts no new ledger of its own")
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
        let second = finished.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": []}"#),
                                      at: start.addingTimeInterval(45))
        suite.expect(second == .finished(id: "r1", outcome: .completed,
                                         startedAt: start, at: start.addingTimeInterval(10), elapsed: 10)
                         && finished.elapsed(at: start.addingTimeInterval(600)) == 10
                         && !NotchSplashMonitoringPolicy.endsMonitoring(.init(idleSeconds: 600, outcome: .completed))
                         && NotchSplashSupport.showsDashboardCard(sectionVisible: true, isMonitoring: true),
                     "a completed task freezes its clock at the length of the work - the thirty-five seconds of the "
                     + "confirmation window are not in it - leaves the reading running, and keeps its card")
        suite.expect(finished.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": []}"#),
                                      at: start.addingTimeInterval(80)) == nil,
                     "an idle reading after a completion says nothing, and the clock stays where it froze")
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
        suite.expect(NotchDashboardLayout.activityHeight(.splash) == NotchSplashLayout.cardHeight(compact: true),
                     "the island measures the card as the card measures itself, at the card the section draws")
        suite.expect(NotchDashboardLayout.liveActivitiesHeight([.timer, .splash])
                         == NotchDashboardLayout.timerCardHeight + NotchSplashLayout.cardHeight(compact: true)
                            + NotchDashboardLayout.cardSpacing,
                     "two cards are their heights and the gap between them")
        // The card the page draws and the card the dashboard's section draws are
        // two measures of one view: the page has the thirty days, the glance in
        // Live Activities does not. A section measured with a chart it does not
        // draw is a page of the wrong height.
        suite.expect(NotchSplashLayout.cardHeight(compact: false) > NotchSplashLayout.cardHeight(compact: true)
                         && NotchSplashLayout.cardHeight(compact: false)
                             - NotchSplashLayout.cardHeight(compact: true)
                             == NotchSplashLayout.sectionSpacing + NotchSplashLayout.trendCardHeight,
                     "the trend's card is the page's own, and the section's card is measured without it")
        suite.expect(NotchSplashLayout.cardHeight(compact: false)
                         == NotchSplashLayout.padding * 2 + NotchSplashLayout.headerHeight
                            + NotchSplashLayout.headerSpacing + NotchSplashLayout.metricCardHeight
                            + NotchSplashLayout.sectionSpacing + NotchSplashLayout.memoryCardHeight
                            + NotchSplashLayout.sectionSpacing + NotchSplashLayout.trendCardHeight,
                     "the card is its header, the four charts, the memory, and the trend, with the gaps between: "
                     + "the measure names every part the reference draws, in the reference's order")
        suite.expect(NotchSplashLayout.cardHeight(compact: true)
                         == NotchSplashLayout.padding * 2 + NotchSplashLayout.headerHeight
                            + NotchSplashLayout.headerSpacing + NotchSplashLayout.metricCardHeight
                            + NotchSplashLayout.sectionSpacing + NotchSplashLayout.memoryCardHeight,
                     "the section's card is its header, its charts and its memory, and the gap between")
        suite.expect(NotchSplashLayout.metricCardHeight > NotchSplashLayout.valueSize
                         + NotchSplashLayout.sparklineHeight + NotchSplashLayout.labelSize,
                     "a chart's card is tall enough for its name, its figure, and its line")
        // The memory's card is one line of name and three readings, and the
        // governor's bar under them: it is a glance, and it is measured to one
        // line and a bar, which is shorter than the two rows it replaced.
        suite.expect(NotchSplashLayout.memoryCardHeight > NotchSplashLayout.memoryValueSize
                         + NotchSplashLayout.memoryLabelSize + NotchSplashLayout.utilizationBarHeight,
                     "the memory's card is tall enough for its name, its three numbers and the governor's bar")
        suite.expect(NotchSplashLayout.memoryCardHeight < 92,
                     "the memory's card is compact, and not the two-row card it was: \(NotchSplashLayout.memoryCardHeight)")
        suite.expect(NotchSplashLayout.trendCardHeight > NotchSplashLayout.trendBarsHeight,
                     "the trend's card is tall enough for its bars, its dates, and the two colours named")
        suite.expect(NotchSplashLayout.pageHeight >= NotchSplashLayout.cardHeight(compact: false)
                         && NotchSplashLayout.pageMinimumHeight < NotchSplashLayout.pageHeight,
                     "the page is as tall as the card it carries, with a floor beneath it")
        // The page's height is what the page has to show: a session's page is
        // as tall as the card of four charts, the memory and the trend; a page
        // before a session is its ruler and its words, and nothing between.
        var withSession = NotchPageContent.empty
        withSession.splashDashboard = true
        suite.expect(NotchNaturalContent.height(module: .splash, items: withSession, width: 700)
                         == NotchSplashLayout.pageHeight
                         && NotchNaturalContent.height(module: .splash, items: .empty, width: 700)
                             == NotchSplashLayout.pageSetupHeight
                         && NotchSplashLayout.pageSetupHeight < NotchSplashLayout.pageHeight
                         && NotchPageFloor.contentHeight(module: .splash)
                             == NotchSplashLayout.pageMinimumHeight
                         && NotchSplashLayout.pageMinimumHeight < NotchSplashLayout.pageSetupHeight,
                     "the page measures what it has to show: the card's height with a session, and the ruler and the words before one")
        // A session that is reading draws its card and no ruler above it, so the
        // page is measured to the card alone: the island keeps no ground for a
        // control the page stopped drawing the moment Start was pressed.
        var reading = NotchPageContent.empty
        reading.splashDashboard = true
        reading.splashReading = true
        suite.expect(NotchSplashLayout.pageReadingHeight == NotchSplashLayout.cardHeight(compact: false)
                         && NotchNaturalContent.height(module: .splash, items: reading, width: 700)
                             == NotchSplashLayout.pageReadingHeight
                         && NotchSplashLayout.pageReadingHeight < NotchSplashLayout.pageHeight,
                     "the page of a running reading is its card, and keeps no room for the ruler it does not draw")
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
        "notifyCompletedBody", "notifyActivityEndedBody", "dayCount", "daysAndTokens",
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
        suite.expect(english.notifyActivityEndedTitle == "Splash Task Activity Ended",
                     "the notice of a run that ended says the activity ended, which is what the endpoint supports")
        suite.expect(english.notifyActivityEndedBody("2m 20s", "1:16 PM", "1:31 PM", "1:41 PM").contains("2m 20s")
                         && english.notifyActivityEndedBody("2m 20s", "1:16 PM", "1:31 PM", "1:41 PM").contains("Ten minutes")
                         && english.notifyActivityEndedBody("2m 20s", "1:16 PM", "1:31 PM", "1:41 PM").contains("1:16 PM")
                         && english.notifyActivityEndedBody("2m 20s", "1:16 PM", "1:31 PM", "1:41 PM").contains("1:31 PM")
                         && english.notifyActivityEndedBody("2m 20s", "1:16 PM", "1:31 PM", "1:41 PM").contains("1:41 PM"),
                     "the notice names the window that ended the run, and carries the clock's length and the run's "
                     + "three times of the day")
        suite.expect(english.memoryAndKVCache == "Memory & KV Cache" && english.trend == "Trend"
                         && english.utilization == "Utilization",
                     "the two new cards and their bar are named as the reference names them")
        suite.expect(english.inputSeries == "Input tokens" && english.outputSeries == "Output tokens",
                     "the trend's two colours are named, in the trend's own words")
        suite.expect(english.daysAndTokens(30, "705M") == "30 days · 705M",
                     "the trend's caption is the period and the period's tokens, as the reference writes it")
        suite.expect(english.kvScarce == "pages running short" && english.kvSpilling == "spilling",
                     "the cache's shortage is said in words, and not in a colour alone")
        suite.expect(english.title == "Splash Dashboard",
                     "the header is written as the words of a heading, and the card writes them as they are")
        suite.expect(english.decode == "Decode Speed" && english.prefill == "Prefill Speed"
                         && english.ttft == "TTFT" && english.cacheHitRate == "Cache Hit Rate",
                     "the four readings are named as the reference names them")
        suite.expect(english.tokensPerSecond == "t/s",
                     "the throughput's unit is the short form, written against the number and nowhere longer")
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
        // The figures of a measuring card are drawn in the colours of the lines
        // they come from, and every card writes purple first and green second: a
        // throughput's batch in hand, and the first token's p50.
        suite.expect(NotchSplashPalette.figureTints(.decode) == (NotchSplashPalette.purple, NotchSplashPalette.green)
                         && NotchSplashPalette.figureTints(.prefill) == (NotchSplashPalette.purple, NotchSplashPalette.green),
                     "a throughput's batch in hand is purple, the average over the running green")
        suite.expect(NotchSplashPalette.figureTints(.ttft) == (NotchSplashPalette.purple, NotchSplashPalette.green),
                     "the first token's p50 is written first, in purple, and its p95 second, in green")
        suite.expect(NotchSplashPalette.lineTints(.decode) == (NotchSplashPalette.purple, NotchSplashPalette.green)
                         && NotchSplashPalette.lineTints(.prefill) == (NotchSplashPalette.purple, NotchSplashPalette.green),
                     "a throughput's batch in hand is the purple line, the average over the running the green")
        suite.expect(NotchSplashPalette.lineTints(.ttft) == (NotchSplashPalette.green, NotchSplashPalette.purple),
                     "the first token's p95 is the green line and its p50 the purple")
        // A figure is the colour of the line it is drawn from, so a pair of
        // numbers needs no key. The throughputs write the purple line's figure
        // first; the first token's card writes the purple line's figure first
        // too, and it is its p50, the average's line, while its tail is green.
        suite.expect(NotchSplashPalette.figureTints(.ttft).first == NotchSplashPalette.lineTints(.ttft).average
                         && NotchSplashPalette.figureTints(.ttft).second == NotchSplashPalette.lineTints(.ttft).leading,
                     "the first token's figures wear their own lines' colours: the p50 the p50 line's purple, the p95 the p95 line's green")
        suite.expect(NotchSplashPalette.figureTints(.decode) == NotchSplashPalette.lineTints(.decode)
                         && NotchSplashPalette.figureTints(.prefill) == NotchSplashPalette.lineTints(.prefill),
                     "a throughput's figures wear their own lines' colours")
        suite.expect(NotchSplashPalette.figureTints(.decode) != (NotchSplashPalette.purple, NotchSplashPalette.blue)
                         && NotchSplashPalette.lineTints(.ttft) != (NotchSplashPalette.purple, NotchSplashPalette.blue),
                     "no measuring card draws its average's line in blue any more")
        // The cache's hit rate keeps the colour of its own threshold, and is not
        // one of the paired cards.
        suite.expect(NotchSplashSupport.cacheTone(NotchSplashSupport.cacheGreenThreshold + 1) == .green
                         && NotchSplashSupport.cacheTone(NotchSplashSupport.cacheAmberThreshold) == .amber
                         && NotchSplashSupport.cacheTone(NotchSplashSupport.cacheAmberThreshold - 1) == .red
                         && NotchSplashSupport.cacheTone(nil) == .neutral,
                     "the hit rate is coloured by its own thresholds, as it has always been")
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
        // The history the session keeps goes to a file of the test's own, so a
        // test never writes to the file the app keeps, and can read back what
        // the session recorded.
        let historyPath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vorss-tests-splash-history-\(ProcessInfo.processInfo.processIdentifier).json")
        let history = NotchSplashHistoryStore(url: historyPath)
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
            deliver: { world.notices.append($0) },
            history: history)

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
            let runBegan = world.now
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
                         "a counter that moved is the engine working, and the engine working is not the end")
            // The confirmation, at its own length. The reading that found the
            // engine quiet is the mark the clock freezes at, and it is noted here
            // before the clock is turned; two readings of nothing follow, the
            // second past the ten-minute window, so the task ends on the second
            // with its clock at the length of the work and not of the work plus
            // the window. The virtual clock jumps, as a test's clock must, so the
            // run's length here is the test's own arithmetic.
            let quietMark = world.now
            world.now = world.now.addingTimeInterval(5 * 60 + 10)
            spin(2.6)
            suite.expect(service.isTaskRunning && world.notices.isEmpty,
                         "a quiet of five minutes is inside the window: the run goes on, its clock at rest")
            suite.expect(Int(service.elapsed()) == 49,
                         "the card's clock rests at the last work while the window runs - "
                         + "forty-nine seconds of task, and the window's minutes are not added to it")
            world.now = world.now.addingTimeInterval(5 * 60 + 10)
            spin(2.6)
            suite.expect(service.taskOutcome == .completed && service.isTaskFinished,
                         "a quiet that outlasts the window is the task's end, confirmed by its counter")
            suite.expect(Int(service.elapsed()) == 49,
                         "the clock froze at the first reading that saw no work, and not at the notice")
            suite.expect(service.isMonitoring, "the completion did not stop the reading")
            suite.expect(world.notices.count == 1,
                         "one task is one notice, whatever turns it had")
            suite.expect(world.notices.first?.title == "Splash Task Activity Ended"
                             && world.notices.first?.body.contains("00:49") == true,
                         "the notice says the activity ended, which is what the endpoint supports, and carries "
                         + "the clock's frozen length")
            // The notice's three times of the day: where the run began, the
            // quiet mark its clock froze at, and the moment these words went out
            // - a whole window after that mark, which is why the sent time is the
            // session's clock and never the mark.
            suite.expect(service.phase == .finished(id: "req-a", outcome: .completed,
                                                    startedAt: runBegan, at: quietMark, elapsed: 49),
                         "the finished phase carries the run's start and the quiet mark it froze at")
            let began = NotchSplashSupport.timeOfDayText(runBegan)
            let over = NotchSplashSupport.timeOfDayText(quietMark)
            let sent = NotchSplashSupport.timeOfDayText(world.now)
            suite.expect(world.notices.first?.body.contains(began) == true
                             && world.notices.first?.body.contains(over) == true
                             && world.notices.first?.body.contains(sent) == true,
                         "the notice carries the run's length and the three times that place it in the day: the start, "
                         + "the quiet the clock froze at, and the moment the notice was sent")
            suite.expect(world.notices.first!.body.range(of: "lasted \(NotchSplashSupport.taskClock(49))") != nil,
                         "the length is the card's own number, written as the card writes it")
            suite.expect(!world.notices.first!.title.contains("Completed"),
                         "the app does not claim a completion the endpoint never reported")
            // A quiet of ten minutes is a run over, and the reading is not asked
            // to stop by it: the window is one number, and a gap inside it - or
            // long after it - leaves the run, the clock, and the polling alone.
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
            // The work is twelve seconds long and the window has just opened. The
            // card shows twelve, and shows twelve when the window closes: the task
            // clock and the confirmation are two timers, and the confirmation never
            // adds to the task's number.
            suite.expect(Int(service.elapsed()) == 12 && service.isTaskRunning,
                         "with the window open the card shows the work's length, and the task is open")
            world.now = world.now.addingTimeInterval(5 * 60 + 10)
            spin(2.6)
            suite.expect(Int(service.elapsed()) == 12 && service.isTaskRunning,
                         "five of the window's minutes pass, and the task's length does not move")
            world.now = world.now.addingTimeInterval(5 * 60 + 10)
            spin(2.6)
            suite.expect(service.taskOutcome == .completed && Int(service.elapsed()) == 12,
                         "the second task is timed and frozen on its own length, not on that length plus the window")
            suite.expect(world.notices.count == 2 && world.notices.last?.body.contains("00:12") == true,
                         "the second completion is its own notice, with the length the work measured")
            suite.expect(service.isMonitoring, "and the reading is still running")
            // The same moment, read as the island reads it: the clock froze, so
            // Splash is no longer an activity, while the card keeps its reading
            // and its frozen numbers. The two rules answer two questions, and
            // the clock is the state behind both.
            suite.expect(!service.isTaskRunning
                             && !NotchSplashSupport.showsIslandActivity(sectionVisible: true,
                                                                         isTaskRunning: service.isTaskRunning,
                                                                         isLive: service.stripReadingIsLive)
                             && service.isMonitoring
                             && NotchSplashSupport.showsDashboardCard(sectionVisible: true,
                                                                       isMonitoring: service.isMonitoring),
                         "at the notice the clock is frozen: no Splash activity on the island, and the card stays")

            // A task that fails is told as a failure, and the reading goes on
            // to take up the next request. The completed count does not move:
            // only the failed one does, which is what makes this a failure.
            world.documents = [running("req-c", completed: 5)]
            spin(1.4)
            suite.expect(service.isTaskRunning
                             && NotchSplashSupport.showsIslandActivity(sectionVisible: true,
                                                                        isTaskRunning: service.isTaskRunning,
                                                                        isLive: service.stripReadingIsLive),
                         "the next request begins a clock of its own, and the island takes Splash back as an activity")
            world.documents = [done(5, failed: 1)]
            world.now = world.now.addingTimeInterval(5)
            spin(1.4)
            world.now = world.now.addingTimeInterval(605)
            spin(2.6)
            world.now = world.now.addingTimeInterval(605)
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

            // What has been read is the history the four charts draw. This
            // server names no figures at all, so there is nothing to record,
            // and nothing is invented for the charts to draw.
            suite.expect(!history.history.hasSamples,
                         "a server that names no figures leaves no sample behind")
            world.documents = [#"{"instance": {"id": "a"}, "requests": {"completed": 3, "failed": 0, "cancelled": 0}, "active_requests": [], "metrics": {"decode_tokens_per_second": 88.5, "prefill_tokens_per_second": 640, "ttft_ms": {"p50": 700}}, "cache": {"hits": 90, "requests": 100}}"#]
            // The session reads at four seconds here, so the reading has to be
            // waited for at that pace.
            spin(5.4)
            suite.expect(history.history.hasSamples
                             && history.history.samples.last?.decode == 88.5
                             && history.history.samples.last?.prefill == 640
                             && history.history.samples.last?.ttftSeconds == 0.7,
                         "a reading that names its figures is recorded, and is what the charts draw")
            suite.expect(history.history.samples.allSatisfy { $0.at <= world.now },
                         "no reading is written in the future")
            suite.expect(history.history.trend(now: world.now, count: 30).last?.total == 0,
                         "and this server, which never reported a counter to take a difference from, writes no tokens")
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
            // The file of the test's own, and nothing of the app's.
            history.flush(at: world.now)
            suite.expect(FileManager.default.fileExists(atPath: historyPath.path),
                         "the measured past is written where the session was told to write it")
            try? FileManager.default.removeItem(at: historyPath)
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
        suite.expect(NotchSplashSupport.savedInterval(in: defaults) == 1,
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

        // The dashboard's own beginning: this Mac's Splash server and the port
        // it answers on. The app ships no key of its own - a key belongs to the
        // machine, in the settings the person writes or in the environment the
        // session starts with.
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchSplashHost] as? String
                         == NotchSplashEndpoint.localHost
                         && Defaults.registeredDefaults[DefaultsKey.notchSplashPort] as? Int
                             == NotchSplashEndpoint.defaultPort
                         && Defaults.registeredDefaults[DefaultsKey.notchSplashAPIKey] as? String == ""
                         && NotchSplashEndpoint.localAPIKeyEnvironment == "VOSSAINT_SPLASH_API_KEY",
                     "the settings begin at the local Splash server and carry no key of their own")
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
            DefaultsKey.notchSplashAPIKey: "",
            DefaultsKey.notchSplashIntervalSeconds: NotchSplashSupport.defaultInterval,
        ])
        let machine = ["VOSSAINT_SPLASH_API_KEY": "sk-env-key"]
        suite.expect(NotchSplashSupport.endpoint(in: local)?.absoluteString == "http://127.0.0.1:8001/status",
                     "a dashboard switched on with nothing typed reads this Mac's Splash server")
        suite.expect(NotchSplashSupport.savedAPIKey(in: local, environment: [:]) == ""
                         && !NotchSplashSupport.hasAPIKey(in: local, environment: [:]),
                     "nothing is sent when no key was written and the machine hands none over")
        suite.expect(NotchSplashSupport.savedAPIKey(in: local, environment: machine) == "sk-env-key"
                         && NotchSplashSupport.hasAPIKey(in: local, environment: machine)
                         && !NotchSplashSupport.hasWrittenAPIKey(in: local),
                     "the machine's own key is used, is known to be there, and is not called written by hand")
        local.set("sk-written-key", forKey: DefaultsKey.notchSplashAPIKey)
        suite.expect(NotchSplashSupport.savedAPIKey(in: local, environment: machine) == "sk-written-key"
                         && NotchSplashSupport.hasWrittenAPIKey(in: local),
                     "a key written into the settings takes the place of the machine's own")
        local.set("  sk-written-key  ", forKey: DefaultsKey.notchSplashAPIKey)
        suite.expect(NotchSplashSupport.savedAPIKey(in: local, environment: machine) == "sk-written-key",
                     "a key is sent as it stands, without the spaces around it")
        local.set("", forKey: DefaultsKey.notchSplashAPIKey)
        suite.expect(NotchSplashSupport.savedAPIKey(in: local, environment: machine) == "sk-env-key"
                         && !NotchSplashSupport.hasWrittenAPIKey(in: local),
                     "clearing the field leaves the machine's own key in place, and it is not written to the settings")
        local.set("splash.local", forKey: DefaultsKey.notchSplashHost)
        local.set(9009, forKey: DefaultsKey.notchSplashPort)
        suite.expect(NotchSplashSupport.endpoint(in: local)?.absoluteString == "http://splash.local:9009/status",
                     "an address written by hand outlasts the default, which is what a saved setting is for")
        for key in keys { local.removeObject(forKey: key) }
    }


    // MARK: The island's activity, and the mark it wears

    /// The closed island asks one question of a reading, and the answer is the
    /// card's clock: while that clock advances, Splash is an activity, and in
    /// the one moment the clock freezes and the task's news is told, it is not.
    ///
    /// The reading, the server and the dashboard are untouched by that moment
    /// and keep their state, which is exactly why the island may not read them:
    /// a card left open on a finished task, and a server that still answers, are
    /// not work being watched. The mark is the other half of the same section:
    /// the strip wears the mark the card wears, in the same view at the strip's
    /// size, so one section is one shape wherever it is seen.
    static func islandActivityChecks(_ suite: TestSuite) {
        func source(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
        // The rule, in its cases: the section, the clock, and the reading's own
        // answer about the engine's present.
        suite.expect(NotchSplashSupport.showsIslandActivity(sectionVisible: true, isTaskRunning: true, isLive: true),
                     "a clock that is advancing over an engine at work is an activity on the island")
        suite.expect(!NotchSplashSupport.showsIslandActivity(sectionVisible: true, isTaskRunning: false, isLive: true),
                     "a frozen clock is not an activity, whatever the server and the dashboard go on to say")
        suite.expect(!NotchSplashSupport.showsIslandActivity(sectionVisible: false, isTaskRunning: true, isLive: true),
                     "a section not in the island has no strip, clock advancing or not")
        suite.expect(!NotchSplashSupport.showsIslandActivity(sectionVisible: true, isTaskRunning: true, isLive: false),
                     "a run kept open through its confirmation window is news being waited for, not work: a quiet "
                     + "engine keeps its clock, its card and its averages, and shows no speed on the island")
        // One clock, one answer, at the tracker's own moment of ending: the task
        // runs, the island registers it; the task ends, its clock freezes, and
        // the island lets it go while the card keeps it.
        var tracker = NotchSplashTaskTracker(quiescence: 30, quietReadingsNeeded: 2)
        _ = tracker.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 3}, "active_requests": [{"id": "r1"}]}"#),
                            at: start)
        suite.expect(tracker.isRunning
                         && NotchSplashSupport.showsIslandActivity(sectionVisible: true,
                                                                    isTaskRunning: tracker.isRunning,
                                                                    isLive: true),
                     "the running clock the card shows is the state the island registers")
        _ = tracker.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": []}"#),
                            at: start.addingTimeInterval(10))
        let ended = tracker.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": []}"#),
                                    at: start.addingTimeInterval(45))
        suite.expect(ended != nil && !tracker.isRunning
                         && !NotchSplashSupport.showsIslandActivity(sectionVisible: true,
                                                                     isTaskRunning: tracker.isRunning,
                                                                     isLive: false)
                         && NotchSplashSupport.showsDashboardCard(sectionVisible: true, isMonitoring: true)
                         && tracker.elapsed(at: start.addingTimeInterval(600)) == 10,
                     "the moment the task is told leaves the island and keeps the card, on the one frozen clock, "
                     + "frozen at the work's ten seconds and not at the window's end")
        suite.expect(tracker.observe(snapshot(#"{"instance": {"id": "a"}, "requests": {"completed": 4}, "active_requests": []}"#),
                                     at: start.addingTimeInterval(80)) == nil,
                     "an idle reading after the telling says nothing, and the island keeps Splash off")
        // The service asks the clock and nothing else, and is told by the same
        // publication that freezes it: no health check, no connection test,
        // no timeout of its own beside the tracker's.
        let service = source("Sources/Vorssaint/Services/Notch/NotchService.swift")
        let head = "    var hasSplashActivity: Bool {"
        let body: String = {
            guard let found = service.range(of: head) else { return "" }
            let tail = service[found.upperBound...]
            let end = tail.range(of: "\n    }")?.lowerBound ?? tail.startIndex
            return String(tail[..<end])
        }()
        suite.expect(body.contains("showsIslandActivity") && body.contains("isTaskRunning")
                         && body.contains("isLive") && body.contains("stripReadingIsLive"),
                     "the island's Splash activity is the clock and the reading's answer about the present: "
                     + "\(body.trimmingCharacters(in: .whitespacesAndNewlines))")
        suite.expect(!body.contains("isMonitoring") && !body.contains("isTaskFinished")
                         && !body.contains("stripShowsDecodeSpeed") && !body.contains("snapshot")
                         && !body.contains("hasWork"),
                     "a reading that goes on, a task that has been told, a decode figure that can be missing for a "
                     + "moment between two generations, and the status read at the island are none of them in the "
                     + "island's rule")
        suite.expect(service.contains("Publishers.CombineLatest3(splash.$isMonitoring.removeDuplicates(),")
                         && service.contains("splash.$phase.removeDuplicates()"),
                     "the island is woken by the same publication that freezes the clock, and by no poller of its own")
        // The mark, in one definition: the card's view at the strip's size, and
        // the room the knot is drawn at, which the shared rule answers.
        let strip = source("Sources/Vorssaint/UI/Notch/NotchSplashStrip.swift")
        let capsule = source("Sources/Vorssaint/UI/Notch/NotchCapsuleViews.swift")
        let card = source("Sources/Vorssaint/UI/Notch/NotchSplashView.swift")
        suite.expect(strip.contains("NotchSectionMark(module: .splash, size: iconSize, tint: NotchSplashPalette.purple)")
                         && !strip.contains("Image(systemName: NotchModule.splash.symbol)"),
                     "the strip wears the card's mark in the card's view, and draws no symbol of its own")
        suite.expect(capsule.contains("NotchSectionMark(module: .splash, size: CapsuleLayout.symbolSize, tint: NotchSplashPalette.purple)")
                         && !capsule.contains("NotchCapsuleSymbol(name: NotchModule.splash.symbol"),
                     "the capsule's row wears the same mark as the strip and the card")
        suite.expect(card.contains("NotchSectionMark(module: .splash, size:"),
                     "the card's mark is the shared view, so the strip and the card have one definition")
        // The clock the card shows is the tracker's, not a span measured here:
        // a wall-clock span from the run's beginning would count the whole
        // confirmation window as task time, which is the number the card must
        // never show.
        suite.expect(card.contains("clockText(NotchSplashSupport.taskClock(elapsed))")
                         && !card.contains("Date().timeIntervalSince(startedAt)"),
                     "the card's clock ticks from what the readings measured, so the window is never counted as task time")
        suite.expect(strip.contains("NotchSectionMark.side(size: iconSize, module: .splash)")
                         && strip.contains("boxHeight: markSide, radius: markSide / 2"),
                     "the strip reserves and clears what the mark is drawn at, so its position stays the strip's own")
        suite.expect(source("Sources/Vorssaint/UI/Notch/NotchComponents.swift")
                         .contains("module == .splash ? size * AgentProvider.codex.markScale : size"),
                     "the wider side the knot is drawn at is one rule, shared by every surface that reserves room for it")
    }

    // MARK: The page, its spacing, and what it does not draw

    /// The page before a reading, and the space a section's mark keeps from its
    /// name.
    ///
    /// The page is its ruler, its value and its Start. The mark at display size
    /// and the block of words that said what Start does and does not send are
    /// gone, and the page's own height keeps no room for them: a page measured
    /// for words it does not draw is a page of empty ground under the ruler.
    /// The space between a mark and a name is the island's one rule, so the
    /// section is not crowded in one surface and roomy in another.
    static func pageChecks(_ suite: TestSuite) {
        func source(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
        let page = source("Sources/Vorssaint/UI/Notch/NotchSplashView.swift")
        // One rule, in the island's own layout, at a gap a name is readable at.
        suite.expect(NotchLayout.sectionMarkTitleGap >= 7 && NotchLayout.sectionMarkTitleGap <= 12,
                     "a section's mark keeps a readable space from its name: \(NotchLayout.sectionMarkTitleGap)pt")
        suite.expect(page.components(separatedBy: "\n")
                         .filter { $0.contains("spacing: NotchLayout.sectionMarkTitleGap") }.count == 1,
                     "the page's title line asks the shared rule, and writes no number of its own")
        // The page before a session: the ruler, the value it rests on, and the
        // ground under it. No mark at display size, no block of words.
        suite.expect(NotchSplashLayout.pageSetupHeight
                         == NotchLayout.timerRulerHeight + NotchLayout.rowSpacing + NotchSplashLayout.pageGroundHeight,
                     "the page before a session is measured to its ruler and its ground: "
                     + "\(NotchSplashLayout.pageSetupHeight)pt")
        suite.expect(NotchSplashLayout.pageSetupHeight
                         < NotchLayout.timerRulerHeight + NotchLayout.rowSpacing + 78,
                     "the page keeps no room for the block of words it no longer draws: "
                     + "\(NotchSplashLayout.pageSetupHeight)pt")
        suite.expect(!page.contains("NotchSectionMark(module: .splash, size: 30")
                         && !page.contains("Text(text.setupHint)"),
                     "the page draws no display-size mark and no explanatory block")
        suite.expect(page.contains("accessibilityIdentifier(\"notch.splash.start\")")
                         && page.contains("notchBand(trailing:")
                         && page.contains("intervalRow"),
                     "the page keeps its header, its ruler and its one action")
        // While a session reads, the row carries no mark of its own: the way
        // out is the card's corner, and the island's corner keeps its room for
        // the page's own controls. The ruler is the page's choice before a
        // reading and after one, and a running page draws the card alone.
        suite.expect(page.contains("if !service.isMonitoring {\n                startButton")
                         && !page.contains("NotchIconButton(symbol: \"xmark\"")
                         && page.contains("if !service.isMonitoring { intervalRow }")
                         && page.contains("NotchCircularIconButton(symbol: \"xmark\", title: text.stop")
                         && page.contains("onStop: service.isMonitoring ? { service.stop() } : nil"),
                     "a running reading draws no row mark and no ruler, and the card keeps the way out")
        // A reading's page is the longer page, and the ruler is the same control
        // on both, so the setup page's shortening moves nothing the person aims at.
        suite.expect(NotchSplashLayout.pageHeight > NotchSplashLayout.pageSetupHeight,
                     "the page of a reading is the longer page, as it has been")
        // The card in Live Activities is the compact card: measured without the
        // trend it does not draw, which is what keeps the dashboard's height and
        // the card's own the same number.
        suite.expect(NotchSplashLayout.cardHeight(compact: true)
                         < NotchSplashLayout.cardHeight(compact: false),
                     "the dashboard's card is measured without the trend, as it is drawn")
    }

    /// The closed island's throughput: what the reading has to answer for, and
    /// what it may not.
    ///
    /// The endpoint keeps the rate of the batch it finished last, marks it valid,
    /// and answers the engine's average over the whole of its running beside it -
    /// and it does all of that while it has nothing in hand. `valid` says the
    /// measurement is well-formed, not that a batch is running, so a figure of
    /// the present is kept only over a reading that says the engine is at work:
    /// an idle engine has no speed on the island, while the card keeps the
    /// averages, the clock it froze, and the reading it is on.
    static func stripThroughputChecks(_ suite: TestSuite) {
        /// The reference's own idle answer: the last batch marked valid, the
        /// lifetime average beside it, and nothing counted as work anywhere.
        let resting = """
        {"instance": {"id": "a"},
         "requests": {"completed": 3, "failed": 0, "cancelled": 0},
         "active_requests": [],
         "scheduler": {"queued": 0, "waiting_resources": 0, "prefilling": 0, "decoding": 0},
         "frontend": {"active": 0, "waiting": 0},
         "transport": {"pending": 0, "status_stale": false},
         "metrics": {"decode_tokens_per_second": 92.3, "prefill_tokens_per_second": 481.2,
                     "current_decode_batch": {"valid": true, "tokens_per_second": 104.5},
                     "current_prefill_batch": {"valid": true, "tokens_per_second": 316.3},
                     "ttft_ms": {"p50": 2068, "p95": 7985},
                     "prefill_input_tokens": 2011746, "decode_output_tokens": 464776}}
        """
        func metrics(_ batch: String) -> String {
            "\"metrics\": {\"decode_tokens_per_second\": 92.3, \"prefill_tokens_per_second\": 481.2, "
                + "\"current_decode_batch\": \(batch), \"ttft_ms\": {\"p50\": 2068, \"p95\": 7985}, "
                + "\"prefill_input_tokens\": 2011746, \"decode_output_tokens\": 464776}"
        }
        func atWork(_ id: String, batch: String) -> String {
            "{\"instance\": {\"id\": \"a\"}, "
                + "\"requests\": {\"completed\": 3, \"failed\": 0, \"cancelled\": 0}, "
                + "\"active_requests\": [{\"id\": \"\(id)\"}], \"scheduler\": {\"decoding\": 1}, \(metrics(batch))}"
        }
        /// The same work, answered with a batch the engine does not measure: the
        /// rates it keeps are the averages, and no current figure arrives.
        func atWorkWithoutBatch(_ id: String) -> String {
            atWork(id, batch: "{\"valid\": false, \"tokens_per_second\": 104.5}")
        }
        func quiet(completed: Int) -> String {
            "{\"instance\": {\"id\": \"a\"}, \"requests\": {\"completed\": \(completed), \"failed\": 0, \"cancelled\": 0}, "
                + "\"active_requests\": [], \"scheduler\": {\"decoding\": 0}, "
                + "\"metrics\": {\"decode_tokens_per_second\": 92.3, "
                + "\"current_decode_batch\": {\"valid\": true, \"tokens_per_second\": 104.5}, "
                + "\"prefill_input_tokens\": 2011800, \"decode_output_tokens\": 464900}}"
        }

        let world = PollingWorld(start: start, documents: [resting])
        let historyPath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vorss-tests-splash-strip-\(ProcessInfo.processInfo.processIdentifier).json")
        let service = NotchSplashService(
            read: { _, _, _ in (Data(world.nextDocument().utf8), world.code) },
            address: { world.address },
            enabled: { world.enabled },
            savedInterval: { world.interval },
            keepInterval: { _ in },
            clock: { world.now },
            strings: { FeatureStrings.notchSplash(.enUS) },
            deliver: { world.notices.append($0) },
            history: NotchSplashHistoryStore(url: historyPath))

        func spin(_ seconds: TimeInterval) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        func islandActivity() -> Bool {
            NotchSplashSupport.showsIslandActivity(sectionVisible: true, isTaskRunning: service.isTaskRunning,
                                                   isLive: service.stripReadingIsLive)
        }

        MainActor.assumeIsolated {
            // The rule, asked of the reading a real endpoint gives an idle engine.
            let idle = status(resting)
            suite.expect(!idle.hasWork, "an engine that names no request and counts nothing is at rest")
            suite.expect(idle.metrics.currentDecodeBatchTokensPerSecond == 104.5
                             && idle.metrics.decodeTokensPerSecond == 92.3,
                         "a resting engine still answers the last batch's rate as valid, and its average beside it")
            suite.expect(NotchSplashLiveMetrics.current(idle.metrics, present: false).decode == nil
                             && NotchSplashLiveMetrics.current(idle.metrics, present: false).prefill == nil,
                         "over a reading at rest those batch rates are not figures of the present")
            suite.expect(NotchSplashLiveMetrics.current(idle.metrics, present: true).decode == 104.5,
                         "over a reading at work the batch in hand is the figure")
            suite.expect(NotchSplashLiveMetrics.current(idle.metrics, present: false).ttftP50 == 2.068,
                         "the percentiles of finished requests are not figures of the present, and rest keeps them")

            service.start()
            spin(1.4)
            suite.expect(service.isMonitoring && service.snapshot != nil && service.reads >= 1,
                         "the reading is running over a resting engine")
            suite.expect(!service.stripReadingIsLive && service.stripDecodeSpeed == nil
                             && !service.stripShowsDecodeSpeed,
                         "a resting engine that answers a valid last batch and a lifetime average of 92.3 leaves the "
                         + "strip with no throughput at all")
            suite.expect(service.live.decode == nil && service.live.prefill == nil,
                         "the card's current figures are empty over a resting reading")
            suite.expect(!islandActivity(), "and the closed island shows no Splash strip over an idle engine")
            suite.expect(service.snapshot?.status.metrics.decodeTokensPerSecond == 92.3
                             && service.phase == .idle && service.elapsed() == 0,
                         "the card keeps the lifetime average to draw, and times nothing")
            suite.expect(NotchSplashSupport.showsDashboardCard(sectionVisible: true,
                                                               isMonitoring: service.isMonitoring),
                         "the dashboard card stands for the reading, idle engine and all")

            // Work: the batch in hand is the figure, and the island has a strip.
            world.documents = [atWork("req-1", batch: "{\"valid\": true, \"tokens_per_second\": 116.7}")]
            spin(1.4)
            suite.expect(service.isTaskRunning && service.stripReadingIsLive
                             && service.stripDecodeSpeed == 116.7 && service.stripShowsDecodeSpeed
                             && islandActivity(),
                         "a decode the engine is running is measured and shown: the batch in hand, not the average")

            // A batch the engine does not measure, over an engine at work: the
            // strip keeps its place and its placeholder, and no stale figure
            // is brought in to fill it.
            world.documents = [atWorkWithoutBatch("req-1")]
            spin(1.4)
            suite.expect(service.stripReadingIsLive && islandActivity() && service.stripDecodeSpeed == nil
                             && NotchSplashSupport.stripSpeedText(nil) == nil,
                         "an engine at work that answers no batch keeps the strip's place, and its number is missing")

            // The work ends and the counters move: the run stays open for its
            // confirmation window, and the closed island lets the speed go with
            // the last reading of the engine at rest. The task, its clock and
            // the reading are untouched by the strip leaving.
            let opened = service.phase
            world.documents = [quiet(completed: 4)]
            spin(1.4)
            suite.expect(service.isTaskRunning && service.trackedID == "req-1" && service.isMonitoring,
                         "the quiet run is kept open, its clock and its reading as they were")
            suite.expect(service.phase == opened && !service.isTaskFinished,
                         "the task's tracking is not reset because the strip went away")
            suite.expect(!service.stripReadingIsLive && service.stripDecodeSpeed == nil && !islandActivity(),
                         "a run open over a resting engine shows no throughput: the last batch's rate and the "
                         + "lifetime average are both figures of what the engine has done")
            suite.expect(service.snapshot?.status.metrics.decodeTokensPerSecond == 92.3,
                         "and the card is left with its averages to draw")

            // The next prompt: the strip comes back with the batch in hand, in
            // the same run and on the same clock.
            world.documents = [atWork("req-2", batch: "{\"valid\": true, \"tokens_per_second\": 74.25}")]
            spin(1.4)
            suite.expect(service.trackedID == "req-1" && service.isTaskRunning
                             && service.stripDecodeSpeed == 74.25 && islandActivity(),
                         "work seen again resumes the same run, and the strip returns with the new batch's rate")

            // A reading that did not arrive is not a reading of the present.
            world.code = 500
            spin(1.6)
            suite.expect(service.failure != nil && !service.stripReadingIsLive
                             && service.stripDecodeSpeed == nil && !islandActivity(),
                         "a status that answers no reading leaves the strip with nothing to show")
            suite.expect(service.snapshot?.status.metrics.decodeTokensPerSecond == 92.3 && service.isMonitoring,
                         "the card keeps the last reading it was given, and the reading goes on")
            world.code = 200
            world.documents = [atWork("req-3", batch: "{\"valid\": true, \"tokens_per_second\": 88}")]
            spin(1.4)
            suite.expect(service.stripDecodeSpeed == 88 && islandActivity(),
                         "and the strip returns with the next reading that measures a batch")

            // A reading that arrived already old, and an engine begun again,
            // answer nothing of the present either.
            service.stop()
            suite.expect(!service.stripReadingIsLive && service.stripDecodeSpeed == nil && !islandActivity(),
                         "the way out leaves the strip with nothing, as an idle engine does")
        }
    }

    static func run(_ suite: TestSuite) {
        suite.run("splash settings") { settingsChecks(suite) }
        suite.run("splash reading") { readingChecks(suite) }
        suite.run("splash metrics") { metricChecks(suite) }
        suite.run("splash live metrics") { liveMetricChecks(suite) }
        suite.run("splash pairs") { pairChecks(suite) }
        suite.run("splash strip priority") { priorityChecks(suite) }
        suite.run("splash text") { textChecks(suite) }
        suite.run("splash history") { historyChecks(suite) }
        suite.run("splash task") { taskChecks(suite) }
        suite.run("splash task tokens") { taskTokenChecks(suite) }
        suite.run("splash notices") { noticeChecks(suite) }
        suite.run("splash session") { sessionChecks(suite) }
        suite.run("splash polling") { pollingChecks(suite) }
        suite.run("splash monitoring") { monitoringChecks(suite) }
        suite.run("splash ruler") { rulerChecks(suite) }
        suite.run("splash dashboard") { dashboardChecks(suite) }
        suite.run("splash island activity") { islandActivityChecks(suite) }
        suite.run("splash strip throughput") { stripThroughputChecks(suite) }
        suite.run("splash page") { pageChecks(suite) }
        suite.run("splash strings") { localizationChecks(suite) }
        suite.run("splash palette") { paletteChecks(suite) }
    }
}
