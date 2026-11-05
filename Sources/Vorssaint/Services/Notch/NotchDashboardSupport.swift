// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// One part of the island's one-page dashboard.
///
/// The open island shows these parts together instead of one page at a time:
/// the levels, the players and the timer that are running, the monitoring
/// grid, and the way to the sections. A part is a section of one surface, not
/// a destination, so a song starting does not replace the dashboard any more
/// than a slider moving does. The order is fixed by `allCases` and the view
/// draws it in the same order, so a test can read the composition without
/// drawing it.
///
/// The page draws no headings. Each section is known by the shape it is made
/// of — the sliders, the cards, the grid, the circles — and a section's name
/// is spoken, not printed: it is the accessibility label of its content.
enum NotchDashboardSection: String, CaseIterable, Identifiable {
    case quickControls
    case calendar
    case liveActivities
    case systemMonitoring
    case explore

    var id: String { rawValue }

    /// The name of the section, used to label its content for the screen
    /// reader. Explore reuses the sections page's own title, so the label of
    /// the tiles and the page they open say the same thing.
    func title(_ language: AppLanguage) -> String {
        let strings = FeatureStrings.notch(language)
        switch self {
        case .quickControls: return strings.quickControlsTitle
        // The calendar's name is the section page's own, so the card on the
        // page and the page it opens answer to one word.
        case .calendar: return NotchModule.calendar.title(language)
        case .liveActivities: return strings.liveActivitiesTitle
        case .systemMonitoring: return strings.systemMonitoringTitle
        case .explore: return strings.sectionsTitle
        }
    }
}

/// A card inside the Live Activities section.
///
/// A player is a card of its own, named by the process that plays, so two
/// players at once are two cards and neither is the other's owner. The timer
/// is the section's other kind of card and keeps its own place.
enum NotchDashboardActivity: Hashable, Identifiable {
    case player(id: Int)
    case timer

    var id: String {
        switch self {
        case .player(let id): return "player.\(id)"
        case .timer: return "timer"
        }
    }
}

/// What one monitoring tile stands for. Kept apart from `MetricDetailKind`,
/// which lives with the panel's detail views, so the dashboard's composition
/// can be compiled and tested without them.
enum NotchDashboardMetric: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, battery, network, disk, power, fan, devices

    var id: String { rawValue }

    /// The detail a tile opens, spelled as the panel spells it. `devices`
    /// opens the connected devices detail, and Fan Control keeps its own name.
    var detailID: String { self == .devices ? "connectedDevices" : rawValue }
}

/// The dashboard's measurements, in points, shared by the page, the island's
/// size and the tests that check the size agrees with the page.
///
/// The page is the island's black surface with shapes on it: the sliders, each
/// activity in a card of its own, the monitoring tiles in four columns, the
/// sections as circles. Nothing is framed by a heading and no shape is nested
/// in a card of its own, which is what keeps a page of eight tiles and seven
/// circles from reading as one flat panel.
enum NotchDashboardLayout {
    /// A card of the page's own charcoal: the island's black under this much
    /// white, with the corners that make it one shape.
    static let cornerRadius: CGFloat = 12
    static let fillOpacity = 0.10
    /// The gap between sections, and between the cards of one section.
    static let sectionSpacing: CGFloat = 10
    static let cardSpacing: CGFloat = 8
    /// The page reads at this width at every preset, and narrows when a preset
    /// on a small display offers less.
    static let naturalContentWidth: CGFloat = 568

    // MARK: Quick Controls

    /// One row of the two levels, each a mark and a bar: the sliders the
    /// Controls page draws, made compact, and nothing else above the page.
    static let quickControlsHeight: CGFloat = 28
    static let quickControlsSpacing: CGFloat = 14
    /// A level's bar is narrow: the row is a control, not a meter to read. The
    /// mark that leads it keeps the width the mute button and the sun have.
    static let quickControlBarWidth: CGFloat = 122
    static let quickControlMarkWidth: CGFloat = 18
    /// How many levels sit at the page's leading edge. The first is volume and
    /// the last is brightness, and the row's middle is the page's own empty
    /// space, which is what puts the two levels at the two ends of the page.
    static let quickControlLeadingCount = 1
    static let quickControlGap: CGFloat = 24

    /// Whether the row's middle is empty: with one level there is nothing to
    /// push to the far side, and the row is that one control at the leading end.
    static func hasTrailingGap(levels: Int) -> Bool {
        levels > quickControlLeadingCount
    }

    // MARK: Calendar

    /// The month's grid at its shortest rows, the Calendar page's own grid, and
    /// the day's appointments read beside it. Six weeks and the names of the
    /// weekdays is what the grid needs; keeping it at that leaves the island
    /// room for the players, the readings and the sections below it.
    static let calendarGridHeight: CGFloat = NotchDashboardLayout.calendarMonthMinimumHeight
    /// Six weeks of days above the names of the weekdays: the shortest grid the
    /// Calendar page draws itself, so the card's grid is the page's grid and not
    /// a squashed copy of it.
    static let calendarMonthMinimumHeight: CGFloat = 110
    /// A week of days, not the page's whole width: the appointments of the day
    /// take the rest of the card.
    static let calendarGridWidth: CGFloat = 176
    static let calendarColumnSpacing: CGFloat = 14
    static let calendarHeaderHeight: CGFloat = 16
    /// The card's height: the grid, with the month and the day named above it
    /// in a row that also carries the way through the months.
    static var calendarCardHeight: CGFloat { calendarHeaderHeight + 6 + calendarGridHeight }

