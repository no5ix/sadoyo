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

/// The marks a timer card offers, in the row order the page draws them.
enum NotchDashboardTimerControl: Equatable {
    case reset
    case pause
    case close
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
    /// The players one page carries, the one in effect among them.
    static let maxPlayers: Int = 4

    // MARK: Quick Controls

    /// The levels sit in the island's top row, beside the camera where the
    /// camera is, as the Controls page puts them there: the first at the row's
    /// leading edge and the last at its trailing edge. The row is the island's
    /// own header, so its height is the header's and not one of the page's.
    static let quickControlsHeight: CGFloat = 28
    static let quickControlsSpacing: CGFloat = 14
    /// A level's bar is narrow: the row is a control, not a meter to read. The
    /// mark that leads it keeps the width the mute button and the sun have, and
    /// the chooser that picks the output or the display keeps the chevron's.
    static let quickControlBarWidth: CGFloat = 122
    /// A narrow row shortens the bar before it drops the chooser, which is how
    /// an output is picked and a display chosen from the top of the island.
    static let quickControlBarMinimumWidth: CGFloat = 56
    static let quickControlMarkWidth: CGFloat = 18
    static let quickControlChooserWidth: CGFloat = 16
    /// The parts of one level, with the gaps the Controls page keeps between them.
    static var quickControlNaturalWidth: CGFloat {
        quickControlMarkWidth + 6 + quickControlBarWidth + 6 + quickControlChooserWidth
    }
    static var quickControlMinimumWidth: CGFloat {
        quickControlMarkWidth + 6 + quickControlBarMinimumWidth + 6 + quickControlChooserWidth
    }

    /// A row of levels is the page's top only when the Mac has a level to show:
    /// with every level hidden the island keeps its bare top, as it did.
    static func showsLevelRow(levels: Int) -> Bool { levels > 0 }

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
    static let calendarHeaderGap: CGFloat = 4
    /// The card's edge to its content, the same on every side: the month's grid
    /// and the day's appointments sit the same distance from the card's outline.
    static let calendarCardPadding: CGFloat = 8
    /// The card is as tall as what it holds: the edge, the month's name, the
    /// grid, and the edge again. Nothing is left empty at the bottom, and
    /// nothing of the grid is cut off at the last week.
    static var calendarCardHeight: CGFloat {
        calendarCardPadding * 2 + calendarHeaderHeight + calendarHeaderGap + calendarGridHeight
    }

    // MARK: Live Activities

    /// The player in effect carries its cover, its title, its position and its
    /// transport, so its card is the tall one.
    static let activityCardHeight: CGFloat = 75
    static let activityArtwork: CGFloat = 44
    /// Every player's card carries its own cover, its own title and artist, its
    /// own position and its own transport, so every card is as tall as the first
    /// - only its type is smaller. Two players are two cards of one height, and
    /// the page asks the island for the height they all need.
    static let playerCardHeight: CGFloat = activityCardHeight
    /// The card's edge to its content, on every side alike. The timer's card is
    /// as tall as its clock, so its top edge is as far from its words as its
    /// leading edge is, and a card of one line is not padded at the top.
    static let activityCardPadding: CGFloat = 10
    /// A card that carries one line of its own, with the edge on every side.
    static var timerCardHeight: CGFloat { activityCardPadding * 2 + activityArtwork - 12 }
    /// The timer card's two controls are one control: the same box, the same
    /// circle, the same place in the row. The pause is filled with the timer's
    /// colour because it holds the session; the close is quiet and lights that
    /// same circle when the pointer is on it. The circle is the button: its
    /// plate, its highlight and its hit area are all of it, as on the player's
    /// transport, so the close of a card is the pause's equal in every way.
    static let timerControlSide: CGFloat = 28
    static var timerControlCorner: CGFloat { timerControlSide / 2 }
    static let timerControlGap: CGFloat = 8

    /// The marks a timer card offers, in their row order: reset first, then the
    /// mark that holds the clock, then the close that ends the session. A
    /// countdown can be started again; a Pomodoro cycle and a stopwatch keep the
    /// two marks they have always had, because a Pomodoro's phases are started
    /// by the user and a stopwatch has no length to restore.
    static func timerCardControls(countdown: Bool) -> [NotchDashboardTimerControl] {
        countdown ? [.reset, .pause, .close] : [.pause, .close]
    }
    /// A player card's transport: three marks of the size the primary card's
    /// compact transport uses, in the same circle, so a player's row and the
    /// player above it read as the same control.
    static let transportMarkSide: CGFloat = 22
    static var transportCorner: CGFloat { transportMarkSide / 2 }
    /// The three marks sit in a row of their own, at one gap, on every card.
    static let transportSpacing: CGFloat = 6
    /// The mark of the app that plays, and the shape it is a button of: the
    /// artwork of the player in effect and the icon of the others are both a
    /// way to that app.
    static let appMarkSide: CGFloat = 26
    static let appMarkCorner: CGFloat = 6

