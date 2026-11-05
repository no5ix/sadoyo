// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One process's memory, as the per-process list reports it.
struct ProcessMemorySample: Equatable {
    let pid: pid_t
    let bytes: UInt64
}

/// One row of that list: the process, named, and what it holds.
struct ProcessMemoryRow: Equatable, Identifiable {
    let pid: pid_t
    let name: String
    let bytes: UInt64

    var id: pid_t { pid }
}

/// Enumerating and ranking processes for the memory list.
///
/// The list answers one question in the same way Activity Monitor's Memory
/// column does: how much memory does *this process* hold, measured as the
/// kernel's physical footprint (`ri_phys_footprint`). Three things follow,
/// and each of them is the reason an earlier version of the list was wrong:
///
/// * Every process is asked, through libproc. Ranking processes by `ps`'s
///   resident size and reading the footprint of only the first rows hid a
///   process whose footprint is far larger than its resident pages — a
///   compressed, purgeable, or I/O-mapped working set is cheap in resident
///   pages and expensive in footprint, and one such process outranked every
///   row the list had.
/// * A row is one process. Footprints are not added across a process
///   hierarchy: the responsibility API bills a helper, a command-line tool
///   launched from an app, and a same-named sibling to the app it resolves
///   to, so summing them reported a figure Activity Monitor shows for no
///   process, under the responsible app's name and pid, while the process
///   that held the memory disappeared from the list.
/// * Processes the current user may not read are left out, because there is
///   no figure to show. Activity Monitor reads them as a privileged
///   collector; the app does not ask for that, so its list can be shorter
///   than Activity Monitor's by those rows, and says nothing about them.
enum ProcessMemorySupport {
    /// The kernel's physical footprint of a process, the figure Activity
    /// Monitor's Memory column shows. Nil when the process is gone or its
    /// owner is not readable: a process that dies during enumeration drops
    /// out of the list rather than reporting a zero.
    static func footprint(of pid: pid_t) -> UInt64? {
        guard pid > 0 else { return nil }
        var info = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
            }
        }
        guard status == 0, info.ri_phys_footprint > 0 else { return nil }
        return info.ri_phys_footprint
    }

    /// Every process id libproc reports, including the ones this process may
    /// not read; `footprint(of:)` decides what can be shown.
    static func processIDs() -> [pid_t] {
        let estimated = max(1, Int(proc_listallpids(nil, 0)))
        var ids = [pid_t](repeating: 0, count: estimated + 64)
        let count = ids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(ids.prefix(min(Int(count), ids.count))).filter { $0 > 0 }
    }

    /// The samples for `pids`, skipping what has no readable footprint. A
    /// process that exits between the enumeration and the read is simply
    /// absent, so the list never carries a row with nothing behind it.
    static func samples(pids: [pid_t], footprint: (pid_t) -> UInt64?) -> [ProcessMemorySample] {
        pids.compactMap { pid in
            guard let bytes = footprint(pid), bytes > 0 else { return nil }
            return ProcessMemorySample(pid: pid, bytes: bytes)
        }
    }

    /// Heaviest first, the pid breaking a tie so a redraw of the same sample
    /// keeps the same order. Zero-footprint rows are dropped.
    static func ranked(_ samples: [ProcessMemorySample], limit: Int) -> [ProcessMemorySample] {
        samples.filter { $0.bytes > 0 }
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.pid < $1.pid }
            .prefix(max(0, limit))
            .map { $0 }
    }

    /// The rows the list shows: one process, its name, its own footprint.
    /// Nothing is merged, so the pid a row names is the pid the memory belongs
    /// to, which is the pid the row's force-quit acts on.
    static func rows(samples: [ProcessMemorySample], limit: Int, name: (pid_t) -> String) -> [ProcessMemoryRow] {
        ranked(samples, limit: limit).map { sample in
            ProcessMemoryRow(pid: sample.pid, name: name(sample.pid), bytes: sample.bytes)
        }
    }

    /// Candidates kept in the cache, so the list a later open shows is the
    /// same list and the identity a force-quit needs stays bound for them.
    static func cachedRowLimit(for limit: Int) -> Int {
        max(limit, 60)
    }

    /// A footprint as the list writes it.
    static func valueText(_ bytes: UInt64) -> String {
        MetricFormat.bytes(bytes)
    }
}
