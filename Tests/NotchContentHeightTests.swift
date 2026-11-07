// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's one height rule, shared by every page and every display: a page
/// is as tall as the content it draws, and at most 80% of the display that
/// hosts it, and scrolls when it measures more.
///
/// These are the observable promises of that rule. A page that sizes itself by
/// a height of its own, a preset that caps a page below what it draws, a long
/// page that keeps growing past the display, a short page padded out to a
/// preset, a page that keeps the height its content had before it shrank, an
/// island that uses the primary display's height on a second display, and a
/// page whose header or margins are left out of its height all fail here,
/// whatever the views look like.
enum NotchContentHeightTests {
    /// A display of this height, with a menu bar of the usual height. The
    /// island hangs from the display's top edge, as it does on screen.
    private static func display(_ height: CGFloat, width: CGFloat = 1440, notched: Bool = false,
                                layout: NotchSize = .compact, customHeight: Double = NotchSize.defaultHeight) -> NotchGeometry {
        NotchGeometry(screen: CGRect(x: 0, y: 0, width: width, height: height),
                      safeAreaTop: notched ? 32 : 0, cameraWidth: notched ? 200 : 0,
                      layout: layout, menuBarHeight: 24, customHeight: customHeight)
    }

    /// Pages whose height follows counts the island can read: more of their
    /// content is a taller page, up to the display's limit.
    private static var measuredPages: [(module: NotchModule, items: NotchPageContent)] {
        let many = NotchPageContent(clipboardEntries: 60, clipboardSearch: true, clipboardComfortable: true,
                                    notificationCards: 60, downloadCards: 60, shelfTiles: 60, captureTiles: 60,
                                    systemCards: 60, tools: 60, mixerMicrophone: true, calendarMonth: true)
        return [(.clipboard, many), (.notifications, many), (.downloads, many), (.files, many),
                (.captures, many), (.system, many), (.tools, many)]
    }