    // MARK: System Monitoring

    static let metricColumns: Int = 4
    /// A tile is a label, a value and a meter, so it is taller than a row of
    /// text: the reading is the tile's own, and a tap opens it. The tile is
    /// measured so its value is read at a glance, not crowded against its edge.
    static let metricTileHeight: CGFloat = 64
    static let metricSpacing: CGFloat = 8
    /// The tile's edge to its reading, the same on every side.
    static let metricTilePadding: CGFloat = 10

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

    /// The activity cards, in order, with the gap between them: the player in
    /// effect at its full height, the other players at one row, the timer at its
    /// clock. This is the height the page asks the island for, so the sections
    /// below - the readings and the way to the sections - are on the page and
    /// not under a scroll.
    static func liveActivitiesHeight(_ activities: [NotchDashboardActivity],
                                     primaryPlayerID: Int? = nil) -> CGFloat {
        activities.reduce(0) { total, activity in
            total + activityHeight(activity, primaryPlayerID: primaryPlayerID)
        } + cardSpacing * CGFloat(max(0, activities.count - 1))
    }

    static func activityHeight(_ activity: NotchDashboardActivity, primaryPlayerID: Int? = nil) -> CGFloat {
        switch activity {
        case .player(let id): return id == primaryPlayerID ? activityCardHeight : playerCardHeight
        case .timer: return timerCardHeight
        }
    }

    /// The players the page shows, in the order their cards are drawn: the one
    /// in effect leads, and the others follow in the adapter's own order, by
    /// process. Nothing about a card's control is in this order, and a card is
    /// never listed twice: using a control on the card below the first sends
    /// that player a command, and the cards stay where they were.
    static func playerIDs(sources: [NotchPlaybackSource], inEffectPID: Int?,
                          limit: Int = NotchDashboardLayout.maxPlayers) -> [Int] {
        var ids: [Int] = []
        if let inEffectPID, inEffectPID > 0, sources.contains(where: { Int($0.pid) == inEffectPID }) {
            ids.append(inEffectPID)
        }
        for source in sources where source.isPlaying || source.hasTrack {
            let pid = Int(source.pid)
            guard pid > 0, !ids.contains(pid) else { continue }
            ids.append(pid)
            if ids.count >= limit { break }
        }
        return ids
    }

    /// Whether a card's transport can reach the player of that card. A command
    /// for a player that is not the one in effect is scoped to the recording that
    /// player reports; a player that reports no recording of its own cannot be
    /// sent one, because the command would land on the player the system is
    /// playing. Such a card therefore shows no marks that would do nothing: it
    /// keeps its cover, its words, its position, and its way to the app.
    static func commandsReach(player: NotchPlaybackSource) -> Bool {
        player.hasTrack && player.itemIdentifier != nil
    }

    /// The page a reading's detail opens over, which is the reading's own page
    /// whatever surface it was opened from. A reading's menu bar indicator and
    /// the same reading's card on the System page are one route, and the panel
    /// is never between a reading and its page.
    static func showsMetricDetail(metricSelected: Bool, appPanel: Bool) -> Bool { metricSelected }

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
    /// The page's own sections, in the order it draws them, at their heights.
    /// The levels are not among them: they are the island's top row, which the
    /// island's own geometry measures, so the page is as tall as the cards,
    /// the grid and the circles it holds, and no more.
    static func sectionHeights(activities: [NotchDashboardActivity], calendar: Bool,
                               metrics: Int, exploreCount: Int, width: CGFloat,
                               primaryPlayerID: Int? = nil) -> [CGFloat] {
        var heights: [CGFloat] = []
        if calendar { heights.append(calendarCardHeight) }
        let live = liveActivitiesHeight(activities, primaryPlayerID: primaryPlayerID)
        if live > 0 { heights.append(live) }
        heights.append(metricsHeight(tiles: metrics, columns: metricColumns))
        heights.append(exploreHeight(count: exploreCount, width: width))
        return heights
    }

    /// The tallest page the island draws on a display of the given height: the
    /// display less the island's chrome - the screen's own limit, the row of
    /// levels at its top, and the page's edges. The page is measured against
    /// this, so the readings and the way to the sections are on the page by
    /// default and not under a scroll a person has to find.
    static func maxPageHeight(screenHeight: CGFloat) -> CGFloat {
        // The one ceiling every page shares: four fifths of the display, and
        // never more than the room the display keeps under its menu bar and
        // safe area. Past it the page scrolls to its last section.
        let panel = min(screenHeight * NotchPanelSizing.maximumHeightFraction,
                        screenHeight - NotchGeometry.displayEdgeReserve)
        return panel - quickControlsHeight - 20
    }

