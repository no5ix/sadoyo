// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The memory list's accounting: which processes it asks, the metric it shows,
/// and the rows it makes of the answers.
///
/// The list's promise is Activity Monitor's Memory column: this process, this
/// pid, this much physical memory, heaviest first. Three failures are checked
/// here, because each of them was seen on a real Mac:
///
/// * Ranking candidates by resident size before reading footprints left out a
///   process whose footprint is far above its resident pages.
/// * Summing footprints under the process a helper is responsible for showed a
///   figure no process holds, under the responsible app's name and pid, while
///   the process that held the memory disappeared.
/// * Rows keyed by name, icon, or app identity drop the process when the
///   icon, name, or app identity is missing.
enum ProcessMemoryAccountingTests {
    /// The rule the list used, kept here to show what it did to the same sample.
    private struct Legacy {
        struct Process {
            let pid: pid_t
            /// Resident size, as `ps -m` ranks by it.
            let resident: UInt64
            /// Kernel footprint, the figure the list showed.
            let footprint: UInt64
            let name: String
            /// The process the responsibility API bills this one to.
            let owner: pid_t
            let ownerName: String
        }

        /// Rank by resident size, keep the first `candidateLimit` rows, read
        /// footprints, then add them up under each row's responsible pid.
        static func rows(_ processes: [Process], candidateLimit: Int, limit: Int) -> [(pid: pid_t, name: String, bytes: UInt64)] {
            let candidates = processes.sorted { $0.resident > $1.resident }.prefix(candidateLimit)
            var totals: [pid_t: (String, UInt64)] = [:]
            for process in candidates {
                let total = totals[process.owner] ?? (process.ownerName, 0)
                totals[process.owner] = (total.0, total.1 + process.footprint)
            }
            return totals.sorted { $0.value.1 > $1.value.1 }
                .prefix(limit)
                .map { pid, total in (pid, total.0, total.1) }
        }
    }

    /// A Mac like the one the report came from: an app, its helpers, and a
    /// same-named command-line process holding most of the memory cheaply.
    private static func machine() -> [Legacy.Process] {
        let gib: UInt64 = 1024 * 1024 * 1024
        return [
            Legacy.Process(pid: 13486, resident: 190 * 1024 * 1024, footprint: 143 * 1024 * 1024,
                           name: "Splash", owner: 13486, ownerName: "Splash"),
            Legacy.Process(pid: 13487, resident: 40 * 1024 * 1024, footprint: 14 * 1024 * 1024,
                           name: "Splash Graphics and Media", owner: 13486, ownerName: "Splash"),
            Legacy.Process(pid: 74424, resident: 340 * 1024 * 1024, footprint: 14 * gib + 3 * 1024 * 1024,
                           name: "splash", owner: 13486, ownerName: "Splash"),
            Legacy.Process(pid: 2316, resident: 800 * 1024 * 1024, footprint: 4 * gib,
                           name: "Safari", owner: 2316, ownerName: "Safari"),
        ]
    }