    static func run(_ suite: TestSuite) {
        suite.run("the panel is as tall as its content, up to 80% of the display") {
            // Scenario A: a short page stays short, at exactly its content.
            let short = NotchHeightPolicy.resolve(contentHeight: 400, chromeHeight: 0, displayHeight: 1000)
            suite.expect(short.surfaceHeight == 400 && !short.scrolls,
                         "400 of content on a 1000 display is a 400 panel, not a padded one: \(short.surfaceHeight)")
            // Scenario B: a medium page grows to its own height.
            let medium = NotchHeightPolicy.resolve(contentHeight: 650, chromeHeight: 0, displayHeight: 1000)
            suite.expect(medium.surfaceHeight == 650 && !medium.scrolls,
                         "650 of content is a 650 panel: \(medium.surfaceHeight)")
            // Scenario C: a long page stops at the limit and scrolls.
            let long = NotchHeightPolicy.resolve(contentHeight: 1200, chromeHeight: 0, displayHeight: 1000)
            suite.expect(long.surfaceHeight == 800 && long.scrolls && long.atMaximum,
                         "1200 of content on a 1000 display stops at 800 and scrolls: \(long.surfaceHeight)")
            // 80% is a maximum, never a default: the limit is only reached by
            // content that needs it.
            suite.expect(NotchHeightPolicy.maximumHeight(displayHeight: 1000) == 800
                             && NotchHeightPolicy.maximumHeight(displayHeight: 900) == 720
                             && NotchHeightPolicy.maximumHeight(displayHeight: 1080) == 864,
                         "the limit is four fifths of the display's own height")
            // Nothing is added to a page that fits, so no empty space appears.
            for content in [1.0, 60, 400, 650, 799, 800] {
                let resolved = NotchHeightPolicy.resolve(contentHeight: CGFloat(content), chromeHeight: 0,
                                                         displayHeight: 1000)
                suite.expect(resolved.surfaceHeight == min(CGFloat(content), 800) && !resolved.scrolls,
                             "content of \(content) fills exactly that much of the panel")
            }
        }

        suite.run("the island's chrome is part of the height, and inside the limit") {
            // The row the island opens with, its gap and its bottom margin are
            // measured with the page, and the limit covers the whole surface.
            let geometry = display(1000, notched: true)
            let chrome = geometry.chromeHeight
            suite.expect(chrome == geometry.headerTopInset + geometry.headerChromeHeight
                             && chrome >= geometry.safeContentTop + NotchLayout.bottomInset,
                         "the chrome is the camera's clearance, the row, its gap and the bottom margin: \(chrome)")
            suite.expect(chrome >= NotchLayout.headerHeight + NotchLayout.spacing + NotchLayout.bottomInset,
                         "a page with a row counts the row, its gap and the margin under the page")
            let natural = NotchNaturalContent.height(module: .clipboard,
                                                     items: NotchPageContent(clipboardEntries: 2, clipboardComfortable: true),
                                                     width: geometry.contentWidth)
            let resolved = geometry.resolveHeight(contentHeight: natural)
            suite.expect(resolved.surfaceHeight == chrome + natural && !resolved.scrolls,
                         "the panel is the page's measure plus the chrome around it")
            suite.expect(resolved.ceiling == NotchHeightPolicy.maximumHeight(displayHeight: 1000) - chrome,
                         "the page's limit is the display's 80% less the chrome, so the surface never passes 800")
            // A page taller than the page the display allows is drawn at the
            // limit, and its surface is exactly the 80%.
            let long = geometry.resolveHeight(contentHeight: 4000)
            suite.expect(long.surfaceHeight == NotchHeightPolicy.maximumHeight(displayHeight: 1000) && long.scrolls,
                         "a long page on a notched display fills exactly 80%: \(long.surfaceHeight)")
            suite.expect(geometry.contentSize(for: geometry.expandedSize(module: .clipboard,
                                                                         content: NotchPageContent(clipboardEntries: 40)))
                             .height == geometry.contentCeiling,
                         "the page is laid out at the tallest height the display allows, so it scrolls to its last row")
        }

        suite.run("a page that loses content shrinks the island") {
            // Scenario D: the rule reads what the page has now, and has no
            // memory of the height its content measured before.
            let geometry = display(1000)
            let chrome = geometry.chromeHeight
            let full = NotchPageContent(clipboardEntries: 40, clipboardComfortable: true)
            let one = NotchPageContent(clipboardEntries: 1, clipboardComfortable: true)
            let tall = geometry.expandedSize(module: .clipboard, content: full)
            let short = geometry.expandedSize(module: .clipboard, content: one)
            suite.expect(tall.height == NotchHeightPolicy.maximumHeight(displayHeight: 1000),
                         "forty cards overflow the display, so the island sits at the limit")
            suite.expect(short.height == chrome + NotchLayout.clipboardCardHeight,
                         "one card leaves a one-card island: \(short.height)")
            let empty = geometry.expandedSize(module: .clipboard, content: .empty)
            suite.expect(empty.height == chrome + NotchLayout.emptyHeight,
                         "no cards leaves the empty page, which names itself: \(empty.height)")
            // The same page measured apart from the panel: the count is the only
            // thing that changes the height.
            var entries = 40
            var previous = CGFloat.greatestFiniteMagnitude
            while entries > 0 {
                let items = NotchPageContent(clipboardEntries: entries, clipboardComfortable: true)
                let height = geometry.expandedSize(module: .clipboard, content: items).height
                suite.expect(height <= previous, "removing cards never makes the island taller: \(entries)")
                previous = height
                entries -= 7
            }
            // A search that narrows the list narrows the island with it.
            let searched = geometry.expandedSize(module: .clipboard, content: NotchPageContent(clipboardEntries: 2,
                                                                                              clipboardSearch: true))
            let browsed = geometry.expandedSize(module: .clipboard, content: NotchPageContent(clipboardEntries: 2))
            suite.expect(searched.height == browsed.height + NotchLayout.clipboardSearchHeight + NotchLayout.rowSpacing,
                         "the search field is a row of the page, and the island counts it")
        }

        suite.run("each display gives its own 80%") {
            // Scenario E: displays of different heights, and the island moving
            // between them. The primary display's height is never assumed.
            let items = NotchPageContent(clipboardEntries: 40, clipboardComfortable: true)
            for height in [600.0, 800, 1000, 1080, 1440, 2160] {
                let geometry = display(CGFloat(height))
                let cap = NotchHeightPolicy.maximumHeight(displayHeight: CGFloat(height))
                let tall = geometry.expandedSize(module: .clipboard, content: items)
                suite.expect(tall.height == cap,
                             "a long page on a \(Int(height)) display is \(Int(cap)) tall, not \(tall.height)")
                suite.expect(geometry.surfaceCeiling <= cap && geometry.contentCeiling == cap - geometry.chromeHeight,
                             "the \(Int(height)) display's limit is its own")
                // A short page is short on every display: the limit is not a
                // height the panel fills.
                let one = geometry.expandedSize(module: .clipboard,
                                                content: NotchPageContent(clipboardEntries: 1, clipboardComfortable: true))
                suite.expect(one.height == geometry.chromeHeight + NotchLayout.clipboardCardHeight,
                             "one card is a one-card island on a \(Int(height)) display too")
            }
            // A smaller display shrinks the same page; a bigger one lets it grow.
            let tall = display(1000), small = display(500)
            suite.expect(tall.expandedSize(module: .system, systemCards: 40).height
                             > small.expandedSize(module: .system, systemCards: 40).height,
                         "the same page is taller on the taller display, at each display's own limit")
            // The gallery is sized by the display it is on as well.
            suite.expect(display(1000).sectionPickerSize(count: 40).height == 800
                             && display(600).sectionPickerSize(count: 40).height == 480,
                         "the gallery stops at each display's 80%")
        }

        suite.run("every page shares the one sizing rule") {
            // Scenario F: no page sizes itself by a rule of its own, and no
            // page's fixed height overrides the shared policy.
            let height: CGFloat = 1000
            let geometry = display(height)
            let cap = NotchHeightPolicy.maximumHeight(displayHeight: height)
            for module in NotchModule.allCases {
                let size = geometry.expandedSize(module: module, systemCards: 60, toolCount: 60,
                                                 content: NotchPageContent(clipboardEntries: 60,
                                                                           notificationCards: 60,
                                                                           downloadCards: 60,
                                                                           shelfTiles: 60, captureTiles: 60,
                                                                           systemCards: 60, tools: 60,
                                                                           calendarMonth: true))
                suite.expect(size.height <= cap, "\(module.rawValue) never passes the display's 80%: \(size.height)")
                suite.expect(size.height >= geometry.chromeHeight + NotchPageFloor.contentHeight(module: module),
                             "\(module.rawValue) keeps its shortest usable page")
                suite.expect(size.height.isFinite && size.height > 0, "\(module.rawValue) has a height")
            }
            for (module, items) in measuredPages {
                let size = geometry.expandedSize(module: module, systemCards: 60, toolCount: 60, content: items)
                suite.expect(size.height == cap,
                             "\(module.rawValue) stops at the limit when it has more to draw than the display holds: \(size.height)")
                suite.expect(geometry.scrolls(contentHeight: geometry.naturalContentHeight(module: module, systemCards: 60,
                                                                                            toolCount: 60, content: items),
                                              minimumContentHeight: NotchPageFloor.contentHeight(module: module)),
                             "\(module.rawValue) scrolls at the limit, so its last item is reachable")
            }
            // A page's floor is a floor, not a height: each page's shortest
            // usable page is its own complete piece of content, and the display's
            // limit stays above every floor.
            for module in NotchModule.allCases {
                let floor = NotchPageFloor.contentHeight(module: module)
                suite.expect(floor <= geometry.contentCeiling,
                             "\(module.rawValue)'s floor fits the display, so it never pushes past the limit")
            }
            // Details and panels follow the same rule as the pages.
            let short = geometry.expandedSize(module: .system, detail: true, detailHeight: 240)
            let long = geometry.expandedSize(module: .system, detail: true, detailHeight: 9000)
            suite.expect(short.height == geometry.chromeHeight + 244, "a measured detail is as tall as the reading")
            suite.expect(long.height == cap && geometry.scrolls(contentHeight: 9000),
                         "a long detail stops at the limit and scrolls")
            suite.expect(geometry.expandedSize(module: .tools, panel: true).height <= cap,
                         "the app panel is inside the same limit")
            // The dashboard is a page like every other, not a page with its own
            // ceiling: it grows with its cards and stops at the display.
            suite.expect(geometry.dashboardSize(content: 300, width: 300).height == geometry.chromeHeight + 300,
                         "the dashboard is as tall as its sections")
            suite.expect(geometry.dashboardSize(content: 4000, width: 300).height == cap,
                         "the dashboard stops at the display's 80%")
            suite.expect(geometry.dashboardContentLimit == geometry.contentCeiling,
                         "the dashboard's page limit is the shared content limit")
        }

        suite.run("pages measure content, not a preset's height") {
            // A preset is a floor beneath a page, never a ceiling over it: the
            // same page with more content is taller on the same preset.
            let compact = display(1000, layout: .compact)
            let spacious = display(1000, layout: .spacious)
            for geometry in [compact, spacious] {
                let one = geometry.expandedSize(module: .system, systemCards: 1)
                let six = geometry.expandedSize(module: .system, systemCards: 6)
                let many = geometry.expandedSize(module: .system, systemCards: 40)
                suite.expect(one.height < six.height && six.height < many.height,
                             "the readings the grid draws grow the island, past any preset's height")
                suite.expect(many.height == NotchHeightPolicy.maximumHeight(displayHeight: 1000),
                             "and it stops at the display's limit, not the preset's")
                // The rail's rows and the island's height agree, so the page
                // never reserves a row it cannot draw.
                let grid = NotchLayout.railHeight(rows: geometry.systemRows(cards: 40),
                                                  rowHeight: NotchLayout.systemCardHeight, spacing: NotchLayout.rowSpacing)
                suite.expect(geometry.contentSize(for: many).height >= grid
                                 || geometry.scrolls(contentHeight: grid),
                             "the grid's rows are drawn whole, or reached by scrolling: never dropped")
            }
            // A height chosen by hand is a limit a person chose, under the
            // display's 80%: it never raises the rule's limit, and a short page
            // under it is still short, not padded to the chosen size.
            let custom = display(1000, layout: .custom, customHeight: 300)
            suite.expect(custom.surfaceCeiling == 300,
                         "a height chosen by hand is this island's limit, under the display's 80%")
            suite.expect(custom.expandedSize(module: .clipboard, content: NotchPageContent(clipboardEntries: 60)).height == 300
                             && custom.scrolls(contentHeight: 4000),
                         "a long page stops at the chosen limit and scrolls to its last card")
            suite.expect(custom.expandedSize(module: .clipboard, content: .empty).height
                             == custom.chromeHeight + NotchLayout.emptyHeight,
                         "a page with less to draw stays short under the chosen limit")
            // The rule, not the chosen number, wins where the display is the
            // shorter of the two.
            let cramped = display(400, layout: .custom, customHeight: 600)
            suite.expect(cramped.surfaceCeiling == NotchHeightPolicy.maximumHeight(displayHeight: 400),
                         "a chosen height taller than the display's 80% gives way to the rule")
            // Tools and the gallery, which are rails like the pages, agree too.
            suite.expect(compact.toolRows(count: 40) > compact.toolRows(count: 4),
                         "the launcher's rail draws more rows as marks are added")
            suite.expect(compact.sectionRows(count: 40) > compact.sectionRows(count: 1),
                         "the gallery draws more rows as sections are added")
            suite.expect(compact.sectionRows(count: 40) <= 40, "and no more rows than there are tiles")
        }

        suite.run("the rule's edges: no content, no display, safe areas, resize") {
            // Zero content: the island is its chrome, with nothing empty inside.
            let bare = NotchHeightPolicy.resolve(contentHeight: 0, chromeHeight: 100, displayHeight: 1000)
            suite.expect(bare.surfaceHeight == 100 && bare.contentHeight == 0 && !bare.scrolls,
                         "a page with no content leaves the chrome and nothing else: \(bare.surfaceHeight)")
            // Zero, negative, and unknown display heights are handled, not
            // trusted: the caller's floor decides, and nothing divides by them.
            for height in [0.0, -1, Double.nan, Double.infinity] {
                let resolved = NotchHeightPolicy.resolve(contentHeight: 500, chromeHeight: 60, displayHeight: CGFloat(height))
                suite.expect(resolved.contentHeight <= resolved.ceiling && resolved.surfaceHeight.isFinite
                                 && resolved.surfaceHeight >= 60,
                             "a display of \(height) yields a finite surface at least the chrome: \(resolved.surfaceHeight)")
            }
            suite.expect(NotchHeightPolicy.maximumHeight(displayHeight: 0) == 0
                             && NotchHeightPolicy.maximumHeight(displayHeight: .nan) == 0,
                         "an unknown display has no height to give")
            // A display too short for a page's floor keeps the limit, not the
            // floor: the page scrolls, and the island stays on the display.
            let tiny = display(200)
            for module in NotchModule.allCases {
                suite.expect(tiny.expandedSize(module: module).height <= tiny.surfaceCeiling,
                             "\(module.rawValue) stays inside a display that is shorter than its floor")
            }
            // Resizing a window onto a shorter display recomputes the same page.
            let tall = display(1400), short = display(700)
            let items = NotchPageContent(notificationCards: 30)
            suite.expect(tall.expandedSize(module: .notifications, content: items).height == 1120
                             && short.expandedSize(module: .notifications, content: items).height == 560,
                         "the page follows the display it moved to, at that display's 80%")
            // A page with a row of its own and one without both start at the
            // island's edge, and neither loses its bottom margin.
            // A page with a row of its own and one beside a camera both keep
            // the camera's clearance and their bottom margin in the height.
            let notched = display(1000, notched: true)
            let rowBelow = display(1000, width: 420, notched: true)
            suite.expect(rowBelow.headerTopInset == rowBelow.safeContentTop
                             && rowBelow.chromeHeight >= rowBelow.safeContentTop + NotchLayout.bottomInset,
                         "a camera's safe area is inside the island's height, not left above it")
            suite.expect(notched.chromeHeight >= notched.safeContentTop + NotchLayout.bottomInset,
                         "a row beside the camera still keeps the camera's clearance and the margin below the page")
            suite.expect(notched.resolveHeight(contentHeight: 500).surfaceHeight
                             == notched.chromeHeight + 500,
                         "the page sits between the island's top clearance and its bottom margin")
            // Dynamic content: every count the island reads moves the height,
            // and the height is never larger than what the counts measure.
            for count in [0, 1, 2, 5, 12, 60] {
                let size = notched.expandedSize(module: .captures,
                                                content: NotchPageContent(captureTiles: count))
                let natural = NotchNaturalContent.rail(count: count, itemWidth: NotchLayout.captureCardWidth,
                                                       itemHeight: NotchLayout.captureCardHeight,
                                                       spacing: NotchLayout.cardSpacing, width: notched.contentWidth)
                suite.expect(size.height == notched.chromeHeight + min(max(natural, 0), notched.contentCeiling),
                             "\(count) captures measure \(natural), and the island is that page: \(size.height)")
            }
        }
    }
}