    // MARK: Live Activities

    /// A player's card holds its cover, its title, its position and its
    /// transport; a timer's card holds its mark, its phase, its clock and its
    /// pause. Both are the same height, so two cards of the section line up.
    static let activityCardHeight: CGFloat = 50
    static let activityArtwork: CGFloat = 34

    // MARK: System Monitoring

    static let metricColumns: Int = 4
    /// A tile is a label, a value and a meter, so it is taller than a row of
    /// text: the reading is the tile's own, and a tap opens it.
    static let metricTileHeight: CGFloat = 50
    static let metricSpacing: CGFloat = 8

    // MARK: Explore

    /// The sections as circles. Seven in a row puts every section on the page
    /// at once, in two rows for the sections a Mac usually has.
    static let exploreColumns: Int = 7
    static let exploreButton: CGFloat = 40
    static let exploreSpacing: CGFloat = 10

    /// The gap between the page's sections is the page's own; the cards inside
    /// a section sit closer, so a section reads as one group.
    static func stackHeight(_ cards: Int, cardHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        guard cards > 0 else { return 0 }
        return CGFloat(cards) * cardHeight + CGFloat(cards - 1) * spacing
    }

    /// Rows of a grid of `tileHeight` cells with `spacing` between the rows.
    static func gridHeight(rows: Int, tileHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        stackHeight(rows, cardHeight: tileHeight, spacing: spacing)
    }

    /// The metrics grid at its columns: four tiles in a row, two rows for the
    /// eight readings a Mac reports.
    static func metricsHeight(tiles: Int, columns: Int = metricColumns) -> CGFloat {
        gridHeight(rows: metricRows(tiles: tiles, columns: columns),
                   tileHeight: metricTileHeight, spacing: metricSpacing)
    }

    static func metricRows(tiles: Int, columns: Int = metricColumns) -> Int {
        guard tiles > 0 else { return 0 }
        let capacity = max(1, columns)
        return (tiles + capacity - 1) / capacity
    }

    /// The tiles split into rows, read left to right. The last row keeps its
    /// tiles at the width of the others and leaves the rest of the row empty,
    /// so an odd number of readings does not stretch a tile across the grid.
    static func metricRowRanges(tiles: Int, columns: Int = metricColumns) -> [Range<Int>] {
        guard tiles > 0 else { return [] }
        let capacity = max(1, columns)
        return (0..<metricRows(tiles: tiles, columns: capacity)).map { row in
            let start = row * capacity
            return start..<min(start + capacity, tiles)
        }
    }

    /// The activity cards, in order, with the gap between them. Every player
    /// has its own card; the timer has its own.
    static func liveActivitiesHeight(_ activities: [NotchDashboardActivity]) -> CGFloat {
        stackHeight(activities.count, cardHeight: activityCardHeight, spacing: cardSpacing)
    }

    /// The Explore circles at their columns, which is seven whenever the page
    /// is as wide as it wants to be.
    static func exploreColumns(width: CGFloat) -> Int {
        min(exploreColumns, max(1, Int(((width + exploreSpacing) / (exploreButton + exploreSpacing)).rounded(.down))))
    }

    static func exploreRows(count: Int, width: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        let columns = exploreColumns(width: width)
        return (count + columns - 1) / columns
    }

    static func exploreHeight(count: Int, width: CGFloat) -> CGFloat {
        gridHeight(rows: exploreRows(count: count, width: width),
                   tileHeight: exploreButton, spacing: exploreSpacing)
    }

    /// The whole dashboard: every section it shows, its content height, the
    /// gaps between them. The island sizes itself to this, so the page never
    /// scrolls for content that fits the display.
    static func sectionHeights(activities: [NotchDashboardActivity], calendar: Bool,
                               metrics: Int, exploreCount: Int, width: CGFloat) -> [CGFloat] {
        var heights: [CGFloat] = [quickControlsHeight]
        if calendar { heights.append(calendarCardHeight) }
        let live = liveActivitiesHeight(activities)
        if live > 0 { heights.append(live) }
        heights.append(metricsHeight(tiles: metrics, columns: metricColumns))
        heights.append(exploreHeight(count: exploreCount, width: width))
        return heights
    }

    static func contentHeight(activities: [NotchDashboardActivity], calendar: Bool, metrics: Int,
                              exploreCount: Int, width: CGFloat) -> CGFloat {
        let sections = sectionHeights(activities: activities, calendar: calendar, metrics: metrics,
                                      exploreCount: exploreCount, width: width)
        guard !sections.isEmpty else { return 0 }
        return sections.reduce(0, +) + sectionSpacing * CGFloat(sections.count - 1)
    }

