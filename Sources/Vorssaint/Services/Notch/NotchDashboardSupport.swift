// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// One part of the island's one-page dashboard.
///
/// The open island shows these parts together instead of one page at a time:
/// the levels, the activities that are running, the monitoring grid and the
/// way to the sections. A part is a section of one surface, not a destination,
/// so a song starting does not replace the dashboard any more than a slider
/// moving does. The order is fixed by `allCases` and the view draws it in the
/// same order, so a test can read the composition without drawing it.
enum NotchDashboardSection: String, CaseIterable, Identifiable {
    case quickControls
    case liveActivities
    case systemMonitoring
    case explore

    var id: String { rawValue }

    /// The name the page shows above the section. Explore reuses the sections
    /// page's own title, so the label above the tiles and the page they open
    /// say the same thing.
    func title(_ language: AppLanguage) -> String {
        let strings = FeatureStrings.notch(language)
        switch self {
        case .quickControls: return strings.quickControlsTitle
        case .liveActivities: return strings.liveActivitiesTitle
        case .systemMonitoring: return strings.systemMonitoringTitle
        case .explore: return strings.sectionsTitle
        }
    }
}

/// An activity card inside the Live Activities section.
enum NotchDashboardActivity: String, CaseIterable, Identifiable {
    case nowPlaying
    case timer

    var id: String { rawValue }
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
/// The sections are cards of one shape on the island's black: a charcoal fill
/// (the island's black under white at `fillOpacity`), the same corner radius,
/// the same insets, and an even gap that keeps two cards from reading as one
/// surface. Heights are the content's own height, so a section's card is
/// `sectionHeight(_:)` — the page and the island's height always agree because
/// both add the insets here.
enum NotchDashboardLayout {
    static let cornerRadius: CGFloat = 14
    static let sectionSpacing: CGFloat = 8
    /// Top and bottom inside a card; the sides sit a little wider, as the
    /// controls in them need the room a slider's thumb reaches.
    static let sectionPadding: CGFloat = 8
    static let sectionInset: CGFloat = 10
    /// The island's black under this much white: a charcoal card that separates
    /// from the surface and from the card above and below it.
    static let fillOpacity = 0.13
    static let hairlineOpacity = 0.07
    /// A card this wide reads like the reference layout at every preset, and
    /// the island narrows to it under a preset that offers more.
    static let naturalContentWidth: CGFloat = 430

    /// A section names itself above its content, so four cards stacked read as
    /// four parts of one page. The label's line and its gap are part of the
    /// card's height, which is why the island sizes itself through this file.
    static let headerHeight: CGFloat = 11
    static let headerSpacing: CGFloat = 5
    static let quickControlsHeight: CGFloat = 28
    static let activityCardSpacing: CGFloat = 6
    /// The Now Playing card is as tall as its cover, which holds the title,
    /// the artist and the song's position beside it, and the transport at its end.
    static let nowPlayingArtwork: CGFloat = 36
    static let nowPlayingHeight: CGFloat = 40
    static let timerHeight: CGFloat = 24
    static let metricColumns: Int = 4
    static let metricTileHeight: CGFloat = 30
    static let metricSpacing: CGFloat = 6
    static let exploreButton: CGFloat = 30
    static let exploreSpacing: CGFloat = 8

    /// A card around content of `content` points.
    static func sectionHeight(_ content: CGFloat) -> CGFloat {
        max(0, content) + sectionPadding * 2
    }

    /// A card that names its section: the label's line and its gap join the
    /// content the card has to hold.
    static func sectionHeight(_ content: CGFloat, header: Bool) -> CGFloat {
        sectionHeight(content + (header ? headerHeight + headerSpacing : 0))
    }

    /// Rows of a grid of `tileHeight` cells with `spacing` between the rows.
    static func gridHeight(rows: Int, tileHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * tileHeight + CGFloat(rows - 1) * spacing
    }

    /// The metrics grid at its columns. Tiles of one width share the section,
    /// so its height is the rows' height.
    static func metricsHeight(tiles: Int, columns: Int = metricColumns) -> CGFloat {
        gridHeight(rows: metricRows(tiles: tiles, columns: columns),
                   tileHeight: metricTileHeight, spacing: metricSpacing)
    }

    /// Rows as even as they can be: nine tiles at four columns are three rows
    /// of three, not a full row and a single tile, so a section with an extra
    /// tile stays balanced.
    static func metricRows(tiles: Int, columns: Int = metricColumns) -> Int {
        guard tiles > 0 else { return 0 }
        let capacity = max(1, columns)
        let rows = (tiles + capacity - 1) / capacity
        return rows
    }