    static func contentHeight(activities: [NotchDashboardActivity], calendar: Bool, metrics: Int,
                              exploreCount: Int, width: CGFloat, primaryPlayerID: Int? = nil) -> CGFloat {
        let sections = sectionHeights(activities: activities, calendar: calendar, metrics: metrics,
                                      exploreCount: exploreCount, width: width,
                                      primaryPlayerID: primaryPlayerID)
        guard !sections.isEmpty else { return 0 }
        return sections.reduce(0, +) + sectionSpacing * CGFloat(sections.count - 1)
    }

    /// What one level takes in the row: its mark, its bar and its chooser. The
    /// row's side is what the island's geometry gives it beside the camera, so
    /// the bar takes what is left after the mark and the chooser, down to the
    /// width it narrows to before the chooser goes.
    static func quickControlWidth(width: CGFloat) -> CGFloat {
        min(quickControlNaturalWidth, max(quickControlMinimumWidth, width))
    }
}

/// Where a menu bar indicator's click leads, and why.
///
/// A metric in the menu bar is a reading, so its indicator leads to that
/// reading's detail. The island is the first surface for it. Where the island
/// cannot take the click, the app's panel opens the same detail, as a page of
/// its own, and never merely the section the reading sits in: one click on a
/// reading always lands on that reading.
enum NotchMenuBarRoute: Equatable {
    /// The island opens, at the metric's detail.
    case islandDetail
    /// The app's panel opens, at the metric's detail.
    case panelDetail
    /// Nothing opens: the metric is off, so its indicator has no reading.
    case nothing

    /// The name the menu bar writes to the log.
    var logName: String {
        switch self {
        case .islandDetail: return "island-detail"
        case .panelDetail: return "panel-detail"
        case .nothing: return "none"
        }
    }
}

/// The dashboard's composition and the routes that reach it. Every decision
/// here answers a question the island asks before it draws: which sections it
/// shows, which players and timers are in them, and what a click on a tile, a
/// menu bar indicator, or the way back leads to.
enum NotchDashboardSupport {

    /// Where one click on a player card's control goes: to the player the click
    /// was aimed at, by process and bundle, and to no other. The command does
    /// not ask which player the page follows, so the card above stays the card
    /// above. A player the page no longer reports, a card with no process, and a
    /// control that has no per-player form are all refused.
    enum PlayerCommand: Equatable {
        case send(pid: Int32, bundleIdentifier: String, action: NotchPlayerAction)
        case refuse
    }

    static func playerCommand(sourcePID: Int, bundleIdentifier: String, action: NotchPlayerAction?,
                              inEffectPID: Int, reported: Bool) -> PlayerCommand {
        guard reported, sourcePID > 0, let action,
              NotchPlaybackCommand.validIdentifier(bundleIdentifier) else { return .refuse }
        return .send(pid: Int32(sourcePID), bundleIdentifier: bundleIdentifier, action: action)
    }

    /// How a card's mark opens the app that plays: a process that is running is
    /// brought forward, and a player that is not running is opened by the
    /// bundle the adapter named for it. A card with neither is asked nothing.
    enum AppOpening: Equatable {
        case activate(pid: Int)
        case open(bundleIdentifier: String)
        case none
    }

    static func appOpening(pid: Int, isRunning: Bool, bundleIdentifier: String?) -> AppOpening {
        if pid > 0, isRunning { return .activate(pid: pid) }
        if let bundleIdentifier, !bundleIdentifier.isEmpty { return .open(bundleIdentifier: bundleIdentifier) }
        return .none
    }

    /// The activity cards, in order: every player that is playing, in the
    /// order they were found, then the timer.
    ///
    /// The players are not capped and do not replace one another, and the
    /// timer is decided apart from them: a song ending leaves the timer's card
    /// where it was, and a timer ending leaves every player's card where it
    /// was. Two players at once are two cards.
    /// The page's activities: the players the system reports, in order, then the
    /// timer, which is decided apart from every one of them.
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

    /// Where the indicator's click goes: the island's detail when the island
    /// can take it and has a System page to put the reading on; the app's
    /// panel, at the same detail, when it cannot; nowhere when the metric
    /// itself is off, which is how the menu bar item already behaves.
    static func menuBarRoute(islandRuns: Bool, systemPage: Bool, metricAvailable: Bool) -> NotchMenuBarRoute {
        guard metricAvailable else { return .nothing }
        return islandRuns && systemPage ? .islandDetail : .panelDetail
    }

    /// Why a click did not reach the island, in the words the menu bar writes
    /// to the log: every condition that failed, by the name the island gives
    /// it. A click that the island takes has no reason, and `nil` says so.
    static func menuBarRouteReason(_ conditions: [(name: String, passed: Bool)]) -> String? {
        let failed = conditions.filter { !$0.passed }.map { $0.name }
        return failed.isEmpty ? nil : failed.joined(separator: ",")
    }

    /// With the island's panel the surface on screen, the metric's detail is
    /// the panel's page: the panel reads the focus and shows the reading, and
    /// the island's own detail page would only sit behind it.
    static func metricShowsInAppPanel(appPanelOpen: Bool) -> Bool { appPanelOpen }

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
