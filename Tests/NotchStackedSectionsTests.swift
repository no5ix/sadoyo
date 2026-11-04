// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The open island stacks the parts it has instead of showing one page: the
/// song, a running timer, the monitoring detail chosen from a menu bar
/// indicator, and Explore closing the stack under them.
enum NotchStackedSectionsTests {
    static func run(_ suite: TestSuite) {
        compositionContracts(suite)
        surfaceContracts(suite)
        heightContracts(suite)
        islandSizeContracts(suite)
    }

    private static func sections(music: Bool, timer: Bool, detail: Bool) -> [NotchStackedSection] {
        NotchStackedSections.visible(stacks: true, music: music, timer: timer, detail: detail)
    }

    /// The order the island draws its parts in, for every activity and detail.
    private static func compositionContracts(_ suite: TestSuite) {
        suite.expect(sections(music: true, timer: false, detail: false) == [.music, .explore],
                     "a song alone is followed by Explore")
        suite.expect(sections(music: false, timer: true, detail: false) == [.timer, .explore],
                     "a timer alone is followed by Explore")
        suite.expect(sections(music: true, timer: true, detail: false) == [.music, .timer, .explore],
                     "a song and a timer keep their own parts, the player first")
        suite.expect(sections(music: false, timer: false, detail: false) == [.explore],
                     "with nothing running the island shows Explore alone")
        for detail in [true, false] {
            suite.expect(sections(music: true, timer: true, detail: detail)
                             == [.music, .timer] + (detail ? [.detail] : []) + [.explore],
                         "the detail part sits between the activities and Explore (detail: \(detail))")
        }
        // Starting or stopping one part never replaces another, so Explore is
        // the last part of every combination and the detail never doubles.
        for music in [true, false] {
            for timer in [true, false] {
                for detail in [true, false] {
                    let parts = sections(music: music, timer: timer, detail: detail)
                    suite.expect(parts.last == .explore,
                                 "Explore stays in the stack (music: \(music), timer: \(timer), detail: \(detail))")
                    suite.expect(parts.filter { $0 == .detail }.count == (detail ? 1 : 0),
                                 "the stack shows one monitoring detail at a time")
                }
            }
        }
    }

    /// Only Explore or a detail stacks. A page of its own, the app panel and
    /// the Command Bar keep the island end to end, as they did before.
    private static func surfaceContracts(_ suite: TestSuite) {
        suite.expect(NotchStackedSections.stacks(gallery: true, detail: false, appPanel: false, commandBar: false),
                     "Explore opens the stacked surface")
        suite.expect(NotchStackedSections.stacks(gallery: false, detail: true, appPanel: false, commandBar: false),
                     "a detail opened from its indicator opens the stacked surface too")
        for appPanel in [true, false] {
            suite.expect(NotchStackedSections.stacks(gallery: false, detail: false, appPanel: appPanel,
                                                     commandBar: false) == false,
                         "a page of its own keeps the whole island (app panel: \(appPanel))")
        }
        suite.expect(NotchStackedSections.stacks(gallery: false, detail: true, appPanel: true, commandBar: false)
                         == false,
                     "the app panel still covers the island over a detail it kept")
        suite.expect(NotchStackedSections.stacks(gallery: true, detail: true, appPanel: true, commandBar: false),
                     "Explore opened over the app panel stays the gallery the island shows")
        for gallery in [true, false] {
            suite.expect(NotchStackedSections.stacks(gallery: gallery, detail: true, appPanel: false,
                                                     commandBar: true) == false,
                         "the Command Bar keeps the island while a detail is remembered (gallery: \(gallery))")
        }
        suite.expect(NotchStackedSections.visible(stacks: false, music: true, timer: true, detail: true).isEmpty,
                     "a page of its own stacks nothing")
    }

    /// Each part keeps the height its own page measures, and the stack adds the
    /// island's spacing only between two parts.
    private static func heightContracts(_ suite: TestSuite) {
        let parts = NotchStackedSections.parts(sections(music: true, timer: true, detail: true),
                                               music: 140, timer: 82, detail: 320, gallery: 274)
        suite.expect(parts.map(\.section) == [.music, .timer, .detail, .explore]
                     && parts.map(\.height) == [140, 82, 320, 274],
                     "each part carries its own height, in the order the island draws them")
        suite.expect(NotchStackedSections.contentHeight(parts: parts)
                         == 140 + 82 + 320 + 274 + 3 * NotchLayout.spacing,
                     "the stack keeps the island's row spacing between its parts")
        let gallery = NotchStackedSections.parts(sections(music: false, timer: false, detail: false),
                                                 music: 0, timer: 0, detail: 0, gallery: 274)
        suite.expect(NotchStackedSections.contentHeight(parts: gallery) == 274,
                     "Explore alone adds no spacing, so it keeps the page it has today")
        suite.expect(NotchStackedSections.parts([.music, .explore], music: -20, timer: 0, detail: 0,
                                                gallery: 10).allSatisfy { $0.height >= 0 },
                     "a part measured shorter than nothing still takes no room")
    }

    /// The island grows to hold the stack and no further, and the gallery on
    /// its own is exactly the page it was before the stack.
    private static func islandSizeContracts(_ suite: TestSuite) {
        for screen in [CGSize(width: 1440, height: 900), CGSize(width: 1680, height: 1050)] {
            let geometry = NotchGeometry(screen: CGRect(origin: .zero, size: screen),
                                         safeAreaTop: 32, cameraWidth: 180)
            let count = NotchModule.allCases.count
            let gallery = geometry.gallerySectionHeight(count: count)
            let bare = NotchStackedSections.parts(NotchStackedSections.visible(stacks: true, music: false,
                                                                              timer: false, detail: false),
                                                  music: 0, timer: 0, detail: 0, gallery: gallery)
            suite.expect(geometry.stackedSize(content: NotchStackedSections.contentHeight(parts: bare))
                             == geometry.sectionPickerSize(count: count),
                         "an island with nothing running keeps Explore's own size (\(screen))")

            let full = NotchStackedSections.parts(NotchStackedSections.visible(stacks: true, music: true,
                                                                              timer: true, detail: true),
                                                  music: 140, timer: 82, detail: geometry.pageBudget,
                                                  gallery: gallery)
            let fullHeight = geometry.stackedSize(content: NotchStackedSections.contentHeight(parts: full)).height
            suite.expect(fullHeight > geometry.stackedSize(content: NotchStackedSections.contentHeight(parts: bare)).height,
                         "the island grows for the parts it adds (\(screen))")
            suite.expect(fullHeight <= screen.height - 48,
                         "the island stays inside the display whatever the stack asks for (\(screen))")
            suite.expect(geometry.stackedSize(content: 10_000).height == screen.height - 48,
                         "a stack taller than the display is bounded by it, and scrolls in the page (\(screen))")
            let content = geometry.contentSize(for: geometry.stackedSize(content: NotchStackedSections
                .contentHeight(parts: bare)))
            suite.expect(content.height >= NotchStackedSections.contentHeight(parts: bare),
                         "the page keeps at least the gallery's height inside the island (\(screen))")
        }
    }
}
