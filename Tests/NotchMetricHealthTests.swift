// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The colours of the monitoring readings, as one rule.
///
/// The tiles, the menu bar and the detail pages all ask the same question of
/// the same thresholds, so the tests are of the thresholds and not of a view:
/// every boundary named in the design is crossed here on both sides, in both
/// directions, and the tones a tile draws are checked to be the tones the rule
/// gives. A colour that disagrees with its own number is the bug these tests
/// exist for.
enum NotchMetricHealthTests {
    static func run(_ suite: TestSuite) {
        suite.run("a load is measured at its boundaries") {
            // The CPU: ordinary to 60, worth a glance from 60, out of room
            // above 85. The boundary readings belong to the band they enter,
            // so a reading of exactly 60 is already a warning and exactly 85
            // is not yet a critical.
            for percent in [0, 1, 42, 59, 59.9, 59.99] {
                suite.expect(NotchMetricHealth.cpu.tone(Double(percent)) == .nominal,
                             "a CPU at \(percent)% is ordinary: \(NotchMetricHealth.cpu.tone(Double(percent)))")
            }
            suite.expect(NotchMetricHealth.cpu.tone(60) == .warning, "60% is the first warning")
            for percent in [60.1, 70, 84, 84.9, 85] {
                suite.expect(NotchMetricHealth.cpu.tone(percent) == .warning,
                             "a CPU at \(percent)% is a warning: \(NotchMetricHealth.cpu.tone(percent))")
            }
            for percent in [85.01, 90, 99.9, 100] {
                suite.expect(NotchMetricHealth.cpu.tone(percent) == .critical,
                             "a CPU at \(percent)% is out of room")
            }
            // The graphics device is read on its own band, whose limits sit
            // where the CPU's do not.
            suite.expect(NotchMetricHealth.gpu.tone(69.9) == .nominal
                             && NotchMetricHealth.gpu.tone(70) == .warning
                             && NotchMetricHealth.gpu.tone(89.9) == .warning
                             && NotchMetricHealth.gpu.tone(90) == .warning
                             && NotchMetricHealth.gpu.tone(90.1) == .critical,
                         "the GPU warns at 70 and turns red above 90: \(NotchMetricHealth.gpu.tone(90))")
            // Memory keeps the dashboard's own band.
            suite.expect(NotchMetricHealth.memory.tone(69.9) == .nominal
                             && NotchMetricHealth.memory.tone(70) == .warning
                             && NotchMetricHealth.memory.tone(85) == .warning
                             && NotchMetricHealth.memory.tone(85.1) == .critical,
                         "memory warns at 70 and turns red above 85")
            // A reading that is not a number is drawn as missing, and carries
            // no verdict: no threshold makes a gap look like a warning.
            suite.expect(NotchMetricHealth.cpu.tone(nil) == .nominal
                             && NotchMetricHealth.gpu.tone(nil) == .nominal
                             && NotchMetricHealth.memory.tone(nil) == .nominal
                             && NotchMetricHealth.cpu.tone(.nan) == .nominal
                             && NotchMetricHealth.cpu.tone(.infinity) == .nominal,
                         "a missing or unreadable reading is not a warning")
        }

        suite.run("a charge and a disk's free space read the other way") {
            // The battery: a charge above 40 is ordinary, 20 to 40 is worth a
            // glance, under 20 is running out. The direction is the reading's,
            // not the caller's, so a tile cannot get it backwards.
            for percent in [40.1, 55, 80, 100] {
                suite.expect(NotchMetricHealth.battery.tone(percent) == .nominal,
                             "a charge at \(percent)% is ordinary")
            }
            suite.expect(NotchMetricHealth.battery.tone(40) == .warning, "40% is the first warning")
            for percent in [39.9, 30, 21, 20] {
                suite.expect(NotchMetricHealth.battery.tone(percent) == .warning,
                             "a charge at \(percent)% is a warning")
            }
            for percent in [19.9, 10, 1, 0] {
                suite.expect(NotchMetricHealth.battery.tone(percent) == .critical,
                             "a charge at \(percent)% is running out")
            }
            // A disk's free space, the same shape: a share of the whole volume,
            // so a small disk and a big one run short at the same share.
            suite.expect(NotchMetricHealth.diskFree.tone(20.1) == .nominal
                             && NotchMetricHealth.diskFree.tone(20) == .warning
                             && NotchMetricHealth.diskFree.tone(15) == .warning
                             && NotchMetricHealth.diskFree.tone(10) == .warning
                             && NotchMetricHealth.diskFree.tone(9.9) == .critical
                             && NotchMetricHealth.diskFree.tone(0) == .critical,
                         "free space warns at a fifth of the volume and turns red under a tenth")
            // Both readings are asked through the metric, in one call, and a
            // laptop plugged in has room: a low charge with the cable in is a
            // fact about the last hour.
            suite.expect(NotchMetricHealth.tone(metric: .battery, percent: 15) == .critical
                             && NotchMetricHealth.tone(metric: .battery, percent: 15, charging: true) == .identity,
                         "a low charge is red on battery and the charge's own colour when plugged in")
            suite.expect(NotchMetricHealth.tone(metric: .battery, percent: 60, charging: true) == .identity
                             && NotchMetricHealth.tone(metric: .battery, percent: 60) == .nominal,
                         "a full charge answers the same on battery and off it")
            suite.expect(NotchMetricHealth.tone(metric: .disk, percent: 10) == .warning
                             && NotchMetricHealth.tone(metric: .disk, percent: 21) == .nominal,
                         "a disk's free share is measured as a share")
            // The inverse bands are marked as inverse, so a reading added to
            // the grid cannot silently be read the wrong way round.
            suite.expect(!NotchMetricHealth.battery.higherIsWorse && !NotchMetricHealth.diskFree.higherIsWorse
                             && NotchMetricHealth.cpu.higherIsWorse && NotchMetricHealth.gpu.higherIsWorse
                             && NotchMetricHealth.memory.higherIsWorse,
                         "the charge and the free space are the readings where less is the news")
        }

        suite.run("a number that is not a verdict keeps its own colour") {
            // Throughput, watts, a fan's speed, a count of devices: none of
            // these is ill because it is high, and none of them turns red on
            // its own. Each keeps the colour of the thing it measures.
            for percent in [0, 40, 95, 100, 100_000] {
                for metric in [NotchDashboardMetric.network, .power, .fan, .devices] {
                    suite.expect(NotchMetricHealth.tone(metric: metric, percent: Double(percent)) == .identity,
                                 "\(metric.rawValue) at \(percent) carries no verdict")
                }
            }
            // The colours: a warning is amber and a critical is red in every
            // tile, and an ordinary reading wears its metric's own colour. The
            // three are different colours, so a glance separates them.
            let amber = NotchMetricHealth.color(.warning, metric: .cpu)
            let red = NotchMetricHealth.color(.critical, metric: .cpu)
            suite.expect(amber != red, "a warning and a critical are not the same colour")
            for metric in NotchDashboardMetric.allCases {
                suite.expect(NotchMetricHealth.color(.warning, metric: metric) == amber
                                 && NotchMetricHealth.color(.critical, metric: metric) == red,
                             "\(metric.rawValue): a warning and a critical read the same as every other tile's")
            }
            // The network's identity is a blue-cyan, and the power's is orange;
            // neither is amber, and neither is red.
            let network = NotchMetricHealth.identityColor(.network)
            let power = NotchMetricHealth.identityColor(.power)
            suite.expect(network != amber && network != red && network != NotchMetricHealth.identityColor(.power),
                         "the network's own colour is its own, and not a warning")
            suite.expect(power != amber && power != red, "the power's own colour is not a warning")
            // A network at full load is drawn in the network's colour and not
            // in red, which is the rule a page of red tiles needs.
            suite.expect(NotchMetricHealth.color(NotchMetricHealth.tone(metric: .network, percent: 100),
                                                 metric: .network) == network,
                         "a network at full load is not painted a warning")
            // The tones of the load's three readings, asked of the rule and
            // drawn by the tile, are one answer.
            suite.expect(NotchMetricHealth.color(NotchMetricHealth.tone(metric: .cpu, percent: 92), metric: .cpu) == red
                             && NotchMetricHealth.color(NotchMetricHealth.tone(metric: .cpu, percent: 65),
                                                        metric: .cpu) == amber
                             && NotchMetricHealth.color(NotchMetricHealth.tone(metric: .cpu, percent: 12),
                                                        metric: .cpu) == .white,
                         "a tile's figure, its meter and its mark are drawn from one tone")
        }

        suite.run("a spike has to hold before the colour follows it") {
            // A load that crosses a limit for one reading is not news. The
            // gate escalates only after the reading has held, and a reading
            // that returns to ordinary clears the gate at once.
            var gate = NotchSustainedTone()
            let start: TimeInterval = 100
            suite.expect(gate.tone(.warning, at: start) == .nominal,
                         "the first warning sample is not yet a warning on the tile")
            suite.expect(gate.tone(.nominal, at: start + 2) == .nominal,
                         "a spike that ends clears the gate before it fills")
            suite.expect(gate.tone(.warning, at: start + 4) == .nominal
                             && gate.tone(.warning, at: start + 6) == .nominal,
                         "two readings of a warning are not yet a warning")
            suite.expect(gate.tone(.warning, at: start + 10) == .warning,
                         "a warning that has held is a warning")
            suite.expect(gate.tone(.critical, at: start + 12) == .warning,
                         "a critical does not jump the gate it has to fill again")
            suite.expect(gate.tone(.critical, at: start + 18) == .critical,
                         "a critical that has held is a critical")
            suite.expect(gate.tone(.nominal, at: start + 20) == .nominal,
                         "the load returning to ordinary clears the colour at once")
            // The gate is asked at the monitor's own cadence, and it is a
            // handful of readings long, not a minute.
            suite.expect(NotchMetricHealth.sustainedSeconds >= 4 && NotchMetricHealth.sustainedSeconds <= 15,
                         "the gate is a handful of readings: \(NotchMetricHealth.sustainedSeconds)s")
            // A sample with no time on it is not a spike: the gate holds its
            // answer rather than inventing a duration.
            var quiet = NotchSustainedTone()
            suite.expect(quiet.tone(.warning, at: nil) == .nominal
                             && quiet.tone(.warning, at: nil) == .nominal,
                         "a reading with no sample time is not escalated from nothing")
        }
    }
}
