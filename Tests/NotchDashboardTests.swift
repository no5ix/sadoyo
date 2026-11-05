// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The one-page island's composition: which sections it shows, in which order,
/// which players and timers share its middle, where a monitoring tile leads,
/// how tall a detail is allowed to be, and what the menu bar's indicators and
/// the way back lead to.
///
/// These are the observable promises of the dashboard. A page that drops the
/// levels, replaces the grid with one metric, caps the players at one, lets a
/// song's start hide a timer, prints a heading over a section, or leaves no way
/// to the sections fails here, whatever its views look like.
enum NotchDashboardTests {
    static func run(_ suite: TestSuite) {
        suite.run("dashboard sections stay and keep their order") {
            let idle = NotchDashboardSupport.sections(activities: [], calendar: false)
            expect(suite, idle, [.quickControls, .systemMonitoring, .explore],
                   "an island with nothing running shows the levels, the grid and the sections")
            let busy = NotchDashboardSupport.sections(activities: [.player(id: 7), .timer], calendar: true)
            expect(suite, busy, [.quickControls, .calendar, .liveActivities, .systemMonitoring, .explore],
                   "the month, then a player and a timer, go between the levels and the grid")
            // The order is the reference's: levels, calendar, activities, grid,
            // sections. Nothing runs between the levels and the calendar.
            suite.expect(busy.first == .quickControls && busy[1] == .calendar
                             && busy[2] == .liveActivities && busy[3] == .systemMonitoring
                             && busy.last == .explore,
                         "the calendar sits under the levels and above the activities")
            for activities in [[NotchDashboardActivity](), [.player(id: 7)], [.timer],
                               [.player(id: 7), .player(id: 9), .timer]] {
                let sections = NotchDashboardSupport.sections(activities: activities, calendar: true)
                suite.expect(sections.first == .quickControls
                                 && sections.contains(.calendar)
                                 && sections.contains(.systemMonitoring)
                                 && sections.last == .explore,
                             "the levels, the calendar, the grid and the sections stay whatever runs: \(activities.count) cards")
            }
        }

        suite.run("the calendar card has its place, and a page wide enough to hold it") {
            // The card is the page's, so it is measured as one shape: the grid
            // at the rows the grid draws itself, with the month's name above it.
            suite.expect(NotchDashboardLayout.calendarCardHeight
                             == NotchDashboardLayout.calendarHeaderHeight + 6 + NotchDashboardLayout.calendarGridHeight,
                         "the card is the grid, its header and their gap, and nothing else")
            suite.expect(NotchDashboardLayout.calendarGridHeight
                             >= NotchDashboardLayout.calendarMonthMinimumHeight,
                         "the grid keeps a row for every week of the month")
            // The page the reference draws - two players, a timer, eight
            // readings, fourteen marks and the month - is read at once, at the
            // island's tallest preset, so the sections do not need a screen each.
            let drawn = NotchDashboardLayout.contentHeight(
                activities: [.player(id: 7), .player(id: 9), .timer],
                calendar: true, metrics: 8, exploreCount: 14,
                width: NotchDashboardLayout.naturalContentWidth)
            suite.expect(drawn <= 630,
                         "the page the reference draws fits the island's tallest preset: \(Int(drawn))pt")
            // What runs is not capped to make that true: more cards make the page
            // taller, and the page scrolls in the island instead of hiding a card.
            let crowded = NotchDashboardLayout.contentHeight(
                activities: [.player(id: 7), .player(id: 9), .player(id: 11), .player(id: 13), .timer],
                calendar: true, metrics: 8, exploreCount: 14,
                width: NotchDashboardLayout.naturalContentWidth)
            suite.expect(crowded > drawn, "each player that starts adds its own card to the page")
            // A page narrower than a week of days beside the day's appointments
            // keeps its other sections instead of squeezing the calendar.
            suite.expect(NotchDashboardSupport.showsCalendar(section: true,
                                                             width: NotchDashboardLayout.naturalContentWidth),
                         "the page at its own width shows the calendar")
            suite.expect(!NotchDashboardSupport.showsCalendar(section: true, width: 300),
                         "a page too narrow for a week and an agenda shows no calendar card")
            suite.expect(!NotchDashboardSupport.showsCalendar(section: false,
                                                              width: NotchDashboardLayout.naturalContentWidth),
                         "the section switched off takes its card away from the page")
            // The card belongs between the levels and the activities, so the
            // page's height counts it in that place.
            let withCard = NotchDashboardLayout.sectionHeights(activities: [.player(id: 7)], calendar: true,
                                                               metrics: 8, exploreCount: 7,
                                                               width: NotchDashboardLayout.naturalContentWidth)
            let without = NotchDashboardLayout.sectionHeights(activities: [.player(id: 7)], calendar: false,
                                                              metrics: 8, exploreCount: 7,
                                                              width: NotchDashboardLayout.naturalContentWidth)
            suite.expect(withCard.count == without.count + 1
                             && withCard[1] == NotchDashboardLayout.calendarCardHeight
                             && without.count == 4,
                         "the calendar is the page's second section, between the levels and the activities")
        }

        suite.run("every player playing gets a card, and the timer has its own") {
            expect(suite, NotchDashboardSupport.activities(players: [], timer: false), [],
                   "nothing running leaves no activity card")
            expect(suite, NotchDashboardSupport.activities(players: [7], timer: false), [.player(id: 7)],
                   "one player takes the section")
            expect(suite, NotchDashboardSupport.activities(players: [], timer: true), [.timer],
                   "a timer alone takes the section")
            // Nothing caps the players at one: three at once are three cards, in
            // the order they were found, with the timer last.
            expect(suite, NotchDashboardSupport.activities(players: [7, 9, 11], timer: true),
                   [.player(id: 7), .player(id: 9), .player(id: 11), .timer],
                   "three players and a timer share one section as four cards")
            suite.expect(Set(NotchDashboardSupport.activities(players: [7, 9, 11], timer: true).map(\.id)).count == 4,
                         "each card is its own, so two players are not one card")
            // The cards are decided apart: one ending leaves the others as they
            // were, and the timer's ending leaves every player's card.
            let many = NotchDashboardSupport.activities(players: [7, 9], timer: true)
            let oneStopped = NotchDashboardSupport.activities(players: [9], timer: true)
            let timerStopped = NotchDashboardSupport.activities(players: [7, 9], timer: false)
            suite.expect(oneStopped == [.player(id: 9), .timer],
                         "one player stopping leaves the other's card and the timer's")
            suite.expect(timerStopped == [.player(id: 7), .player(id: 9)],
                         "the timer ending leaves every player's card where it was")
            suite.expect(NotchDashboardSupport.activities(players: [], timer: false).isEmpty,
                         "all of them ending empties the section, which drops it from the page")
        }

        suite.run("grid shows every metric at once, in four columns") {
            let all = NotchDashboardSupport.tiles { _ in true }
            expect(suite, all, [.cpu, .gpu, .memory, .battery, .network, .disk, .power, .fan, .devices],
                   "the grid's order, read left to right")
            let eight = NotchDashboardSupport.tiles { $0 != .fan }
            suite.expect(eight.count == 8, "a Mac with no fan tile shows the eight the layout asks for")
            suite.expect(NotchDashboardLayout.metricColumns == 4, "the grid is four columns wide")
            let rows = NotchDashboardLayout.metricRowRanges(tiles: eight.count)
            suite.expect(rows.count == 2 && rows[0] == 0..<4 && rows[1] == 4..<8,
                         "eight tiles fill four columns in two rows: \(rows)")
            suite.expect(NotchDashboardLayout.metricRowRanges(tiles: all.count)
                            .map { $0.count } == [4, 4, 1],
                         "nine tiles fill the rows from the left, so the tiles keep one width")
            // Unavailable metrics leave no tile, so no tile opens an empty detail.
            expect(suite, NotchDashboardSupport.tiles { $0 == .cpu }, [.cpu], "a desktop Mac shows a CPU tile only")
            suite.expect(NotchDashboardLayout.metricRowRanges(tiles: 0).isEmpty
                             && NotchDashboardLayout.metricsHeight(tiles: 0) == 0,
                         "no tiles measure no grid")
        }

        suite.run("each metric names the detail it opens") {
            // The island opens a detail by this spelling; the panel's detail
            // kinds answer to the same names.
            let expected: [NotchDashboardMetric: String] = [
                .cpu: "cpu", .gpu: "gpu", .memory: "memory", .battery: "battery",
                .network: "network", .disk: "disk", .power: "power", .fan: "fan",
                .devices: "connectedDevices",
            ]
            var ids: Set<String> = []
            for (metric, id) in expected {
                suite.expect(metric.detailID == id, "\(metric.rawValue) opens \(id)")
                ids.insert(metric.detailID)
            }
            suite.expect(ids.count == expected.count, "no two tiles share a destination")
        }

        suite.run("the two levels sit at the two ends of the page") {
            // One row, the first level at the leading edge, the last at the
            // trailing edge, the page's empty middle between them: the row the
            // reference draws, and the Controls page's own controls in it.
            suite.expect(NotchDashboardLayout.hasTrailingGap(levels: 2),
                         "volume and brightness share the row with the page's middle between them")
            suite.expect(!NotchDashboardLayout.hasTrailingGap(levels: 1),
                         "one level takes the leading end, and nothing is pushed to the far side")
            suite.expect(!NotchDashboardLayout.hasTrailingGap(levels: 0),
                         "no level takes no row, and the page does not grow one")
            suite.expect(NotchDashboardLayout.quickControlLeadingCount == 1
                             && NotchDashboardLayout.quickControlsHeight == 28,
                         "the row is one row of the Controls page's compact sliders")
        }

        suite.run("menu bar indicators open their detail directly") {
            // A reading in the menu bar is a reading, so its indicator leads to
            // that reading's detail. What the app's panel is set to open at the
            // app's own icon is a separate question and does not answer this one.
            suite.expect(NotchDashboardSupport.menuBarOpensDetail(islandRuns: true, systemPage: true,
                                                                  metricAvailable: true),
                         "an indicator's click opens the island at its detail")
            suite.expect(!NotchDashboardSupport.menuBarOpensDetail(islandRuns: false, systemPage: true,
                                                                   metricAvailable: true),
                         "an island that is off leaves the click to the menu panel")
            suite.expect(!NotchDashboardSupport.menuBarOpensDetail(islandRuns: true, systemPage: false,
                                                                   metricAvailable: true),
                         "an island with no System page leaves the click to the menu panel")
            suite.expect(!NotchDashboardSupport.menuBarOpensDetail(islandRuns: true, systemPage: true,
                                                                   metricAvailable: false),
                         "a metric the island will not show opens no detail")
            for metric in NotchDashboardMetric.allCases {
                suite.expect(!metric.detailID.isEmpty, "\(metric.rawValue) leads somewhere")
            }
        }

        suite.run("every page leads back to the page it sits on") {
            // A section opened from the page's marks, a detail, and the gallery
            // all return to the dashboard, and the marks the person tapped their
            // way out of are not the destination's way back.
            suite.expect(NotchDashboardSupport.returnsToDashboard(sectionPage: true, appPanel: false, dashboard: false),
                         "a section opened from the marks leads back to the dashboard")
            suite.expect(NotchDashboardSupport.returnsToDashboard(sectionPage: true, appPanel: false, dashboard: true)
                             == false,
                         "the dashboard needs no way back to itself")
            suite.expect(NotchDashboardSupport.returnsToDashboard(sectionPage: true, appPanel: true, dashboard: false)
                             == false,
                         "the app panel keeps its own way out")
            suite.expect(!NotchDashboardSupport.returnsToDashboard(sectionPage: false, appPanel: false,
                                                                   dashboard: false),
                         "a closed island leads nowhere")
            suite.expect(NotchDashboardSupport.returnsToDashboard(sectionPage: true, appPanel: false, dashboard: false)
                             && NotchDashboardSupport.returnsToDashboard(fromDetail: true),
                         "the section and the detail share one way back")
        }

        suite.run("closing the timer's card leaves every player's card") {
            // The card's close ends the timer's session. The players' cards are
            // decided by what plays, so the close touches none of them.
            let both = NotchDashboardSupport.activities(players: [7, 9], timer: true)
            let closed = NotchDashboardSupport.activities(players: [7, 9], timer: false)
            expect(suite, both, [.player(id: 7), .player(id: 9), .timer], "two players and a timer, three cards")
            expect(suite, closed, [.player(id: 7), .player(id: 9)],
                   "the timer closed, the players keep their cards and their order")
            suite.expect(NotchDashboardLayout.liveActivitiesHeight(both)
                             - NotchDashboardLayout.liveActivitiesHeight(closed)
                             == NotchDashboardLayout.activityCardHeight + NotchDashboardLayout.cardSpacing,
                         "the page loses the timer's card and its gap, and nothing else")
            suite.expect(NotchDashboardSupport.sections(activities: closed, calendar: true).contains(.liveActivities),
                         "the section stays while the players run")
            let empty = NotchDashboardSupport.activities(players: [], timer: false)
            suite.expect(empty.isEmpty
                             && !NotchDashboardSupport.sections(activities: empty, calendar: true).contains(.liveActivities),
                         "the last card closing takes the empty section away from the page")
        }

        suite.run("the page and the way back") {
            // Opening the island asks for nothing, so it opens on the dashboard.
            suite.expect(NotchDashboardSupport.opensDashboard(module: false, metric: false,
                                                              appPanel: false, sections: false),
                         "hovering the island opens the dashboard")
            for (module, metric, panel, sections) in [(true, false, false, false), (false, true, false, false),
                                                      (false, false, true, false), (false, false, false, true)] {
                suite.expect(!NotchDashboardSupport.opensDashboard(module: module, metric: metric,
                                                                   appPanel: panel, sections: sections),
                             "a named destination is what opens, not the dashboard")
            }
            // A detail is a page over the dashboard, and the way back leads there.
            let overDetail = NotchDashboardSupport.showsDashboard(dashboard: true, expanded: true, metric: true,
                                                                  appPanel: false, sections: false,
                                                                  commandBar: false, modules: true)
            suite.expect(!overDetail, "a detail covers the grid, it does not sit under it")
            suite.expect(NotchDashboardSupport.returnsToDashboard(fromDetail: true),
                         "the way back from a detail leads to the dashboard")
            suite.expect(NotchDashboardSupport.showsDashboard(dashboard: true, expanded: true, metric: false,
                                                              appPanel: false, sections: false,
                                                              commandBar: false, modules: true),
                         "the open island shows the dashboard")
            for (metric, panel, sections, commandBar, modules) in [(true, false, false, false, true),
                                                                   (false, true, false, false, true),
                                                                   (false, false, true, false, true),
                                                                   (false, false, false, true, true),
                                                                   (false, false, false, false, false)] {
                suite.expect(!NotchDashboardSupport.showsDashboard(dashboard: true, expanded: true, metric: metric,
                                                                   appPanel: panel, sections: sections,
                                                                   commandBar: commandBar, modules: modules),
                             "a surface of its own, or no section at all, keeps the dashboard away")
            }
            suite.expect(!NotchDashboardSupport.showsDashboard(dashboard: true, expanded: false, metric: false,
                                                               appPanel: false, sections: false,
                                                               commandBar: false, modules: true),
                         "a closed island shows its strip, not the page")
        }

        suite.run("the island's height is what the page measures, with no headings") {
            let width = NotchDashboardLayout.naturalContentWidth
            let cards: [NotchDashboardActivity] = [.player(id: 7), .player(id: 9), .timer]
            let idle = NotchDashboardLayout.sectionHeights(activities: [], calendar: false, metrics: 8,
                                                            exploreCount: 7, width: width)
            let busy = NotchDashboardLayout.sectionHeights(activities: cards, calendar: false, metrics: 8,
                                                            exploreCount: 7, width: width)
            suite.expect(idle.count == 3 && busy.count == 4,
                         "one height per section, the activity cards measured only when something runs")
            // A section is its content and nothing else: no label line, no
            // card insets of its own. That is what keeps the island exactly as
            // tall as the page it holds.
            suite.expect(idle[0] == NotchDashboardLayout.quickControlsHeight,
                         "the levels' row is a row, not a card with a caption")
            suite.expect(idle[1] == NotchDashboardLayout.metricsHeight(tiles: 8),
                         "the grid is measured at its rows")
            suite.expect(idle[2] == NotchDashboardLayout.exploreHeight(count: 7, width: width),
                         "the sections' marks are measured at their rows")
            suite.expect(busy[1] == NotchDashboardLayout.liveActivitiesHeight(cards),
                         "the activity section is measured at its three cards")
            suite.expect(NotchDashboardLayout.contentHeight(activities: cards, calendar: false, metrics: 8,
                                                             exploreCount: 7, width: width)
                             == busy.reduce(0, +) + NotchDashboardLayout.sectionSpacing * 3,
                         "the page is its sections and the gaps between them")
            // Each card, player or timer, adds exactly its own height.
            suite.expect(NotchDashboardLayout.liveActivitiesHeight([.player(id: 7)]) + NotchDashboardLayout.cardSpacing
                             + NotchDashboardLayout.activityCardHeight
                             == NotchDashboardLayout.liveActivitiesHeight([.player(id: 7), .player(id: 9)]),
                         "a second player adds a card of its own, and the gap")
            suite.expect(NotchDashboardLayout.liveActivitiesHeight(cards)
                             > NotchDashboardLayout.liveActivitiesHeight([.player(id: 7)]),
                         "more cards grow the page, which the island then measures")
        }

        suite.run("each section is known by shape, and named out loud") {
            // The page prints no headings, so its labels are the accessibility
            // labels of the content they stand over: every language has them and
            // no two sections answer to the same name.
            for activities in [[NotchDashboardActivity](), [.player(id: 7), .timer]] {
                let drawn = NotchDashboardSupport.sections(activities: activities, calendar: true)
                for language in AppLanguage.allCases {
                    let titles = drawn.map { $0.title(language) }
                    suite.expect(titles.allSatisfy {
                        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }, "\(language.rawValue): every section on the page has a label")
                }
                let en = drawn.map { $0.title(.enUS) }
                suite.expect(Set(en).count == en.count, "no two sections answer to the same name")
            }
            // Explore's label is the title of the page the marks open.
            for language in AppLanguage.allCases {
                suite.expect(NotchDashboardSection.explore.title(language)
                                 == FeatureStrings.notch(language).sectionsTitle,
                             "\(language.rawValue): the Explore label is the sections page's own title")
            }
        }

        suite.run("the sections are laid out as the page was drawn") {
            let width = NotchDashboardLayout.naturalContentWidth
            // Quick Controls: a compact row of two levels, leading the page,
            // each a mark and a narrow bar, with room to spare beside them.
            suite.expect(NotchDashboardLayout.quickControlsHeight >= 24
                             && NotchDashboardLayout.quickControlsHeight <= 34,
                         "the row is tall enough for a slider a pointer can hold, and no taller")
            suite.expect(NotchDashboardLayout.quickControlBarWidth <= 140,
                         "a level's bar stays compact: \(NotchDashboardLayout.quickControlBarWidth)")
            suite.expect(2 * NotchDashboardLayout.quickControlWidth(width: width)
                             + NotchDashboardLayout.quickControlsSpacing <= width,
                         "both levels fit the row side by side, with the row's end left empty")
            // Monitoring: four columns, two rows, each tile a label, a reading
            // and a meter.
            suite.expect(NotchDashboardLayout.metricTileHeight >= 44,
                         "a tile has room for its label, its reading and its meter")
            suite.expect(NotchDashboardLayout.metricsHeight(tiles: 8)
                             == NotchDashboardLayout.gridHeight(rows: 2,
                                                                tileHeight: NotchDashboardLayout.metricTileHeight,
                                                                spacing: NotchDashboardLayout.metricSpacing),
                         "the grid's height is its two rows")
            // Explore: round marks, seven in a row, so the sections sit on the
            // page in two rows and none of them is cut off.
            suite.expect(NotchDashboardLayout.exploreColumns(width: width) == 7,
                         "seven marks in a row at the page's width")
            suite.expect(NotchDashboardLayout.exploreButton >= 36,
                         "a mark is a circle a pointer aims at, not a dot")
            suite.expect(NotchDashboardLayout.exploreRows(count: 14, width: width) == 2,
                         "fourteen sections fill the row and one more")
            suite.expect(NotchDashboardLayout.exploreHeight(count: 14, width: width)
                             == NotchDashboardLayout.exploreHeight(count: 7, width: width)
                             + NotchDashboardLayout.exploreSpacing + NotchDashboardLayout.exploreButton,
                         "marks past the row add a row, so none is cut off")
            suite.expect(NotchDashboardSupport.rows(count: 0, columns: 7).isEmpty
                             && NotchDashboardSupport.rows(count: 5, columns: 4) == [0..<4, 4..<5],
                         "rows cover every mark exactly once")
            // The page keeps the reference's width, where four columns of tiles,
            // two levels and seven marks all fit.
            suite.expect(width >= 520 && width <= 620, "the page keeps the reference's width: \(width)")
            // Shapes, not headings, separate the sections: filled, rounded and
            // gapped, on the island's black.
            suite.expect(NotchDashboardLayout.sectionSpacing >= 8
                             && NotchDashboardLayout.cornerRadius >= 10
                             && NotchDashboardLayout.fillOpacity >= 0.08,
                         "cards are rounded, lighter than the island's black, and gapped")
        }

        suite.run("a detail is as tall as what it shows, and scrolls when it is taller") {
            let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                         safeAreaTop: 32, cameraWidth: 180)
            let unmeasured = geometry.expandedSize(module: .system, detail: true, panel: false, detailHeight: nil)
            let short = geometry.expandedSize(module: .system, detail: true, panel: false, detailHeight: 120)
            let long = geometry.expandedSize(module: .system, detail: true, panel: false, detailHeight: 10_000)
            suite.expect(short.height < unmeasured.height,
                         "a detail measured short gives a short island, not a page of empty space")
            suite.expect(long.height <= unmeasured.height,
                         "a detail taller than the display is capped by the page, which scrolls inside it")
            suite.expect(long.height < 10_000, "the island never grows past the display for a long detail")
            let page = geometry.contentSize(for: long)
            suite.expect(page.height > 0 && page.height < 956, "the detail's page stays on the display")
        }
    }

    private static func expect(_ suite: TestSuite, _ actual: [NotchDashboardSection],
                               _ expected: [NotchDashboardSection], _ message: String) {
        suite.expect(actual == expected, "\(message): got \(actual.map(\.rawValue))")
    }

    private static func expect(_ suite: TestSuite, _ actual: [NotchDashboardActivity],
                               _ expected: [NotchDashboardActivity], _ message: String) {
        suite.expect(actual == expected, "\(message): got \(actual.map(\.id))")
    }

    private static func expect(_ suite: TestSuite, _ actual: [NotchDashboardMetric],
                               _ expected: [NotchDashboardMetric], _ message: String) {
        suite.expect(actual == expected, "\(message): got \(actual.map(\.rawValue))")
    }
}
