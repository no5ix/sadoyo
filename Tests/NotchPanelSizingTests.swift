// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The one sizing rule the System Monitoring pages share. A panel is as tall
/// as the content it draws, up to four fifths of the display it sits on, and
/// past that its content scrolls inside it with every row of itself drawn.
///
/// These are the observable promises: a short list of applications makes a
/// short panel, a long list makes a panel that holds the list to its last
/// entry, a taller display raises the ceiling, and no page cuts an
/// application, a card, or a section off in the middle.
enum NotchPanelSizingTests {
    static func run(_ suite: TestSuite) {
        func display(height: CGFloat, notch: Bool = true, layout: NotchSize = .compact,
                     customHeight: Double = NotchSize.defaultHeight, quickAccess: CGFloat = 0,
                     width: CGFloat = 1470) -> NotchGeometry {
            var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: width, height: height),
                                         safeAreaTop: notch ? 32 : 0, cameraWidth: notch ? 180 : 0,
                                         layout: layout, menuBarHeight: 24, compactSideRoom: 200,
                                         customHeight: customHeight)
            geometry.quickAccessBottomInset = quickAccess
            return geometry
        }

        suite.run("the panel's ceiling follows the display it is drawn on") {
            suite.expect(NotchPanelSizing.maximumHeightFraction == 0.8,
                         "four fifths of the display is the shared ceiling")
            // A display 1,000 points tall holds a panel 800 points tall.
            suite.expect(abs(display(height: 1_000).maximumPanelHeight - 800) < 0.001,
                         "a 1,000-point display gives a panel of 800")
            for height in [900, 1_080, 1_117, 1_440, 1_800, 2_160] as [CGFloat] {
                let geometry = display(height: height)
                suite.expect(abs(geometry.maximumPanelHeight - height * 0.8) < 0.001,
                             "the ceiling is four fifths of a \(Int(height))-point display")
                suite.expect(abs(geometry.maximumPanelContentHeight
                                 - (geometry.maximumPanelHeight - geometry.headerTopInset - geometry.headerChromeHeight)) < 0.001,
                             "the content's ceiling leaves the header and the page's margins on \(Int(height))")
            }
            // The menu bar, the safe area and the floating buttons are the
            // room the display keeps, so a display too short for four fifths
            // of itself is bounded by that room instead.
            let shallow = display(height: 200)
            suite.expect(shallow.maximumPanelHeight < shallow.screen.height * 0.8
                         && shallow.maximumPanelHeight == shallow.screen.height - NotchGeometry.displayEdgeReserve,
                         "a display shorter than the room it keeps bounds the panel by that room, not by the fraction")
            // The floating buttons ask for room under the panel. Where that
            // room is less than four fifths of the display, it bounds the
            // panel; where it is more, the fraction does.
            let withButtons = display(height: 1_080)
            let crowded = display(height: 1_080, quickAccess: 300)
            let slight = display(height: 1_080, quickAccess: 120)
            suite.expect(crowded.maximumPanelHeight < withButtons.maximumPanelHeight
                         && crowded.maximumPanelHeight == 1_080 - NotchGeometry.displayEdgeReserve - 300,
                         "the floating buttons' room comes off the panel's ceiling on the same display")
            suite.expect(slight.maximumPanelHeight == withButtons.maximumPanelHeight,
                         "a small room the display keeps does not lower the ceiling under four fifths")
            // Every System Monitoring page reads the ceiling from one place.
            suite.expect(display(height: 1_080).dashboardContentLimit == display(height: 1_080).maximumPanelContentHeight,
                         "the complete dashboard and a reading share the same content ceiling")
        }

        suite.run("a reading is as tall as the reading it shows") {
            let display = display(height: 1_080)
            let header = display.headerTopInset + display.headerChromeHeight
            func panel(_ content: CGFloat) -> CGSize {
                display.expandedSize(module: .system, detail: true, detailHeight: content)
            }
            // A short list of applications shrinks the panel to it, with no
            // empty space below the last row.
            for content in [60, 120, 240, 300] as [CGFloat] {
                let size = panel(content)
                suite.expect(abs(size.height - (content + 4 + header)) < 0.001,
                             "a reading measuring \(Int(content)) points gets a panel of its own height")
            }
            // A reading taller than the strip its layout chose takes the whole
            // page the display allows, so its last row is inside the panel.
            let strip = min(display.pageBudget, display.maximumPanelContentHeight)
            let between = strip + 120
            let grown = panel(between)
            suite.expect(abs(grown.height - display.maximumPanelHeight) < 0.001
                         && grown.height - header >= between,
                         "a reading of \(Int(between)) points, taller than its strip of \(Int(strip)), gets the whole page and shows every row")
            // A long list grows the panel until the ceiling, and there the
            // page scrolls: the panel never exceeds four fifths of the display.
            for content in [900, 2_000, 8_000] as [CGFloat] {
                let size = panel(content)
                suite.expect(abs(size.height - display.maximumPanelHeight) < 0.001,
                             "a reading of \(Int(content)) points stops at the display's ceiling")
                let room = size.height - header
                suite.expect(room < content, "a reading longer than the room scrolls to its last entry")
                suite.expect(room > 0, "and the panel still holds a page of it")
            }
            // A list of fifteen applications with its cards, the longest page
            // the readings draw, is held whole on a normal display: the last
            // application is inside the panel, not cut by its edge.
            let applications = 15
            let rows = CGFloat(applications) * 24
            let cards: CGFloat = 210
            let measured = rows + cards
            let size = panel(measured)
            suite.expect(size.height - header >= measured,
                         "fifteen applications and their cards fit a 1,080-point display, so none is cut off")
            suite.expect(size.height <= display.maximumPanelHeight,
                         "and the panel that holds them stays inside four fifths of the display")
            // The ceiling is the same for every reading, whatever module the
            // page was opened from: the CPU, GPU, Memory, Network, Disk,
            // Battery, Power and Connected Devices pages size by one rule.
            for module in [NotchModule.system, .controls, .music, .mixer, .calendar, .timer] {
                let long = display.expandedSize(module: module, detail: true, detailHeight: 6_000)
                suite.expect(abs(long.height - display.maximumPanelHeight) < 0.001,
                             "the \(module.rawValue) reading stops at the same ceiling")
            }
        }

        suite.run("a height chosen by hand never cuts a reading's list off") {
            // The island's own pages keep the height the person chose...
            let chosen = 420.0
            let display = display(height: 1_080, layout: .custom, customHeight: chosen)
            suite.expect(abs(display.expandedSize(module: .calendar).height - CGFloat(chosen)) < 0.001,
                         "a page that fills a budget keeps the height chosen for the island")
            // ...and a System Monitoring page measures what it draws, so a
            // short custom height cannot slice the application list in half.
            let measured: CGFloat = 760
            let list = display.expandedSize(module: .system, detail: true, detailHeight: measured)
            suite.expect(list.height > CGFloat(chosen),
                         "a reading longer than the height chosen for the island outgrows it")
            suite.expect(list.height - display.headerTopInset - display.headerChromeHeight >= measured,
                         "and the panel is grown to hold the whole list, not cut at the chosen height")
            // A list longer than the display stops at four fifths of it, and
            // the page scrolls the rest, with every application drawn.
            let long = display.expandedSize(module: .system, detail: true, detailHeight: 2_000)
            suite.expect(abs(long.height - display.maximumPanelHeight) < 0.001,
                         "a reading past the ceiling stops at four fifths of the display")
            suite.expect(long.height - display.headerTopInset - display.headerChromeHeight < 2_000,
                         "past the ceiling the page scrolls, with every application drawn")
        }

        suite.run("a reading that has not been measured yet gets a page to measure itself on") {
            // The view measures a reading outside its scroll view, and only
            // then decides whether the page scrolls. For that the layout must
            // hand an unmeasured reading a real page, inside the ceiling.
            let display = display(height: 1_080)
            let unmeasured = display.expandedSize(module: .system, detail: true, detailHeight: nil)
            suite.expect(unmeasured.height > 0 && unmeasured.height <= display.maximumPanelHeight,
                         "an unmeasured reading takes a page inside the display, so its first frame is never blank")
            let room = display.contentSize(for: unmeasured).height
            suite.expect(room > 0 && room <= display.maximumPanelContentHeight,
                         "the room a reading measures its own height against is the page's, inside the ceiling")
            // A reading measured taller than that page's room grows the panel
            // to itself; one measured taller than the display's ceiling keeps
            // the ceiling's room and scrolls the rest to its last row.
            let grows = display.expandedSize(module: .system, detail: true, detailHeight: room + 200)
            suite.expect(display.contentSize(for: grows).height >= room + 200
                         && grows.height <= display.maximumPanelHeight,
                         "a reading taller than the page it opened on grows the panel, inside the ceiling")
            let scrolls = display.expandedSize(module: .system, detail: true,
                                               detailHeight: display.maximumPanelContentHeight + 200)
            suite.expect(display.contentSize(for: scrolls).height < display.maximumPanelContentHeight + 200,
                         "a reading taller than the display's ceiling is left with room to scroll to its last row")
            let shorter = display.expandedSize(module: .system, detail: true, detailHeight: 120)
            suite.expect(display.contentSize(for: shorter).height >= 120,
                         "a reading that fits the page is drawn whole, with nothing under the panel's edge")
        }

        suite.run("the complete dashboard grows with what runs") {
            for height in [1_080, 1_440] as [CGFloat] {
                let display = display(height: height)
                let header = display.headerTopInset + display.headerChromeHeight
                // The sections the page draws decide the panel's height.
                for content in [200, 480, 700] as [CGFloat] {
                    let size = display.dashboardSize(content: content, width: 568)
                    suite.expect(abs(size.height - (content + header)) < 0.001,
                                 "a dashboard of \(Int(content)) points gets a panel of its own height on \(Int(height))")
                }
                // More sections than the display holds: the panel stops at the
                // ceiling and the page scrolls, with every section drawn.
                let tall = display.dashboardSize(content: 4_000, width: 568)
                suite.expect(abs(tall.height - display.maximumPanelHeight) < 0.001,
                             "a dashboard longer than the display stops at four fifths of it")
                suite.expect(tall.height - header == display.dashboardContentLimit,
                             "the page's room is the ceiling less its header, so the scroll reaches the last section")
                suite.expect(tall.height - header < 4_000,
                             "the sections beyond the ceiling are reached by scrolling, not by being dropped")
            }
        }

        suite.run("the scroller is a fifth of its track, whatever the page") {
            suite.expect(NotchScrollIndicator.thumbFraction == 0.2,
                         "the bar keeps to a fifth of the track it travels")
            // The bar is measured from its track alone: a page three times as
            // long as the panel gets the same short bar as one barely longer.
            let track: CGFloat = 800
            suite.expect(abs(NotchScrollIndicator.thumbHeight(track: track) - 160) < 0.001,
                         "a 800-point track carries a 160-point bar")
            suite.expect(NotchScrollIndicator.thumbHeight(track: track)
                         == NotchScrollIndicator.thumbHeight(track: track),
                         "the bar's length never reads the page's length, so it cannot grow into a rail")
            suite.expect(NotchScrollIndicator.thumbHeight(track: 60) >= NotchScrollIndicator.minimumThumb
                         && NotchScrollIndicator.thumbHeight(track: 60) <= 60 - NotchScrollIndicator.edgeInset * 2,
                         "a short track keeps a bar a finger can find, inside its track")
            suite.expect(NotchScrollIndicator.travel(track: track, thumb: 160) == track - 160 - NotchScrollIndicator.edgeInset * 2,
                         "the bar travels the track it is given, and stops inside it")
            // Where the bar sits marks where the page is, from its first row
            // to its last, and a page that fits its panel gets no bar at all.
            let page = NotchScrollReading(offset: 0, container: 400, content: 1_000)
            suite.expect(page.scrolls && page.progress == 0, "at the first row the bar sits at the track's start")
            let middle = NotchScrollReading(offset: 300, container: 400, content: 1_000)
            suite.expect(abs(middle.progress - 0.5) < 0.001, "halfway down the page the bar sits at half the track")
            let end = NotchScrollReading(offset: 600, container: 400, content: 1_000)
            suite.expect(abs(end.progress - 1) < 0.001, "at the last row the bar sits at the track's end")
            suite.expect(NotchScrollReading(offset: 900, container: 400, content: 1_000).progress == 1,
                         "and never past it")
            suite.expect(!NotchScrollReading(offset: 0, container: 400, content: 400).scrolls
                         && !NotchScrollReading(offset: 0, container: 400, content: 401).scrolls,
                         "a page that fits its panel is drawn whole, with no scroller in it")
            suite.expect(NotchScrollReading(offset: 0, container: 0, content: 0).progress == 0,
                         "a page not measured yet has no bar to place")
        }
    }
}