    static func run(_ suite: TestSuite) {
        suite.run("every process is asked for its own footprint") {
            let pids: [pid_t] = [400, 401, 402, 0, -7]
            let read: [pid_t: UInt64] = [400: 2_000, 401: 9_000, 402: 0]
            let samples = ProcessMemorySupport.samples(pids: pids) { read[$0] }
            suite.expect(samples.count == 2
                             && samples.contains(ProcessMemorySample(pid: 400, bytes: 2_000))
                             && samples.contains(ProcessMemorySample(pid: 401, bytes: 9_000)),
                         "a readable process is a row; zero, gone and non-positive pids are not: \(samples)")
        }

        suite.run("a process that dies during enumeration leaves no row") {
            // The answer arrives after the id was listed, so the process may be
            // gone by then. A row must not be left holding a zero, and the
            // sample must not stop at the failure.
            var asked: [pid_t] = []
            let samples = ProcessMemorySupport.samples(pids: [10, 11, 12]) { pid in
                asked.append(pid)
                return pid == 11 ? nil : UInt64(pid) * 1024
            }
            suite.expect(asked == [10, 11, 12], "the enumeration goes on past a process that vanished")
            expect(suite, samples.map(\.pid), [10, 12], "the vanished process is absent, not zero")
        }

        suite.run("the list is ordered by the figure it shows") {
            let samples = [ProcessMemorySample(pid: 1, bytes: 100),
                           ProcessMemorySample(pid: 2, bytes: 900),
                           ProcessMemorySample(pid: 3, bytes: 0),
                           ProcessMemorySample(pid: 4, bytes: 500)]
            expect(suite, ProcessMemorySupport.ranked(samples, limit: 10).map(\.pid), [2, 4, 1],
                   "heaviest first, and a zero footprint is no row")
            suite.expect(ProcessMemorySupport.ranked(samples, limit: 2).map(\.bytes) == [900, 500],
                         "the limit keeps the heaviest rows")
            let tied = [ProcessMemorySample(pid: 9, bytes: 700), ProcessMemorySample(pid: 6, bytes: 700)]
            expect(suite, ProcessMemorySupport.ranked(tied, limit: 10).map(\.pid), [6, 9],
                   "equal footprints keep a stable order, so a redraw does not shuffle rows")
        }

        suite.run("a process is one row, at its own pid") {
            // The report: the command-line `splash` holds 14 GiB and is
            // responsible to the app `Splash`.
            let processes = machine()
            let samples = processes.map { ProcessMemorySample(pid: $0.pid, bytes: $0.footprint) }
            let rows = ProcessMemorySupport.rows(samples: samples, limit: 15) { pid in
                processes.first { $0.pid == pid }?.name ?? "pid \(pid)"
            }
            let pids = rows.map(\.pid)
            let lead = rows.first
            let megabyte: UInt64 = 1024 * 1024
            let splashBytes: UInt64 = 14 * 1024 * megabyte + 3 * megabyte
            let appBytes: UInt64 = 143 * megabyte
            let appRows = rows.filter { $0.pid == 13486 }
            expect(suite, pids, [74424, 2316, 13486, 13487],
                   "the process that holds the memory leads, at its own pid")
            suite.expect(lead?.name == "splash", "the leader is the process, named as itself: \(lead?.name ?? "none")")
            suite.expect(lead?.bytes == splashBytes,
                         "its row is its own footprint, not an app's total: \(lead?.bytes ?? 0)")
            suite.expect(appRows.count == 1 && appRows.first?.bytes == appBytes,
                         "the app keeps its own row, at its own reading: \(appRows.count)")
            suite.expect(rows.count == processes.count,
                         "no process is folded into another: \(rows.count) rows")
        }

        suite.run("the accounting the report saw is gone") {
            let processes = machine()
            // The old rule, on the same sample: rank by resident size, keep the
            // first 120, add footprints up under the responsible pid.
            let legacy = Legacy.rows(processes, candidateLimit: 120, limit: 15)
            suite.expect(legacy.count == 2, "the old list showed one row per responsible app: \(legacy.count)")
            let splash = legacy.first(where: { $0.name == "Splash" })
            let megabyte: UInt64 = 1024 * 1024
            let gigabyte: UInt64 = 1024 * megabyte
            let summed: UInt64 = 143 * megabyte + 14 * megabyte + 14 * gigabyte + 3 * megabyte
            suite.expect(splash?.pid == 13486, "the old row carried the app's pid, not the memory holder's")
            suite.expect(splash?.bytes == summed,
                         "the old row added the helper, the app and a command-line process into one: \(String(describing: splash))")
            // A candidate limit of 120 rows hid the heavy process outright when
            // its resident pages ranked it below them.
            var crowded = processes
            for pid in pid_t(1_000)...pid_t(1_130) {
                crowded.append(Legacy.Process(pid: pid, resident: 1024 * 1024 * 1024, footprint: 20 * 1024 * 1024,
                                              name: "busy\(pid)", owner: pid, ownerName: "busy\(pid)"))
            }
            let crowdedLegacy = Legacy.rows(crowded, candidateLimit: 120, limit: 15)
            let legacyNames = crowdedLegacy.map(\.name)
            suite.expect(!legacyNames.contains("splash"),
                         "ranking by resident size hid the process whose footprint is far above it")
            let crowdedSamples = crowded.map { ProcessMemorySample(pid: $0.pid, bytes: $0.footprint) }
            let crowdedRows = ProcessMemorySupport.rows(samples: crowdedSamples, limit: 15) { pid in
                crowded.first { $0.pid == pid }?.name ?? "pid \(pid)"
            }
            let heaviest = crowdedRows.first.map { "\($0.name) \($0.bytes)" } ?? "none"
            suite.expect(crowdedRows.first?.name == "splash",
                         "asking every process for its footprint puts it first: \(heaviest)")
        }

        suite.run("a row survives a missing name, icon, or app identity") {
            // Names, icons and app identity are read from the process after the
            // row exists; a row is a pid and a figure, so none of them removes it.
            let samples = [ProcessMemorySample(pid: 700, bytes: 5_000), ProcessMemorySample(pid: 701, bytes: 4_000)]
            let namers: [(pid_t) -> String] = [{ "pid \($0)" }, { _ in "" }, { _ in "Unknown" }]
            for namer in namers {
                let rows = ProcessMemorySupport.rows(samples: samples, limit: 10, name: namer)
                suite.expect(rows.count == 2 && rows.map(\.pid) == [700, 701],
                             "an unnamed, iconless process is still a row")
            }
            suite.expect(ProcessMemorySupport.rows(samples: samples, limit: 10) { "pid \($0)" }
                             .map(\.name) == ["pid 700", "pid 701"],
                         "the pid is the fallback identity, and the row keeps it")
        }

        suite.run("the figure is written as a quantity of bytes") {
            suite.expect(ProcessMemorySupport.valueText(1024 * 1024 * 1024).hasSuffix("GB"),
                         "a gigabyte is labelled as one: \(ProcessMemorySupport.valueText(1024 * 1024 * 1024))")
            suite.expect(ProcessMemorySupport.valueText(14 * 1024 * 1024 * 1024) == "14 GB",
                         "whole values keep no decimals: \(ProcessMemorySupport.valueText(14 * 1024 * 1024 * 1024))")
            suite.expect(ProcessMemorySupport.valueText(0) == "0 B", "zero is not shown as a process's reading")
        }

        suite.run("the cache keeps rows to redraw") {
            suite.expect(ProcessMemorySupport.cachedRowLimit(for: 15) >= 15,
                         "the cache holds at least the rows the list shows")
            suite.expect(ProcessMemorySupport.cachedRowLimit(for: 200) >= 200,
                         "a wider request is not clamped below itself")
        }

        suite.run("the same calls on this Mac") {
            let pids = ProcessMemorySupport.processIDs()
            suite.expect(pids.count > 20 && pids.allSatisfy { $0 > 0 }, "libproc reports live pids: \(pids.count)")
            let own = ProcessMemorySupport.footprint(of: ProcessInfo.processInfo.processIdentifier)
            suite.expect((own ?? 0) > 0, "this process reports a footprint: \(String(describing: own))")
            suite.expect(ProcessMemorySupport.footprint(of: pid_t(Int32.max)) == nil,
                         "a pid that is not a process reports nothing")
            let rows = ProcessMemorySupport.rows(
                samples: ProcessMemorySupport.samples(pids: pids, footprint: ProcessMemorySupport.footprint(of:)),
                limit: 10) { pid in
                Self.appName(pid) ?? "pid \(pid)"
            }
            suite.expect(rows.count > 3 && rows.count <= 10, "the list fills on live processes: \(rows.count)")
            let bytes = rows.map(\.bytes)
            suite.expect(bytes == bytes.sorted(by: >), "the live rows come back heaviest first")
            suite.expect(Set(rows.map(\.pid)).count == rows.count, "no two rows share a pid")
        }
    }

    /// The app name a row would carry, if the pid belongs to a regular app. The
    /// test module has no app list, so nil stands for "no app identity", which is
    /// the case the row must survive.
    private static func appName(_ pid: pid_t) -> String? { nil }

    private static func expect(_ suite: TestSuite, _ actual: [pid_t], _ expected: [pid_t], _ message: String) {
        suite.expect(actual == expected, "\(message): got \(actual), expected \(expected)")
    }
}
