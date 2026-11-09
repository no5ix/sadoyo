// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// The island's one calendar display state: the month the grid is built
/// around, and the day the appointments are read for.
///
/// The dashboard's card and the Calendar page are two drawings of one
/// calendar, so they share this state. The month and the day belong to the
/// island and not to a page: leaving the page and coming back finds the month
/// and the day where they were, and no view keeps a month of its own. The
/// event read follows the month shown here, so both views draw from one list
/// of events and a day carries the same marks in each of them.
///
/// The rules of what a day holds, and of the spans a read covers, are
/// `NotchCalendarSupport`'s; this only moves the two values.
final class NotchCalendarDisplay: ObservableObject {
    /// The island's own display. A preview in Settings builds one of its own
    /// so browsing a month there does not move what the island shows.
    static let shared = NotchCalendarDisplay()

    /// The month the grid is built around.
    @Published private(set) var focus: Date
    /// The day the appointments are read for, or nil for the coming week.
    @Published private(set) var selectedDay: Date?

    init(now: Date = Date(), calendar: Calendar = .current) {
        focus = calendar.startOfDay(for: now)
    }

    /// The day the appointments are read for: the one picked, or today.
    var selectedDate: Date {
        selectedDay ?? Calendar.current.startOfDay(for: Date())
    }

    /// Build the grid around another day, keeping the day being read.
    func show(_ date: Date) {
        setFocus(date)
    }

    /// Picking a day reads that day, in the month that holds it.
    func select(_ day: Date) {
        selectedDay = Calendar.current.startOfDay(for: day)
        setFocus(day)
    }

    /// Back to the coming week, read from today.
    func showWeek(now: Date = Date()) {
        selectedDay = nil
        setFocus(now)
    }

    /// A week earlier or later, with that week's day read: the strip steps by
    /// week, as Calendar's own week view does.
    func moveWeek(_ offset: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset * 7, to: focus) else { return }
        selectedDay = Calendar.current.startOfDay(for: date)
        setFocus(date)
    }

    /// A month earlier or later. The day being read follows the month, kept to
    /// a day that month has, so a card and a page never read a day the grid no
    /// longer holds; with no day picked, the coming week stays the reading.
    func moveMonth(_ offset: Int) {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .month, for: focus)?.start,
              let month = calendar.date(byAdding: .month, value: offset, to: start) else { return }
        setFocus(month)
        if let day = selectedDay { selectedDay = move(day, to: month) }
    }

    /// The month today is in, and today's appointments.
    func goToday(now: Date = Date()) {
        setFocus(now)
        selectedDay = Calendar.current.startOfDay(for: now)
    }

    /// The month's own day of the month, moved to a month that has it: the
    /// 31st of March becomes the 30th of April, and February keeps its 29th.
    private func move(_ day: Date, to month: Date) -> Date? {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return nil }
        let last = calendar.range(of: .day, in: .month, for: month)?.count ?? 31
        let dayOfMonth = min(calendar.component(.day, from: day), last)
        return calendar.date(byAdding: .day, value: dayOfMonth - 1, to: interval.start)
    }

    /// A month is read once, not per day: the grid's six weeks are read for
    /// any of its days, so moving within a month changes no read. The focus is
    /// kept at the day's start so a day asked twice is one value.
    private func setFocus(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        guard focus != day else { return }
        focus = day
    }
}