    /// The volume and brightness sliders share one row, each as wide as its
    /// bar and its mark, and the row keeps the rest of the page empty.
    static func quickControlWidth(width: CGFloat) -> CGFloat {
        min(quickControlBarWidth + quickControlMarkWidth + 6,
            max(0, (width - quickControlsSpacing) / 2))
    }
}

/// The dashboard's composition and the routes that reach it. Every decision
/// here answers a question the island asks before it draws: which sections it
/// shows, which players and timers are in them, and what a click on a tile, a
/// menu bar indicator, or the way back leads to.
enum NotchDashboardSupport {
    /// The activity cards, in order: every player that is playing, in the
    /// order they were found, then the timer.
    ///
    /// The players are not capped and do not replace one another, and the
    /// timer is decided apart from them: a song ending leaves the timer's card
    /// where it was, and a timer ending leaves every player's card where it
    /// was. Two players at once are two cards.
    static func activities(players: [Int], timer: Bool) -> [NotchDashboardActivity] {
        var visible = players.map { NotchDashboardActivity.player(id: $0) }
        if timer { visible.append(.timer) }
        return visible
    }

    /// The sections in the order the page draws them. The levels, the calendar,
    /// the grid and the way to the sections are the page's own; the activity
    /// section is only there when something runs, so an idle island is four
    /// sections and not an empty card.
    static func sections(activities: [NotchDashboardActivity], calendar: Bool) -> [NotchDashboardSection] {
        var sections: [NotchDashboardSection] = [.quickControls]
        if calendar { sections.append(.calendar) }
        if !activities.isEmpty { sections.append(.liveActivities) }
        sections.append(.systemMonitoring)
        sections.append(.explore)
        return sections
    }

    /// The calendar card belongs to a page that is wide enough to set a week of
    /// days and the day's appointments side by side. Narrower than that the
    /// page keeps its other sections, as it does when the section is off.
    static func showsCalendar(section: Bool, width: CGFloat) -> Bool {
        section && width >= NotchDashboardLayout.calendarGridWidth
            + NotchDashboardLayout.calendarColumnSpacing + 150
    }

    /// The tiles in the grid, in reading order, with only the ones the Mac can
    /// report. A metric that is unavailable is left out; the grid never shows
    /// a tile whose detail would open on nothing.
    static func tiles(available: (NotchDashboardMetric) -> Bool) -> [NotchDashboardMetric] {
        NotchDashboardMetric.allCases.filter(available)
    }

    /// Whether the open island is the dashboard: nothing of its own is in
    /// front, and it was not opened at a section, a detail, the app panel,
    /// the gallery or the Command Bar.
    static func showsDashboard(dashboard: Bool, expanded: Bool, metric: Bool, appPanel: Bool,
                               sections: Bool, commandBar: Bool, modules: Bool) -> Bool {
        dashboard && expanded && !metric && !appPanel && !sections && !commandBar && modules
    }

    /// Opening the island with nothing asked for — the pointer resting on it,
    /// a click, the toggle — shows the dashboard. A section, a detail, the
    /// panel, the gallery and the Command Bar each name where they go, and the
    /// island goes there.
    static func opensDashboard(module: Bool, metric: Bool, appPanel: Bool, sections: Bool) -> Bool {
        !module && !metric && !appPanel && !sections
    }

    /// A menu bar indicator's click leads straight to its detail, with the
    /// island collapsed, closed, or showing something else: one click, one
    /// detail. A metric in the menu bar is a reading, so its indicator leads
    /// to that reading's detail and not to the app's panel, whatever the panel
    /// is set to open at. It leads to the panel instead when the island does
    /// not run or has no System page, and nowhere when the metric itself is
    /// off, which is how the menu bar item already behaves.
    static func menuBarOpensDetail(islandRuns: Bool, systemPage: Bool, metricAvailable: Bool) -> Bool {
        metricAvailable && islandRuns && systemPage
    }

    /// Where the way back from a detail leads: always the dashboard, which is
    /// what the grid sits on.
    static func returnsToDashboard(fromDetail: Bool) -> Bool { fromDetail }

    /// The way back from a page the person reached through the page's own marks,
    /// and from the gallery the marks open, is the dashboard under them. The app
    /// panel is a surface of its own with its own way out, and the dashboard
    /// needs no way back to itself. The sections page is never the destination
    /// a page leads back to, because it is the page the person just left.
    static func returnsToDashboard(sectionPage: Bool, appPanel: Bool, dashboard: Bool) -> Bool {
        sectionPage && !appPanel && !dashboard
    }

    /// `count` items in rows of at most `columns`, read left to right. The
    /// rows are filled from the left and the last row keeps its items at the
    /// width of the others, which is how the Explore circles and the tiles
    /// both lay out.
    static func rows(count: Int, columns: Int) -> [Range<Int>] {
        let capacity = max(1, columns)
        guard count > 0 else { return [] }
        return (0...((count - 1) / capacity)).map { row in
            let start = row * capacity
            return start..<min(start + capacity, count)
        }
    }
}