    /// The tiles split into rows, read left to right.
    static func metricRowRanges(tiles: Int, columns: Int = metricColumns) -> [Range<Int>] {
        let rows = metricRows(tiles: tiles, columns: columns)
        guard tiles > 0, rows > 0 else { return [] }
        let base = tiles / rows
        let remainder = tiles % rows
        return (0..<rows).map { row in
            let start = row * base + min(row, remainder)
            return start..<(start + base + (row < remainder ? 1 : 0))
        }
    }

    /// The activity cards, in order, with the gap between them.
    static func liveActivitiesHeight(_ activities: [NotchDashboardActivity]) -> CGFloat {
        guard !activities.isEmpty else { return 0 }
        let card = activities.reduce(CGFloat(0)) { total, activity in
            total + (activity == .nowPlaying ? nowPlayingHeight : timerHeight)
        }
        return card + activityCardSpacing * CGFloat(activities.count - 1)
    }

    /// How many circular Explore buttons fit in `width`.
    static func exploreColumns(width: CGFloat) -> Int {
        max(1, Int(((width + exploreSpacing) / (exploreButton + exploreSpacing)).rounded(.down)))
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

    /// The whole dashboard: every section it shows, its content heights, the
    /// gap between sections. The island sizes itself to this, so the page never
    /// has to scroll for content that fits the display.
    static func contentHeight(activities: [NotchDashboardActivity], metrics: Int,
                              exploreCount: Int, width: CGFloat) -> CGFloat {
        let sections = sectionHeights(activities: activities, metrics: metrics,
                                      exploreCount: exploreCount, width: width)
        guard !sections.isEmpty else { return 0 }
        return sections.reduce(0, +) + sectionSpacing * CGFloat(sections.count - 1)
    }

    /// One height per section, in the order the page draws them.
    static func sectionHeights(activities: [NotchDashboardActivity], metrics: Int,
                               exploreCount: Int, width: CGFloat) -> [CGFloat] {
        var heights: [CGFloat] = [sectionHeight(quickControlsHeight, header: true)]
        let live = liveActivitiesHeight(activities)
        if live > 0 { heights.append(sectionHeight(live, header: true)) }
        heights.append(sectionHeight(metricsHeight(tiles: metrics, columns: metricColumns), header: true))
        heights.append(sectionHeight(exploreHeight(count: exploreCount, width: width), header: true))
        return heights
    }

    /// The volume and brightness sliders share one row, each taking half of it
    /// less the gap between them.
    static func quickControlWidth(width: CGFloat) -> CGFloat {
        max(0, (width - sectionInset * 2 - sectionSpacing) / 2)
    }
}

/// The dashboard's composition and the routes that reach it. Every decision
/// here answers a question the island asks before it draws: which sections it
/// shows, which activities are in them, and what a click on a tile, a menu bar
/// indicator, or the way back leads to.
enum NotchDashboardSupport {
    /// The player shows while a song is known, playing or paused; a stopped
    /// player leaves nothing to show. A timer shows while a session runs,
    /// waits, or has just finished.
    ///
    /// The two are decided apart, in that order, and never replace each other:
    /// `music: true, timer: false` and `music: true, timer: true` are two
    /// states of one section, and a song ending leaves the timer's card where
    /// it was.
    static func activities(music: Bool, timer: Bool) -> [NotchDashboardActivity] {
        var visible: [NotchDashboardActivity] = []
        if music { visible.append(.nowPlaying) }
        if timer { visible.append(.timer) }
        return visible
    }

    /// The sections in the order the page draws them. The levels, the grid and
    /// the way to the sections are always there; the activity section is only
    /// there when something runs, so an idle island is three sections and not
    /// an empty card.
    static func sections(activities: [NotchDashboardActivity]) -> [NotchDashboardSection] {
        var sections: [NotchDashboardSection] = [.quickControls]
        if !activities.isEmpty { sections.append(.liveActivities) }
        sections.append(.systemMonitoring)
        sections.append(.explore)
        return sections
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
    /// detail. It leads to the panel's detail instead when the island does not
    /// run, is off, has no System page, or takes the panel; and nowhere when
    /// the metric itself is off, which is how the menu bar item already behaves.
    static func menuBarOpensDetail(islandRuns: Bool, routesPanel: Bool, systemPage: Bool,
                                   metricAvailable: Bool) -> Bool {
        metricAvailable && islandRuns && routesPanel && systemPage
    }

    /// Where the way back from a detail leads: always the dashboard, which is
    /// what the grid sits on.
    static func returnsToDashboard(fromDetail: Bool) -> Bool { fromDetail }

    /// `count` items in rows of at most `columns`, the rows as even as they
    /// can be and read left to right.
    static func rows(count: Int, columns: Int) -> [Range<Int>] {
        let capacity = max(1, columns)
        guard count > 0 else { return [] }
        let rows = (count + capacity - 1) / capacity
        return (0..<rows).map { row in
            let start = row * capacity
            return start..<min(start + capacity, count)
        }
    }
}
