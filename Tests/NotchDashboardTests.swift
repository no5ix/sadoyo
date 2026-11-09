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
                             == NotchDashboardLayout.calendarCardPadding * 2
                                 + NotchDashboardLayout.calendarHeaderHeight
                                 + NotchDashboardLayout.calendarHeaderGap
                                 + NotchDashboardLayout.calendarGridHeight,
                         "the card is its edge, the month's name, the grid and the edge again, and nothing else")
            // The card's edge is the same on every side, so the month's name and
            // the last week of days sit as far from the outline as the card's
            // first day does, and the card is not empty at its bottom.
            suite.expect(NotchDashboardLayout.calendarCardPadding == 8,
                         "one edge, kept on all four sides")
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
            suite.expect(drawn <= 700,
                         "the page the reference draws fits a small display's island: \(Int(drawn))pt")
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
                             && withCard.first == NotchDashboardLayout.calendarCardHeight
                             && without.count == 3,
                         "the calendar leads the page's sections, under the row of levels")
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

        suite.run("the levels are the island's top row, choosers and all") {
            // The row of levels is the island's own top row, beside the camera
            // as the Controls page sets it: volume at the leading edge, the last
            // level at the trailing edge, and the page starting under it, so no
            // empty band is left above the sliders.
            suite.expect(NotchDashboardLayout.showsLevelRow(levels: 2)
                             && NotchDashboardLayout.showsLevelRow(levels: 1),
                         "a Mac with a level to show has the row, and the page starts under it")
            suite.expect(!NotchDashboardLayout.showsLevelRow(levels: 0),
                         "with every level hidden the island keeps its bare top, and no empty row")
            // The chooser is the row's own: it is where the output and the
            // display are picked. A tight row shortens the bar first.
            suite.expect(NotchDashboardLayout.quickControlNaturalWidth
                             == NotchDashboardLayout.quickControlMarkWidth + 6
                                 + NotchDashboardLayout.quickControlBarWidth + 6
                                 + NotchDashboardLayout.quickControlChooserWidth,
                         "a level is its mark, its bar and its chooser")
            suite.expect(NotchDashboardLayout.quickControlBarMinimumWidth
                             < NotchDashboardLayout.quickControlBarWidth
                             && NotchDashboardLayout.quickControlChooserWidth > 0,
                         "the bar narrows before the chooser is dropped")
            let side = (NotchDashboardLayout.naturalContentWidth - 210) / 2
            suite.expect(side >= NotchDashboardLayout.quickControlNaturalWidth,
                         "each side beside this Mac's camera holds a level with its chooser: \(Int(side))pt")
            suite.expect(NotchDashboardLayout.quickControlMinimumWidth <= 106,
                         "and a narrow row's side takes a level at its narrowest: "
                             + "\(Int(NotchDashboardLayout.quickControlMinimumWidth))pt")
        }

        suite.run("menu bar indicators open their detail, wherever they land") {
            // A reading in the menu bar is a reading, so its indicator leads to
            // that reading's detail: the island's page when the island can take
            // the click, the app's panel at the same detail when it cannot. The
            // panel is never left at the section the reading is one card in,
            // and what the panel opens at the app's own icon is a separate
            // question that does not answer this one.
            suite.expect(NotchDashboardSupport.menuBarRoute(islandRuns: true, systemPage: true,
                                                            metricAvailable: true) == .islandDetail,
                         "an indicator's click opens the island at its detail")
            suite.expect(NotchDashboardSupport.menuBarRoute(islandRuns: false, systemPage: true,
                                                            metricAvailable: true) == .panelDetail,
                         "an island that is off takes the click to the panel's detail page")
            suite.expect(NotchDashboardSupport.menuBarRoute(islandRuns: true, systemPage: false,
                                                            metricAvailable: true) == .panelDetail,
                         "an island with no System page takes it to the panel's detail page")
            suite.expect(NotchDashboardSupport.menuBarRoute(islandRuns: false, systemPage: false,
                                                            metricAvailable: true) == .panelDetail,
                         "neither surface ready, the click still lands on a detail page")
            suite.expect(NotchDashboardSupport.menuBarRoute(islandRuns: true, systemPage: true,
                                                            metricAvailable: false) == .nothing,
                         "a metric that is off opens no detail, on either surface")
            // The panel is a surface of the reading's own: opened at a metric, it
            // shows that reading's page, which is what one click asks for.
            suite.expect(NotchDashboardSupport.metricShowsInAppPanel(appPanelOpen: true)
                             && !NotchDashboardSupport.metricShowsInAppPanel(appPanelOpen: false),
                         "with the panel on screen the detail is the panel's page")
            // Why a click did not reach the island, in the log's own words.
            suite.expect(NotchDashboardSupport.menuBarRouteReason([("island-off", true), ("fullscreen", true)]) == nil,
                         "a click the island takes has no reason")
            suite.expect(NotchDashboardSupport.menuBarRouteReason([("island-off", true),
                                                                   ("fullscreen", false),
                                                                   ("mission-control", false)])
                             == "fullscreen,mission-control",
                         "the log names every condition that sent the click away, in order")
            suite.expect(NotchDashboardSupport.menuBarRouteReason([("metric-off", false)]) == "metric-off",
                         "a metric that is off says so by its own name")
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

        suite.run("the island grows by the card, and every section stays on the page") {
            let width = NotchDashboardLayout.naturalContentWidth
            let tiles = 8
            func height(_ players: Int, timer: Bool) -> CGFloat {
                var activities: [NotchDashboardActivity] = (0..<players).map { .player(id: 7 + $0) }
                if timer { activities.append(.timer) }
                return NotchDashboardLayout.contentHeight(activities: activities, calendar: true,
                                                           metrics: tiles, exploreCount: 7, width: width,
                                                           primaryPlayerID: players > 0 ? 7 : nil)
            }
            let bare = height(0, timer: false)
            let one = height(1, timer: false)
            let two = height(2, timer: false)
            let three = height(3, timer: false)
            // A card is a card: each player adds exactly its own height and the
            // gap, so the page - and the island that measures it - grows by that.
            suite.expect(one - bare == NotchDashboardLayout.activityCardHeight + NotchDashboardLayout.sectionSpacing,
                         "one player adds the player's card and the section: one=\(one) bare=\(bare)")
            suite.expect(two - one == NotchDashboardLayout.playerCardHeight + NotchDashboardLayout.cardSpacing,
                         "a second player adds its own row inside the section")
            suite.expect(three - two == NotchDashboardLayout.playerCardHeight + NotchDashboardLayout.cardSpacing,
                         "a third player adds its own row, and the page keeps growing")
            suite.expect(height(3, timer: true) - three
                             == NotchDashboardLayout.timerCardHeight + NotchDashboardLayout.cardSpacing,
                         "the timer adds its own card beside the players")
            // The grid is measured whole at every size: the page never trims the
            // readings to make room for a player.
            suite.expect(NotchDashboardLayout.metricsHeight(tiles: tiles)
                             == NotchDashboardLayout.gridHeight(rows: 2,
                                                                tileHeight: NotchDashboardLayout.metricTileHeight,
                                                                spacing: NotchDashboardLayout.metricSpacing),
                         "eight readings are two rows of four, whatever the players are")
            suite.expect(height(3, timer: true) >= bare
                             + NotchDashboardLayout.metricsHeight(tiles: tiles)
                             + NotchDashboardLayout.exploreHeight(count: 7, width: width),
                         "the page holds the grid and the sections on top of the players")
            // A built-in display holds the fullest page, so nothing of it is
            // left under a scroll.
            suite.expect(three <= NotchDashboardLayout.maxPageHeight(screenHeight: 1084)
                             && height(3, timer: true) <= NotchDashboardLayout.maxPageHeight(screenHeight: 1084),
                         "the month, three players, the timer, the grid and the sections fit a built-in display: \(height(3, timer: true))")
        }

        suite.run("the island's dashboard height follows the page, not the preset") {
            let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
            func geometry(_ preset: NotchSize, height custom: Double = 320) -> NotchGeometry {
                NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 200,
                              layout: preset, customHeight: custom)
            }
            let small = geometry(.compact)
            let chosen = geometry(.custom, height: 220)
            let wide = geometry(.spacious)
            let one: CGFloat = 420
            let three: CGFloat = 640
            let oneSize = small.dashboardSize(content: one, width: 568)
            let threeSize = small.dashboardSize(content: three, width: 568)
            suite.expect(threeSize.height > oneSize.height,
                         "the island grows when the page does, on every preset")
            suite.expect(oneSize.height == one + small.chromeHeight
                             && threeSize.height == three + small.chromeHeight,
                         "the island is the page, its chrome, and nothing else")
            // The display is the only ceiling, and the page scrolls below it.
            let tall = small.dashboardSize(content: 4000, width: 568)
            suite.expect(tall.height == NotchHeightPolicy.maximumHeight(displayHeight: 1117),
                         "the display's 80% bounds the island, which is where the page starts to scroll")
            suite.expect(small.scrolls(contentHeight: 4000, minimumContentHeight: NotchLayout.emptyHeight),
                         "and the page scrolls to the sections below that limit")
            suite.expect(small.dashboardContentLimit == tall.height - small.chromeHeight,
                         "the page's own limit is that island less its chrome")
            // A height chosen by hand is that island's own limit, under the rule.
            suite.expect(chosen.dashboardSize(content: 4000, width: 568).height
                             == chosen.surfaceCeiling,
                         "a height chosen by hand bounds the dashboard, and the page scrolls inside it")
            let wideOne = wide.dashboardSize(content: one, width: 568)
            let wideThree = wide.dashboardSize(content: three, width: 568)
            suite.expect(wideThree.height - wideOne.height == three - one
                             && wideThree.height > 220,
                         "the preset does not set the page's ceiling: its content does, on every preset")
        }

        suite.run("a player's control goes to that player, and to no other") {
            // The command carries the player the click was aimed at, by process
            // and bundle. It asks nothing about which player the page follows.
            suite.expect(NotchDashboardSupport.playerCommand(sourcePID: 9, bundleIdentifier: "com.spotify.client",
                                                             action: .toggle, inEffectPID: 7, reported: true)
                             == .send(pid: 9, bundleIdentifier: "com.spotify.client", action: .toggle),
                         "a card's control is aimed at the player of that card")
            suite.expect(NotchDashboardSupport.playerCommand(sourcePID: 7, bundleIdentifier: "com.apple.Music",
                                                             action: .next, inEffectPID: 7, reported: true)
                             == .send(pid: 7, bundleIdentifier: "com.apple.Music", action: .next),
                         "the card of the player in effect is aimed the same way")
            suite.expect(NotchDashboardSupport.playerCommand(sourcePID: 9, bundleIdentifier: "com.spotify.client",
                                                             action: .toggle, inEffectPID: 7, reported: false) == .refuse,
                         "a player the adapter no longer reports is sent nothing")
            suite.expect(NotchDashboardSupport.playerCommand(sourcePID: -1, bundleIdentifier: "com.spotify.client",
                                                             action: .toggle, inEffectPID: 7, reported: true) == .refuse,
                         "a card without a process is sent nothing")
            suite.expect(NotchDashboardSupport.playerCommand(sourcePID: 9, bundleIdentifier: "com.spotify.client",
                                                             action: nil, inEffectPID: 7, reported: true) == .refuse,
                         "a control with no per-player form is aimed at no player")
            suite.expect(NotchDashboardSupport.playerCommand(sourcePID: 9, bundleIdentifier: "",
                                                             action: .toggle, inEffectPID: 7, reported: true) == .refuse,
                         "a card that names no app is sent nothing")
            // A card's marks are drawn only where a command can reach that
            // player: a command for a player that names no recording of its own
            // would land on the player the system is playing.
            let scoped = NotchPlaybackSource(pid: 9, bundleIdentifier: "com.spotify.client", isMusicApp: true,
                                             isPlaying: true, hasTrack: true, itemIdentifier: "item-1")
            let unscoped = NotchPlaybackSource(pid: 31, bundleIdentifier: "com.netease.163music", isMusicApp: true,
                                               isPlaying: true, hasTrack: true)
            suite.expect(NotchDashboardLayout.commandsReach(player: scoped),
                         "a player that reports its own recording is reached by its card's marks")
            suite.expect(!NotchDashboardLayout.commandsReach(player: unscoped),
                         "a player that names no recording is given no marks, so none of them is a dead control")
            suite.expect(NotchPlaybackCommand.toggle.playerAction == .toggle
                             && NotchPlaybackCommand.next.playerAction == .next
                             && NotchPlaybackCommand.previous.playerAction == .previous
                             && NotchPlaybackCommand.seek(10).playerAction == nil
                             && NotchPlaybackCommand.source(nil).playerAction == nil,
                         "only the three marks of a card's transport have a per-player form")
        }

        suite.run("using a player's control leaves the cards where they were") {
            let safari = NotchPlaybackSource(pid: 21, bundleIdentifier: "com.apple.Safari", isMusicApp: false,
                                             isPlaying: true, hasTrack: true, displayName: "Safari")
            let netease = NotchPlaybackSource(pid: 31, bundleIdentifier: "com.netease.163music", isMusicApp: true,
                                              isPlaying: true, hasTrack: true, displayName: "NetEaseMusic")
            let spotify = NotchPlaybackSource(pid: 41, bundleIdentifier: "com.spotify.client", isMusicApp: true,
                                              isPlaying: true, hasTrack: true, displayName: "Spotify")
            let reported = [netease, safari, spotify]
            let first = NotchDashboardLayout.playerIDs(sources: reported, inEffectPID: 31)
            suite.expect(first == [31, 21, 41],
                         "the player in effect leads, and the others follow by process")
            // A command is not a choice of player, so the players and the player
            // in effect are the same afterwards, and the order is the same.
            suite.expect(NotchDashboardLayout.playerIDs(sources: reported, inEffectPID: 31) == first,
                         "the order is the players, not the last control used")
            suite.expect(!first.dropFirst().contains(31),
                         "a player is not drawn twice, so no card repeats the card above")
            // Only a choice of player moves a card, and moves it once.
            suite.expect(NotchDashboardLayout.playerIDs(sources: reported, inEffectPID: 41) == [41, 31, 21],
                         "a chosen player leads once, and the rest keep their order")
            suite.expect(NotchDashboardLayout.playerIDs(sources: reported, inEffectPID: nil) == [31, 21, 41],
                         "with no player in effect the players keep their own order")
        }

        suite.run("every player's card is drawn from that player's own report") {
            let cover = Data((0..<64).map { UInt8($0) })
            let entries: [[String: Any]] = [
                ["pid": 21, "bundleIdentifier": "com.apple.Safari", "isMusicApp": false, "isPlaying": true,
                 "hasTrack": true, "displayName": "Safari", "title": "Big Buck Bunny", "artist": "Blender",
                 "elapsed": 57.0, "duration": 600.0, "itemIdentifier": "video-1",
                 "artworkBase64": cover.base64EncodedString()],
                ["pid": 31, "bundleIdentifier": "com.netease.163music", "isMusicApp": true, "isPlaying": false,
                 "hasTrack": true, "displayName": "NetEaseMusic", "title": "当年情", "artist": "Leslie Cheung",
                 "elapsed": 150.0, "duration": 254.0],
                // A player that reports a song with no cover and no position.
                ["pid": 41, "bundleIdentifier": "com.spotify.client", "isMusicApp": true, "isPlaying": true,
                 "hasTrack": true, "title": "Memorable Trip"],
                // A player that reports nonsense is read as reporting nothing.
                ["pid": 51, "bundleIdentifier": "com.example.player", "isMusicApp": true, "isPlaying": true,
                 "hasTrack": true, "title": String(repeating: "n", count: 4_000), "artist": "  ",
                 "elapsed": -5.0, "duration": Double.nan,
                 "artworkBase64": Data(repeating: 7, count: NotchPlaybackSource.maximumArtworkBytes + 1)
                    .base64EncodedString()],
            ]
            let sources = NotchPlaybackSource.decode(entries)
            suite.expect(sources.count == 4, "every reported player is read")
            let video = sources[0], song = sources[1], bare = sources[2], junk = sources[3]
            suite.expect(video.title == "Big Buck Bunny" && video.artist == "Blender"
                             && video.elapsed == 57 && video.duration == 600,
                         "a player's own title, artist and position are read from it")
            suite.expect(video.artworkData == cover && video.itemIdentifier == "video-1",
                         "a player's own cover is read with the recording it belongs to")
            suite.expect(song.title == "当年情" && song.artist == "Leslie Cheung" && song.artworkData == nil,
                         "a player that reports no cover is read without inventing one")
            suite.expect(bare.title == "Memorable Trip" && bare.artist == nil && bare.elapsed == nil
                             && bare.duration == nil,
                         "a player that reports no artist and no position is read as reporting none")
            suite.expect(junk.title == nil && junk.artist == nil && junk.elapsed == nil
                             && junk.duration == nil && junk.artworkData == nil,
                         "a text over its bound, a position that is not one, and an oversized cover are refused")
            suite.expect(junk.hasTrack, "a player that reports a song is still a player, unreadable fields and all")
        }

        suite.run("a reading's own click opens its page, not the panel") {
            // The menu bar's indicator of a reading and the same reading's card
            // on the System page are one route: the reading's detail page, with
            // the panel, the sections and the dashboard behind it.
            suite.expect(NotchDashboardLayout.showsMetricDetail(metricSelected: true, appPanel: true),
                         "a reading opened from the panel is the reading's page, not the panel")
            suite.expect(NotchDashboardLayout.showsMetricDetail(metricSelected: true, appPanel: false),
                         "the same reading opened in the island is the same page")
            suite.expect(!NotchDashboardLayout.showsMetricDetail(metricSelected: false, appPanel: true),
                         "with no reading named, the panel is the panel")
        }

        suite.run("a card's mark opens the app that plays") {
            // A process that runs and answers to the app the cover names is
            // brought forward, so no second copy of the app is started; an app
            // that is not running, or a process that belongs to a different
            // app, is opened by the bundle the adapter named.
            suite.expect(NotchDashboardSupport.appOpening(pid: 7, isRunning: true,
                                                          bundleIdentifier: "com.spotify.client",
                                                          runningBundleIdentifier: "com.spotify.client")
                             == .activate(pid: 7),
                         "a running player is activated, not launched again")
            suite.expect(NotchDashboardSupport.appOpening(pid: 7, isRunning: true,
                                                          bundleIdentifier: "com.spotify.client",
                                                          runningBundleIdentifier: "com.apple.Music")
                             == .open(bundleIdentifier: "com.spotify.client"),
                         "a process id handed out again to another app is not the player, and is not raised")
            suite.expect(NotchDashboardSupport.appOpening(pid: 7, isRunning: true,
                                                          bundleIdentifier: "com.NETEASE.163music",
                                                          runningBundleIdentifier: "com.netease.163music")
                             == .activate(pid: 7),
                         "a bundle name written in another case is the same app")
            suite.expect(NotchDashboardSupport.appOpening(pid: 7, isRunning: true,
                                                          bundleIdentifier: nil,
                                                          runningBundleIdentifier: nil) == .activate(pid: 7),
                         "a player that is a process and not an app bundle is raised by its process")
            suite.expect(NotchDashboardSupport.appOpening(pid: 7, isRunning: false,
                                                          bundleIdentifier: "com.netease.163music")
                             == .open(bundleIdentifier: "com.netease.163music"),
                         "a player whose process went is opened by the bundle the adapter named")
            suite.expect(NotchDashboardSupport.appOpening(pid: -1, isRunning: false, bundleIdentifier: nil) == .none,
                         "a card that names no app asks for nothing")
            suite.expect(NotchDashboardSupport.appOpening(pid: 7, isRunning: false, bundleIdentifier: "") == .none,
                         "an empty bundle name is not a way to an app")
            suite.expect(NotchDashboardSupport.appOpening(pid: -1, isRunning: false,
                                                          bundleIdentifier: "com.apple.Music")
                             == .open(bundleIdentifier: "com.apple.Music"),
                         "a track whose app is not running at all is asked of the system, and a click that can find nothing does nothing")
        }

        suite.run("the timer's pause and close are one control") {
            // The circle is the control: its plate, its highlight and its hit
            // area are all of one diameter, and both of the card's buttons are
            // drawn from one view at one size.
            suite.expect(NotchDashboardLayout.timerControlSide == 28
                             && NotchDashboardLayout.timerControlCorner == NotchDashboardLayout.timerControlSide / 2,
                         "the timer's two controls share one box, whose corner is the radius of its circle")
            suite.expect(NotchDashboardLayout.transportMarkSide == 22
                             && NotchDashboardLayout.transportCorner == NotchDashboardLayout.transportMarkSide / 2
                             && NotchDashboardLayout.transportSpacing > 0,
                         "a player's three marks are circles of one diameter, at one gap, on every card")
            // The card is the two controls and the clock, at one edge on every
            // side: its height is the edge, the control, and the edge again.
            suite.expect(NotchDashboardLayout.timerCardHeight
                             == NotchDashboardLayout.activityCardPadding * 2
                             + NotchDashboardLayout.activityArtwork - 12,
                         "the timer's card is measured to its content, not padded at the top")
            suite.expect(NotchDashboardLayout.timerControlSide <= NotchDashboardLayout.timerCardHeight
                             - 2 * NotchDashboardLayout.activityCardPadding,
                         "the controls sit inside the card's own edge")
        }

        suite.run("the countdown's card offers its restart, the other modes do not") {
            // The marks are one decision, read in row order: a countdown is
            // started again, held and ended, and the restart is the first of
            // them. A Pomodoro cycle and a stopwatch keep the marks they have
            // always had, so their cards grow no button of their own.
            suite.expect(NotchDashboardLayout.timerCardControls(countdown: true) == [.reset, .pause, .close],
                         "a countdown's card resets, holds and ends its session, in that row order")
            suite.expect(NotchDashboardLayout.timerCardControls(countdown: false) == [.pause, .close],
                         "a Pomodoro cycle and a stopwatch keep the two marks they had")
            suite.expect(NotchDashboardLayout.timerCardControls(countdown: true).first == .reset,
                         "the restart sits left of the mark that holds the clock, as the reference lays it out")
            // Three marks of one diameter at one gap, inside the card's edge,
            // still fit the page's width beside the clock.
            let marks = 3 * NotchDashboardLayout.timerControlSide + 2 * NotchDashboardLayout.timerControlGap
            suite.expect(marks < NotchDashboardLayout.naturalContentWidth
                             - 2 * NotchDashboardLayout.activityCardPadding - 120,
                         "the three marks, at their gap and edges, leave the clock its room")
        }

        suite.run("the page keeps its readings and its sections whatever runs") {
            let width = NotchDashboardLayout.naturalContentWidth
            let grid = NotchDashboardLayout.metricsHeight(tiles: 8)
            let sections = NotchDashboardLayout.exploreHeight(count: 7, width: width)
            func rows(_ activities: [NotchDashboardActivity]) -> [CGFloat] {
                NotchDashboardLayout.sectionHeights(activities: activities, calendar: true, metrics: 8,
                                                    exploreCount: 7, width: width, primaryPlayerID: 7)
            }
            let none = rows([])
            let one = rows([.player(id: 7)])
            let many = rows([.player(id: 7), .player(id: 9), .player(id: 11), .timer])
            for (name, heights) in [("nothing running", none), ("one player", one), ("three players", many)] {
                suite.expect(heights.contains(grid), "the whole grid of readings is on the page: \(name)")
                suite.expect(heights.contains(sections), "the way to the sections is on the page: \(name)")
                suite.expect(heights.first == NotchDashboardLayout.calendarCardHeight,
                             "the month leads the page: \(name)")
                suite.expect(heights.last == sections, "the page ends at the sections, at every size: \(name)")
            }
            // The players add their own section; the month, the grid and the way
            // to the sections are the page at every size.
            suite.expect(many.count == none.count + 1
                             && one.count == none.count + 1,
                         "the players add one section between the month and the grid, at every count")
            suite.expect(many.first == none.first && many.last == none.last,
                         "the month leads and the sections close the page, with three players as with none")
        }

        suite.run("the page's players are the players the system reports") {
            let safari = NotchPlaybackSource(pid: 21, bundleIdentifier: "com.apple.Safari", isMusicApp: false,
                                             isPlaying: true, hasTrack: true, displayName: "Safari")
            let netease = NotchPlaybackSource(pid: 31, bundleIdentifier: "com.netease.163music", isMusicApp: true,
                                              isPlaying: true, hasTrack: true, displayName: "NetEaseMusic")
            let spotify = NotchPlaybackSource(pid: 41, bundleIdentifier: "com.spotify.client", isMusicApp: true,
                                              isPlaying: false, hasTrack: true, displayName: "Spotify")
            let silent = NotchPlaybackSource(pid: 51, bundleIdentifier: "com.apple.Music", isMusicApp: true,
                                             isPlaying: false, hasTrack: false)
            let reported = [netease, safari, spotify, silent]
            // A card is media being heard. The player in effect leads, and a
            // browser that is playing is a player like any other; a player
            // paused with its track still named, and a process with nothing at
            // all, are not on the page.
            suite.expect(NotchDashboardLayout.playerIDs(sources: reported, inEffectPID: 31) == [31, 21],
                         "the player in effect, then the others that are playing, and no paused session")
            suite.expect(NotchDashboardLayout.playerIDs(sources: reported, inEffectPID: nil) == [31, 21],
                         "with none in effect, every player playing now is on the page")
            suite.expect(NotchDashboardLayout.playerIDs(sources: reported, inEffectPID: 21) == [21, 31],
                         "the card above is the first, and the rest keep their order")
            suite.expect(NotchDashboardLayout.playerIDs(sources: reported, inEffectPID: 41) == [31, 21],
                         "a player in effect that has paused leads no card of its own")
            suite.expect(NotchDashboardLayout.playerIDs(sources: [spotify], inEffectPID: 41).isEmpty,
                         "a lone paused player leaves the page with no player card")
            // A page of four players is the whole list, and the fifth is not asked.
            let many = reported + [NotchPlaybackSource(pid: 61, bundleIdentifier: "com.apple.podcast",
                                                       isMusicApp: true, isPlaying: true, hasTrack: true)]
            suite.expect(NotchDashboardLayout.playerIDs(sources: many, inEffectPID: 31) == [31, 21, 61],
                         "the page carries the players it has room for, in order")
            suite.expect(NotchDashboardLayout.playerIDs(sources: [], inEffectPID: 31).isEmpty,
                         "what the adapter does not report, the page does not draw")
            // The same players reported in the same order answer the same way,
            // and only the player in effect moving changes the order.
            suite.expect(NotchDashboardLayout.playerIDs(sources: reported, inEffectPID: 31)
                             == NotchDashboardLayout.playerIDs(sources: reported, inEffectPID: 31),
                         "the same players in the same report give the same cards, every time")
            // Playing with a track, and playing with none: a player that says
            // it plays and names nothing has no card to draw.
            let playingNothing = NotchPlaybackSource(pid: 71, bundleIdentifier: "com.apple.Music",
                                                     isMusicApp: true, isPlaying: true, hasTrack: false)
            suite.expect(NotchDashboardLayout.playerIDs(sources: [playingNothing], inEffectPID: 71).isEmpty,
                         "a player playing nothing is given no card")
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
                             == NotchDashboardLayout.timerCardHeight + NotchDashboardLayout.cardSpacing,
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
            suite.expect(idle.count == 2 && busy.count == 3,
                         "one height per section, the activity cards measured only when something runs")
            // A section is its content and nothing else: no label line, no
            // card insets of its own. That is what keeps the island exactly as
            // tall as the page it holds, with no empty space at its bottom.
            suite.expect(idle[0] == NotchDashboardLayout.metricsHeight(tiles: 8),
                         "the grid is measured at its rows, and leads the page when nothing runs")
            suite.expect(idle[1] == NotchDashboardLayout.exploreHeight(count: 7, width: width),
                         "the sections' marks are measured at their rows")
            suite.expect(busy[0] == NotchDashboardLayout.liveActivitiesHeight(cards),
                         "the activity section is measured at its three cards")
            // The levels are not among the page's heights: they are the island's
            // top row, which the island's geometry measures with its insets.
            suite.expect(!NotchDashboardLayout.sectionHeights(activities: cards, calendar: true, metrics: 8,
                                                              exploreCount: 7, width: width)
                             .contains(NotchDashboardLayout.quickControlsHeight),
                         "the page measures no row of levels, so the island adds no row of empty space")
            suite.expect(NotchDashboardLayout.contentHeight(activities: cards, calendar: false, metrics: 8,
                                                             exploreCount: 7, width: width)
                             == busy.reduce(0, +) + NotchDashboardLayout.sectionSpacing * 2,
                         "the page is its sections and the gaps between them")
            // Each card, player or timer, adds exactly its own height.
            suite.expect(NotchDashboardLayout.liveActivitiesHeight([.player(id: 7)], primaryPlayerID: 7)
                             + NotchDashboardLayout.cardSpacing
                             + NotchDashboardLayout.playerCardHeight
                             == NotchDashboardLayout.liveActivitiesHeight([.player(id: 7), .player(id: 9)],
                                                                          primaryPlayerID: 7),
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
            let side = (width - 210) / 2
            // Quick Controls: the island's row, one compact level on each side
            // of the camera, each a mark, a bar and its chooser.
            suite.expect(NotchDashboardLayout.quickControlsHeight >= 24
                             && NotchDashboardLayout.quickControlsHeight <= 34,
                         "the row is tall enough for a slider a pointer can hold, and no taller")
            suite.expect(NotchDashboardLayout.quickControlBarWidth <= 140,
                         "a level's bar stays compact: \(NotchDashboardLayout.quickControlBarWidth)")
            suite.expect(2 * NotchDashboardLayout.quickControlWidth(width: side)
                             + 210 <= width,
                         "both levels fit the row, one on each side of the camera")
            // Monitoring: four columns, two rows, each tile a label, a reading
            // and a meter, read at a glance and not crowded against its edge.
            suite.expect(NotchDashboardLayout.metricTileHeight >= 60
                             && NotchDashboardLayout.metricTilePadding == 10,
                         "a tile has room for its label, its reading and its meter, and one edge")
            suite.expect(NotchDashboardLayout.activityCardHeight >= 70
                             && NotchDashboardLayout.activityCardPadding == 10,
                         "a card is tall enough for its words, its times and its buttons, and one edge")
            // The whole page, at its fullest, is measured against the island's
            // tallest page, so the readings and the way to the sections are on
            // the page by default and not under a scroll the person has to find.
            let crowded: [NotchDashboardActivity] = [.player(id: 7), .player(id: 9), .player(id: 11), .timer]
            let page = NotchDashboardLayout.contentHeight(activities: crowded, calendar: true, metrics: 8,
                                                          exploreCount: 7, width: width, primaryPlayerID: 7)
            suite.expect(page <= NotchDashboardLayout.maxPageHeight(screenHeight: 1084),
                         "the month, three players, the timer, the readings and the sections fit the island: \(page)")
            suite.expect(NotchDashboardLayout.liveActivitiesHeight(crowded, primaryPlayerID: 7)
                             == NotchDashboardLayout.activityCardHeight
                             + 2 * NotchDashboardLayout.playerCardHeight + NotchDashboardLayout.timerCardHeight
                             + 3 * NotchDashboardLayout.cardSpacing,
                         "the players in effect is tall, the others are rows, the timer is its clock")
            suite.expect(NotchDashboardLayout.timerCardHeight
                             == NotchDashboardLayout.activityCardPadding * 2 + NotchDashboardLayout.activityArtwork - 12,
                         "the timer's card is its clock with the same edge on every side")
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
            suite.expect(short.height == geometry.chromeHeight + 124,
                         "the island is the reading it measured, plus its chrome")
            suite.expect(long.height == geometry.surfaceCeiling && geometry.scrolls(contentHeight: 10_000),
                         "a detail taller than the display stops at its 80%, and scrolls to its last row")
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
