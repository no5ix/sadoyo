// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The one-page island's composition: which sections it shows, in which order,
/// which activities share its middle, where a monitoring tile leads, and what
/// the menu bar's indicators and the way back lead to.
///
/// These are the observable promises of the dashboard. A page that drops the
/// levels, replaces the grid with one metric, lets a song's start hide a timer,
/// or leaves no way to the sections fails here, whatever its views look like.
enum NotchDashboardTests {
    static func run(_ suite: TestSuite) {
        suite.run("dashboard sections stay and keep their order") {
            let idle = NotchDashboardSupport.sections(activities: [])
            expect(suite, idle, [.quickControls, .systemMonitoring, .explore],
                   "an island with nothing running shows the levels, the grid and the sections")
            let busy = NotchDashboardSupport.sections(activities: [.nowPlaying, .timer])
            expect(suite, busy, [.quickControls, .liveActivities, .systemMonitoring, .explore],
                   "a song and a timer go between the levels and the grid")
            for activities in [[NotchDashboardActivity](), [.nowPlaying], [.timer], [.nowPlaying, .timer]] {
                let sections = NotchDashboardSupport.sections(activities: activities)
                suite.expect(sections.first == .quickControls
                                 && sections.contains(.systemMonitoring)
                                 && sections.last == .explore,
                             "the levels, the grid and the sections stay whatever runs: \(activities)")
            }
        }

        suite.run("activities coexist and end apart") {
            expect(suite, NotchDashboardSupport.activities(music: false, timer: false), [],
                   "nothing running leaves no activity card")
            expect(suite, NotchDashboardSupport.activities(music: true, timer: false), [.nowPlaying],
                   "a song alone takes the section")
            expect(suite, NotchDashboardSupport.activities(music: false, timer: true), [.timer],
                   "a timer alone takes the section")
            expect(suite, NotchDashboardSupport.activities(music: true, timer: true), [.nowPlaying, .timer],
                   "a song and a timer share the section, in order")
            // The two are decided apart: every change of one leaves the other's
            // card as it was, and both changes together leave the section empty.
            let before = NotchDashboardSupport.activities(music: true, timer: true)
            let songEnded = NotchDashboardSupport.activities(music: false, timer: true)
            let timerEnded = NotchDashboardSupport.activities(music: true, timer: false)
            suite.expect(songEnded == [.timer] && timerEnded == [.nowPlaying],
                         "one activity ending keeps the other's card")
            suite.expect(before.count == 2
                             && NotchDashboardSupport.activities(music: false, timer: false).isEmpty,
                         "both ending empties the section, which drops it from the page")
        }

        suite.run("grid shows every metric at once, in four columns") {
            let all = NotchDashboardSupport.tiles { _ in true }
            expect(suite, all, [.cpu, .gpu, .memory, .battery, .network, .disk, .power, .fan, .devices],
                   "the grid's order, read left to right")
            let withoutFans = NotchDashboardSupport.tiles { $0 != .fan }
            suite.expect(withoutFans.count == 8, "a Mac with no fan tile shows the eight the layout asks for")
            let rows = NotchDashboardLayout.metricRowRanges(tiles: withoutFans.count)
            suite.expect(rows.count == 2 && rows[0] == 0..<4 && rows[1] == 4..<8,
                         "eight tiles fill four columns in two rows: \(rows)")
            suite.expect(NotchDashboardLayout.metricRowRanges(tiles: all.count)
                            .map { $0.count } == [3, 3, 3],
                         "nine tiles fill three even rows, so none is a lone tile")
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

        suite.run("menu bar indicators open their detail directly") {
            suite.expect(NotchDashboardSupport.menuBarOpensDetail(islandRuns: true, routesPanel: true,
                                                                  systemPage: true, metricAvailable: true),
                         "an indicator's click opens the island at its detail")
            suite.expect(!NotchDashboardSupport.menuBarOpensDetail(islandRuns: false, routesPanel: true,
                                                                   systemPage: true, metricAvailable: true),
                         "an island that is off leaves the click to the menu panel")
            suite.expect(!NotchDashboardSupport.menuBarOpensDetail(islandRuns: true, routesPanel: false,
                                                                   systemPage: true, metricAvailable: true),
                         "an island that does not take the panel leaves the click to the menu panel")
            suite.expect(!NotchDashboardSupport.menuBarOpensDetail(islandRuns: true, routesPanel: true,
                                                                   systemPage: false, metricAvailable: true),
                         "an island with no System page leaves the click to the menu panel")
            suite.expect(!NotchDashboardSupport.menuBarOpensDetail(islandRuns: true, routesPanel: true,
                                                                   systemPage: true, metricAvailable: false),
                         "a metric the island will not show opens no detail")
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

        suite.run("the island's height is what the page measures") {
            let width = NotchDashboardLayout.naturalContentWidth
            let idle = NotchDashboardLayout.sectionHeights(activities: [], metrics: 8, exploreCount: 8, width: width)
            let both = NotchDashboardLayout.sectionHeights(activities: [.nowPlaying, .timer], metrics: 8,
                                                           exploreCount: 8, width: width)
            suite.expect(idle.count == 3 && both.count == 4,
                         "one height per section, the activity card measured only when something runs")
            suite.expect(NotchDashboardLayout.contentHeight(activities: [.nowPlaying, .timer], metrics: 8,
                                                            exploreCount: 8, width: width)
                             > NotchDashboardLayout.contentHeight(activities: [], metrics: 8,
                                                                  exploreCount: 8, width: width),
                         "an activity grows the island; the sections under it do not move")
            suite.expect(NotchDashboardLayout.contentHeight(activities: [.nowPlaying], metrics: 8,
                                                            exploreCount: 8, width: width)
                             > NotchDashboardLayout.contentHeight(activities: [.timer], metrics: 8,
                                                                  exploreCount: 8, width: width),
                         "the player's card is measured taller than the timer's")
            suite.expect(idle[0] == NotchDashboardLayout.sectionHeight(NotchDashboardLayout.quickControlsHeight,
                                                                      header: true),
                         "the levels keep their row's height, plus the label above them")
            suite.expect(idle[1] == NotchDashboardLayout.sectionHeight(NotchDashboardLayout.metricsHeight(tiles: 8),
                                                                      header: true),
                         "the grid is measured at its rows, so all eight tiles fit")
            suite.expect(idle[2] == NotchDashboardLayout.sectionHeight(
                NotchDashboardLayout.exploreHeight(count: 8, width: width), header: true),
                         "the sections' marks are measured at their rows")
            suite.expect(idle.allSatisfy { height in
                height >= NotchDashboardLayout.headerHeight + NotchDashboardLayout.headerSpacing
            } && NotchDashboardLayout.contentHeight(activities: [], metrics: 8, exploreCount: 8, width: width)
                > NotchDashboardLayout.contentHeight(activities: [], metrics: 8, exploreCount: 0, width: width),
                         "every card leaves room for its label, and marks add height the page measures")
        }

        suite.run("every section the page draws names itself") {
            for activities in [[NotchDashboardActivity](), [.nowPlaying, .timer]] {
                let drawn = NotchDashboardSupport.sections(activities: activities)
                for language in AppLanguage.allCases {
                    let titles = drawn.map { $0.title(language) }
                    suite.expect(titles.allSatisfy {
                        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }, "\(language.rawValue): every section on the page has a label")
                }
                let en = drawn.map { $0.title(.enUS) }
                suite.expect(Set(en).count == en.count, "no two sections answer to the same name")
            }
            // Explore's label is the title of the page the marks open, so the
            // label above them and the page they lead to agree.
            for language in AppLanguage.allCases {
                suite.expect(NotchDashboardSection.explore.title(language)
                                 == FeatureStrings.notch(language).sectionsTitle,
                             "\(language.rawValue): the Explore label is the sections page's own title")
            }
            suite.expect(NotchDashboardLayout.headerHeight >= 9
                             && NotchDashboardLayout.headerSpacing >= 3,
                         "the label is a line that can be read, with a gap under it")
            suite.expect(NotchDashboardLayout.sectionHeight(20, header: true)
                             == NotchDashboardLayout.sectionHeight(20)
                                + NotchDashboardLayout.headerHeight + NotchDashboardLayout.headerSpacing,
                         "a card's height counts its label, so the island is as tall as the page")
            suite.expect(NotchDashboardLayout.naturalContentWidth >= 400,
                         "the page keeps the reference's width, where four columns and two levels fit")
        }

        suite.run("the sections stay compact and separated") {
            let width = NotchDashboardLayout.naturalContentWidth
            // Quick Controls: one row, the two levels sharing it.
            suite.expect(NotchDashboardLayout.quickControlWidth(width: width) > 120,
                         "a level keeps a usable slider in half the row")
            suite.expect(NotchDashboardLayout.quickControlsHeight >= 24,
                         "the slider keeps a height a pointer can hold")
            // Monitoring: four columns of tiles, each tall enough for its reading.
            suite.expect(NotchDashboardLayout.metricColumns == 4
                             && NotchDashboardLayout.metricTileHeight >= 24,
                         "eight readings in four columns of readable tiles")
            suite.expect(NotchDashboardLayout.metricsHeight(tiles: 8)
                             == NotchDashboardLayout.gridHeight(rows: 2,
                                                                tileHeight: NotchDashboardLayout.metricTileHeight,
                                                                spacing: NotchDashboardLayout.metricSpacing),
                         "the grid's height is its two rows")
            // Explore: round marks, no words, as many as fit, spreading sideways.
            let columns = NotchDashboardLayout.exploreColumns(width: width - NotchDashboardLayout.sectionInset * 2)
            suite.expect(columns >= 10, "the marks fit a row on a wide island: \(columns)")
            suite.expect(NotchDashboardLayout.exploreHeight(count: 14, width: width)
                             == NotchDashboardLayout.exploreHeight(count: 10, width: width)
                             + NotchDashboardLayout.exploreSpacing + NotchDashboardLayout.exploreButton,
                         "marks past the row add a row, so none is cut off")
            suite.expect(NotchDashboardSupport.rows(count: 0, columns: columns).isEmpty
                             && NotchDashboardSupport.rows(count: 5, columns: 4) == [0..<4, 4..<5],
                         "rows cover every mark exactly once")
            // Separation: the cards are inset from each other, not flush.
            suite.expect(NotchDashboardLayout.sectionSpacing >= 6
                             && NotchDashboardLayout.cornerRadius > 0
                             && NotchDashboardLayout.fillOpacity > 0.06,
                         "cards are rounded and lighter than the island's black, with a gap between them")
        }
    }

    private static func expect(_ suite: TestSuite, _ actual: [NotchDashboardSection],
                               _ expected: [NotchDashboardSection], _ message: String) {
        suite.expect(actual == expected, "\(message): got \(actual.map(\.rawValue))")
    }

    private static func expect(_ suite: TestSuite, _ actual: [NotchDashboardActivity],
                               _ expected: [NotchDashboardActivity], _ message: String) {
        suite.expect(actual == expected, "\(message): got \(actual)")
    }

    private static func expect(_ suite: TestSuite, _ actual: [NotchDashboardMetric],
                               _ expected: [NotchDashboardMetric], _ message: String) {
        suite.expect(actual == expected, "\(message): got \(actual.map(\.rawValue))")
    }
}
