// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where a click on the combined menu bar item lands. The bar shows several
/// readings in one button, and the promise is that the number the pointer is
/// over is the reading the click opens — the memory block opens Memory, the
/// disk block opens Disk — while the app glyph and the empty parts of the item
/// stay the app panel's.
///
/// The layout hands over the widths its blocks measured; the decisions below
/// are what the menu bar answers with, and they are what broke when a click on
/// a reading's number opened the overview instead of that reading's page.
enum MenuBarMetricHitTests {
    static func run(_ suite: TestSuite) {
        suite.run("a click on a reading's number names that reading") {
            let ranges = MenuBarMetricHitSupport.ranges(
                metrics: ["memory", "diskActivity", "diskUsage"],
                widths: [40, 30, 36]
            )
            expect(suite, MenuBarMetricHitSupport.metric(at: 20, in: ranges), "memory",
                   "the middle of the first block is the memory reading")
            expect(suite, MenuBarMetricHitSupport.metric(at: 55, in: ranges), "diskActivity",
                   "the middle of the second block is the disk activity reading")
            expect(suite, MenuBarMetricHitSupport.metric(at: 88, in: ranges), "diskUsage",
                   "the middle of the last block is the disk reading")            // The memory block is the one the user clicks for Memory, and it is
            // the one that answered with the overview.
            expect(suite, MenuBarMetricHitSupport.mainItemClick(x: 20, in: ranges), .metric("memory"),
                   "the menu bar's memory number is a click on Memory")
        }

        suite.run("the blocks cover the title with no gap and no overlap") {
            let widths: [CGFloat] = [40, 30, 36, 22]
            let metrics = ["memory", "diskActivity", "diskUsage", "power"]
            let ranges = MenuBarMetricHitSupport.ranges(metrics: metrics, widths: widths)
            suite.expect(ranges.count == metrics.count, "every reading gets a slice of the title")
            suite.expect(ranges.first?.minX == 0, "the first block starts where the title starts")
            var total: CGFloat = 0
            for width in widths { total += width }
            suite.expect(ranges.last?.maxX == total, "the last block ends where the title ends")
            for index in 1..<ranges.count {
                suite.expect(ranges[index].minX == ranges[index - 1].maxX,
                             "block \(index) begins where block \(index - 1) ends")
            }
            // Every point of the title, including the seams, answers for one
            // reading: a click never falls between two numbers.
            for x in stride(from: CGFloat(0), through: total - 1, by: 1) {
                suite.expect(MenuBarMetricHitSupport.metric(at: x, in: ranges) != nil,
                             "a click at \(x) points belongs to a reading")
            }
        }

        suite.run("the app glyph, the edge and no position at all are the panel's") {
            let ranges = MenuBarMetricHitSupport.ranges(metrics: ["memory", "diskUsage"],
                                                        widths: [40, 30],
                                                        leadingInset: 4)
            expect(suite, MenuBarMetricHitSupport.mainItemClick(x: nil, in: ranges), .panel,
                   "a click with no position to read is the app panel's")
            expect(suite, MenuBarMetricHitSupport.mainItemClick(x: -3, in: ranges), .panel,
                   "a click over the app glyph is the app panel's")
            expect(suite, MenuBarMetricHitSupport.mainItemClick(x: 80, in: ranges), .panel,
                   "a click past the last number is the app panel's")
            expect(suite, MenuBarMetricHitSupport.mainItemClick(x: .nan, in: ranges), .panel,
                   "a click at no position at all is the app panel's")
            // The leading glyph shifts the blocks; the reading under the pointer
            // follows the shift, so the number the user sees is the one they hit.
            expect(suite, MenuBarMetricHitSupport.mainItemClick(x: 6, in: ranges), .metric("memory"),
                   "the first number starts after the glyph and stays memory")
            expect(suite, MenuBarMetricHitSupport.metric(at: 3, in: ranges), nil as String?,
                   "the glyph's own space answers for no reading")
            let inset = MenuBarMetricHitSupport.ranges(metrics: ["memory"], widths: [40], leadingInset: 4)
            let bare = MenuBarMetricHitSupport.ranges(metrics: ["memory"], widths: [40])
            suite.expect(inset.first?.minX == 4 && bare.first?.minX == 0,
                         "the leading inset moves the whole title, not one block")
        }

        suite.run("a reading that renders nothing takes no click") {
            let ranges = MenuBarMetricHitSupport.ranges(metrics: ["cpuTemperature", "memory"],
                                                        widths: [0, 30])
            suite.expect(ranges.first?.width == 0, "a reading with no block takes no room")
            expect(suite, MenuBarMetricHitSupport.metric(at: 15, in: ranges), "memory",
                   "the block that is drawn answers for its own reading")
            let short = MenuBarMetricHitSupport.ranges(metrics: ["memory", "gpu", "fanSpeed"], widths: [40])
            expect(suite, MenuBarMetricHitSupport.mainItemClick(x: 45, in: short), .panel,
                   "a reading with no measured width is not a click target")
            expect(suite, MenuBarMetricHitSupport.mainItemClick(x: 10, in: []), .panel,
                   "a bar with no readings is the app panel's")
        }
    }

    private static func expect<T: Equatable>(_ suite: TestSuite, _ actual: T, _ expected: T, _ message: String) {
        suite.expect(actual == expected, "\(message): got \(actual), expected \(expected)")
    }
}
