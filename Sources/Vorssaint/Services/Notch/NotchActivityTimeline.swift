// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// When each Live Activity became active, and the order that follows from it.
///
/// The section's order is the machine's history and not a table: the card that
/// started first is drawn first, and every activity that starts after it is
/// appended below. A hardcoded rank by activity type cannot say that — it puts
/// the timer above a song that started an hour ago, and it cannot tell the
/// second run of a timer from the first.
///
/// So each activity *instance* is recorded with the instant it became active
/// and the number issued to it:
///
/// * An activity already drawn keeps its record, and its place, whatever
///   starts beside it.
/// * An activity that starts is issued the next number and stands last.
/// * An activity that stops loses its record, and the records left keep their
///   order — no gap is left where it stood.
/// * An activity that stops and starts again is a new instance: it is issued a
///   fresh number and appended, because the machine has begun it again and
///   that is a later thing than what is already on the page.
/// * Several activities that become active in the same breath are issued their
///   numbers in the order they were offered, which is the callers' one
///   deterministic order, and the numbers break the tie when the clock does
///   not. Nothing here reads a dictionary.
struct NotchActivityInsertion: Equatable {
    /// One activity instance: what it is, when it began, and the number issued
    /// to it.
    struct Entry: Equatable {
        let id: String
        let activatedAt: Date
        /// Issued in order of activation, and the tie-break when two
        /// activations share an instant.
        let sequence: Int
    }

    /// The instances, oldest activation first.
    private(set) var entries: [Entry] = []
    /// The last number issued. Never reused, so an activity begun after a
    /// stop is always later than everything still on the page.
    private(set) var issued = 0

    /// `ids` is the page's candidate list in the order the caller decides it —
    /// the order is used only for activities activating together, which is the
    /// deterministic tie-break and nothing else.

    /// The ids, in the order the page draws them.
    var order: [String] { entries.map(\.id) }

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    func entry(for id: String) -> Entry? { entries.first { $0.id == id } }

    /// Records the activities that are active now, at `date`, and answers how
    /// many of them are new: the cards the page is about to gain, which is the
    /// page growing and not shrinking, and one movement must know which it is.
    @discardableResult
    mutating func register(_ ids: [String], at date: Date = Date()) -> Int {
        var seen = Set<String>()
        let active: [String] = ids.filter { seen.insert($0).inserted }
        let activeSet = Set(active)
        // An activity no longer running has no card, and no place kept for it.
        entries.removeAll { !activeSet.contains($0.id) }
        var begun = 0
        for id in active where entry(for: id) == nil {
            issued += 1
            entries.append(Entry(id: id, activatedAt: date, sequence: issued))
            begun += 1
        }
        // The record is kept in activation order. Appending is all a newcomer
        // can do: its number is the highest, and no existing record moves.
        entries.sort { first, second in
            first.activatedAt == second.activatedAt
                ? first.sequence < second.sequence
                : first.activatedAt < second.activatedAt
        }
        return begun
    }

    /// The page's items, in the order their activity became active.
    ///
    /// An item whose activity has no record yet keeps the caller's relative
    /// order, at the end: it has just appeared, and a card that has not been
    /// registered is the newest thing on the page.
    func ordering<Value>(_ items: [Value], id: (Value) -> String) -> [Value] {
        let ranks = Dictionary(entries.enumerated().map { ($0.element.id, $0.offset) },
                               uniquingKeysWith: { first, _ in first })
        let last = entries.count
        return items.enumerated()
            .sorted { left, right in
                let a = ranks[id(left.element)] ?? last
                let b = ranks[id(right.element)] ?? last
                return a == b ? left.offset < right.offset : a < b
            }
            .map(\.element)
    }
}
