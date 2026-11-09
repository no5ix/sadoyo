// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SwiftUI

/// The dashboard's six compact cards: which six, in what grid, what each card
/// says in its corner, what colour it says it in, and what its chart is drawn
/// from.
///
/// These are the page's promises, asked of the model and not of the drawing: a
/// card that grew a title, a meter, a white figure, a second line, a chart of
/// the current reading repeated, or a page of seven cards fails here. So does a
/// card whose line is drawn in its threshold's colour, and a figure that is
/// white while the reading is not ordinary.
enum NotchSystemCardsTests {
    /// The monitor's clock: a moment on the uptime clock, as the sampler stamps
    /// its readings with.
    private static let t0: TimeInterval = 10_000

    private static func cards(_ sample: NotchDashboardSample, inBits: Bool = false,
                              at now: TimeInterval = t0) -> [NotchDashboardCardReading] {
        NotchDashboardCards.readings(sample, networkSpeedInBits: inBits, now: now)
    }

    private static func card(_ sample: NotchDashboardSample, _ metric: NotchDashboardMetric,
                             inBits: Bool = false,
                             at now: TimeInterval = t0) -> NotchDashboardCardReading {
        cards(sample, inBits: inBits, at: now).first { $0.metric == metric } ?? cards()[0]
    }

    private static func cards() -> [NotchDashboardCardReading] {
        NotchDashboardCards.readings(NotchDashboardSample(), networkSpeedInBits: false, now: t0)
    }

    /// The voice of a card's first figure, when the figure carries a verdict.
    private static func verdict(_ card: NotchDashboardCardReading) -> NotchMetricTone? {
        guard case .verdict(let tone)? = card.figures.first?.voice else { return nil }
        return tone
    }

    /// The reading of a card's first figure, and its voice.
    private static func figure(_ card: NotchDashboardCardReading, _ index: Int = 0) -> NotchMetricFigure? {
        card.figures.indices.contains(index) ? card.figures[index] : nil
    }

    /// Every throughput a card's corner says is said in full: the unit, the
    /// slash, and the `s`. A corner that spells a speed the menu bar's compact
    /// way - `17K`, `0B` - stops saying what its figure is a reading of, and
    /// fails here.
    private static func expectFullUnits(_ suite: TestSuite, _ cards: [NotchDashboardCardReading],
                                         _ what: String) {
        let missing = cards.flatMap { card in
            card.figures.compactMap { figure -> String? in
                guard let text = figure.text,
                      text.contains(NotchDashboardCards.networkDownloadArrow)
                        || text.contains(NotchDashboardCards.networkUploadArrow) else { return nil }
                return text.contains("/s") ? nil : "\(card.metric.rawValue) \(text)"
            }
        }
        suite.expect(missing.isEmpty,
                     what + (missing.isEmpty ? "" : " - said short: \(missing.joined(separator: ", "))"))
    }

    /// A full moment of the machine, at the numbers the reference's card shows.
    private static var full: NotchDashboardSample {
        NotchDashboardSample(cpu: 0.13, gpu: 0.22, memory: 0.41,
                             netDown: 6_200, netUp: 2_400,
                             diskRead: 2_400_000, diskWrite: 6_200_000, watts: 30,
                             diskFreeBytes: 193_000_000_000, diskTotalBytes: 500_000_000_000)
    }

    static func run(_ suite: TestSuite) {
        suite.run("the grid is six cards in two rows of three") {
            expect(suite, NotchDashboardCards.metrics, [.cpu, .gpu, .memory, .network, .disk, .power],
                   "the six, in the order the page reads them")
            suite.expect(NotchDashboardLayout.metricColumns == 3,
                         "three columns: \(NotchDashboardLayout.metricColumns)")
            suite.expect(NotchDashboardLayout.dashboardTileCount == 6
                             && NotchDashboardLayout.dashboardRows == 2,
                         "six cards, two rows: \(NotchDashboardLayout.dashboardTileCount) at "
                         + "\(NotchDashboardLayout.dashboardRows)")
            let rows = NotchDashboardLayout.metricRowRanges(tiles: NotchDashboardLayout.dashboardTileCount)
            suite.expect(rows == [0..<3, 3..<6], "the rows are filled from the left, three each: \(rows)")
            suite.expect(NotchDashboardLayout.metricsHeight(tiles: 6)
                             == 2 * NotchDashboardLayout.metricTileHeight + NotchDashboardLayout.metricSpacing,
                         "the page's grid is its two rows and the one gap between them")
            // The charge and the devices on the cables are the watt page's
            // readings, and the fans are Fan Control's page and the menu bar's:
            // the page has six cards and no seventh.
            suite.expect(!NotchDashboardCards.metrics.contains(.battery)
                             && !NotchDashboardCards.metrics.contains(.devices)
                             && !NotchDashboardCards.metrics.contains(.fan),
                         "no battery, no devices, and no fan card in the grid")
            // The grid is the six whatever the Mac reports: a reading that is
            // missing is drawn as missing, and the page keeps its shape.
            let bare = cards()
            suite.expect(bare.count == 6 && bare.map(\.metric) == NotchDashboardCards.metrics,
                         "a Mac reporting nothing at all still lays out six cards")
            suite.expect(bare.allSatisfy { card in
                card.figures.allSatisfy { $0.text == nil && $0.voice == .quiet }
                    && card.lines.allSatisfy { !$0.hasLine }
            }, "every missing reading says it is missing, and draws no line")
            // A card is not a tall thing: its mark, its figures and its line,
            // and the page's height is measured to the same number.
            suite.expect(NotchDashboardLayout.metricTileHeight >= 56
                             && NotchDashboardLayout.metricTileHeight <= 76,
                         "the card is as tall as its reading and its line, and no taller: "
                         + "\(NotchDashboardLayout.metricTileHeight)pt")
            suite.expect(NotchDashboardLayout.metricChartHeight >= 14
                             && NotchDashboardLayout.metricTilePadding >= 6,
                         "the line has a thumb's height and the card an edge")
        }

        suite.run("a compact card has no title and no meter, and its readings in the corner") {
            let all = cards(full)
            // The shape of the card is the promise: no title to draw, no level
            // to fill a bar, no detail line — the mark says which reading it is,
            // the corner says what it reads, and the line says what it has done.
            let labels = Set(Mirror(reflecting: all[0]).children.compactMap(\.label))
            suite.expect(!labels.contains("title") && !labels.contains("level") && !labels.contains("detail"),
                         "a compact card carries no title, no meter, and no detail line: \(labels.sorted())")
            for card in all {
                suite.expect(!card.lines.isEmpty, "\(card.metric.rawValue) draws its history as a line")
            }
            let cpu = card(full, .cpu)
            suite.expect(cpu.symbol == "cpu" && cpu.figures.count == 1 && cpu.figures[0].text == "13%",
                         "the mark and the figure, and no word beside them")
            suite.expect(card(full, .gpu).symbol == "rectangle.connected.to.line.below"
                             && card(full, .gpu).figures[0].text == "22%", "the GPU's figure")
            suite.expect(card(full, .memory).symbol == "memorychip"
                             && card(full, .memory).figures[0].text == "41%", "the memory's figure")
            suite.expect(card(full, .power).symbol == "powerplug.fill"
                             && card(full, .power).figures[0].text == MetricFormat.wattsCompact(30),
                         "the draw's figure, in watts")
            // The share's figure is the whole of what the card has to say: it is
            // spelled once, and the card has no second, shorter spelling of it.
            suite.expect(all.filter { $0.metric == .cpu || $0.metric == .gpu
                                 || $0.metric == .memory }.allSatisfy { $0.figures.count == 1 },
                         "a share is one figure, spelled once")
            suite.expect(cpu.id == "cpu" && card(full, .disk).id == "disk",
                         "a card answers to its metric, and not to its place in the grid")
            suite.expect(all.filter { $0.sharesOneLine }.count == 5 && !card(full, .disk).sharesOneLine,
                         "five cards read on one line; the disk's corner is the page's two-line one")
            suite.expect(all.allSatisfy { $0.figureLines.count == ($0.metric == .disk ? 2 : 1) },
                         "the corner's lines are the metric's shape: two for the disk, one for the rest")
        }

        suite.run("a figure wears the reading's verdict and a line wears its metric") {
            // The thresholds reach the figures: the three voices, per metric.
            suite.expect(NotchMetricHealth.verdictColor(.nominal) == NotchSplashPalette.green
                             && NotchMetricHealth.verdictColor(.warning) == NotchSplashPalette.amber
                             && NotchMetricHealth.verdictColor(.critical) == NotchSplashPalette.red,
                         "a verdict is green, amber, or red, and never white")
            for (share, wanted) in [(0.13, NotchMetricTone.nominal), (0.65, .warning), (0.90, .critical)] {
                suite.expect(verdict(card(NotchDashboardSample(cpu: share), .cpu)) == wanted,
                             "a CPU at \(Int(share * 100))% is \(wanted)")
            }
            for (share, wanted) in [(0.22, NotchMetricTone.nominal), (0.75, .warning), (0.95, .critical)] {
                suite.expect(verdict(card(NotchDashboardSample(gpu: share), .gpu)) == wanted,
                             "a GPU at \(Int(share * 100))% is \(wanted)")
            }
            for (share, wanted) in [(0.41, NotchMetricTone.nominal), (0.80, .warning), (0.90, .critical)] {
                suite.expect(verdict(card(NotchDashboardSample(memory: share), .memory)) == wanted,
                             "memory at \(Int(share * 100))% is \(wanted)")
            }
            // No reading, no verdict: the figure is quiet, not green.
            let none = card(NotchDashboardSample(), .cpu)
            suite.expect(figure(none)?.voice == .quiet && figure(none)?.text == nil,
                         "a CPU with no reading says nothing, and is not painted healthy")
            // A watt and a throughput carry no verdict: they keep their metric's
            // colour, and the page invents no limit for them.
            let power = card(full, .power)
            suite.expect(figure(power)?.voice == .identity(.power)
                             && power.figures[0].color == NotchSplashPalette.orange
                             && !power.wantsAttention,
                         "watts are the watt's own orange, whatever they read")
            let loud = card(NotchDashboardSample(watts: 400), .power)
            suite.expect(figure(loud)?.voice == .identity(.power), "a big draw is not painted as an illness")
            // The chart's identity is the metric's, and one line never borrows
            // another's colour. A card's line count is the reading's own.
            suite.expect(NotchChartRole.cpu.color == NotchChartPalette.teal
                             && NotchChartRole.gpu.color == NotchSplashPalette.blue
                             && NotchChartRole.memory.color == NotchSplashPalette.purple
                             && NotchChartRole.power.color == NotchSplashPalette.orange,
                         "the four single lines keep their metrics' four colours")
            suite.expect(NotchChartRole.networkDown.color == NotchSplashPalette.blue
                             && NotchChartRole.networkUp.color == NotchSplashPalette.orange
                             && NotchChartRole.diskWrite.color == NotchSplashPalette.blue
                             && NotchChartRole.diskRead.color == NotchSplashPalette.green,
                         "the two directions of the wire and the two faces of the volume keep their colours")
            suite.expect(NotchChartRole.cpu.color != NotchChartRole.gpu.color
                             && NotchChartRole.cpu.color != NotchChartRole.memory.color
                             && NotchChartRole.gpu.color != NotchChartRole.memory.color
                             && NotchChartRole.networkUp.color != NotchChartRole.networkDown.color
                             && NotchChartRole.diskRead.color != NotchChartRole.diskWrite.color,
                         "six cards, and no two of a kind to tell apart by colour")
            // One line for a single reading, two for a pair, in the order the
            // card draws them.
            suite.expect(card(full, .cpu).lines.map(\.role) == [.cpu]
                             && card(full, .gpu).lines.map(\.role) == [.gpu]
                             && card(full, .memory).lines.map(\.role) == [.memory]
                             && card(full, .power).lines.map(\.role) == [.power],
                         "four cards, one line each")
            suite.expect(card(full, .network).lines.map(\.role) == [.networkDown, .networkUp]
                             && card(full, .disk).lines.map(\.role) == [.diskWrite, .diskRead],
                         "the network's two and the disk's two, in the order the arrows are read")
        }

        suite.run("a load has to hold before its figure turns") {
            // The six-second gate, kept: a spike that has not held keeps the
            // page's colour, and a load that has holds the figure at its verdict.
            suite.expect(NotchMetricHealth.sustainedSeconds == 6, "the window is six seconds")
            let spike = NotchDashboardSample(cpu: 0.90, gpu: 0.95, sustained: [.cpu: .nominal, .gpu: .nominal])
            suite.expect(verdict(card(spike, .cpu)) == .nominal && verdict(card(spike, .gpu)) == .nominal,
                         "a second's spike on the CPU or the GPU leaves the figure alone")
            let held = NotchDashboardSample(cpu: 0.90, gpu: 0.95, sustained: [.cpu: .critical, .gpu: .warning])
            suite.expect(verdict(card(held, .cpu)) == .critical && verdict(card(held, .gpu)) == .warning,
                         "a load that held gives the figure its verdict")
            // The gate is shared, so the tile, the compact card, the menu bar and
            // the detail page all answer from the same rule.
            suite.expect(NotchMetricReading.gate(.critical, gated: .nominal) == .nominal
                             && NotchMetricReading.tone(.cpu, percent: 50, sustained: [.cpu: .warning]) == .nominal
                             && NotchMetricReading.percent(0.412) == "41%"
                             && abs((NotchMetricReading.percentValue(0.412) ?? 0) - 41.2) < 0.001
                             && NotchMetricReading.percent(nil) == nil
                             && NotchMetricReading.percent(Double.nan) == nil
                             && NotchMetricReading.percent(3) == "100%",
                         "one rule for a share and its gate, and a gate quieter than the reading lets the reading answer")
            // Memory's thresholds are a pressure's, not a load's: no gate.
            suite.expect(NotchMetricHealth.tone(metric: .memory, percent: 86) == .critical
                             && NotchMetricHealth.memory.warning == 70
                             && NotchMetricHealth.memory.critical == 85,
                         "memory's band is its own and needs no gate")
        }

        suite.run("the network card reads one wire's two directions") {
            let net = card(full, .network)
            let down = figure(net, 0)?.text ?? ""
            let up = figure(net, 1)?.text ?? ""
            suite.expect(net.figures.count == 2, "two figures, both in the corner")
            suite.expect(down == NotchDashboardCards.networkDownloadArrow + " "
                             + MetricFormat.networkRate(6_200, inBits: false),
                         "the download, with its arrow and no word: \(down)")
            suite.expect(up == NotchDashboardCards.networkUploadArrow + " "
                             + MetricFormat.networkRate(2_400, inBits: false),
                         "the upload, with its arrow and no word: \(up)")
            suite.expect(down.hasPrefix("↓") && up.hasPrefix("↑"), "the arrows are the two directions")
            suite.expect(down.contains("KB/s") && up.contains("KB/s"), "the bytes' unit, as the settings choose it")
            let bits = card(full, .network, inBits: true)
            suite.expect((figure(bits, 0)?.text ?? "").contains("bps")
                             && (figure(bits, 1)?.text ?? "").contains("bps"),
                         "the same card at the bits setting")
            suite.expect(figure(net, 0)?.color == NotchSplashPalette.blue
                             && figure(net, 1)?.color == NotchSplashPalette.orange,
                         "blue in, orange out")
            // A card that has to fit says the same words smaller; it never says
            // fewer of them. There is no short spelling of a throughput in the
            // page at all, so no corner can be drawn without the unit.
            expectFullUnits(suite, [net, card(NotchDashboardSample(netDown: 0, netUp: 0), .network),
                                    card(NotchDashboardSample(netDown: 5_120_000, netUp: 12), .network)],
                            "a throughput is spelled in full, unit and /s, at every speed")
            // The two directions of one wire are a pair: the card draws both
            // against the same instants.
            let samples = [SystemMetricSample(at: t0, netDown: 100, netUp: 200),
                           SystemMetricSample(at: t0 + 2, netDown: 300, netUp: 400),
                           SystemMetricSample(at: t0 + 4, netDown: 500, netUp: nil)]
            let pairs = SystemMetricSeries.pairs(in: samples, \.netDown, \.netUp,
                                                 window: NotchDashboardCards.chartWindow, endingAt: t0 + 4)
            suite.expect(pairs.map(\.at) == [t0, t0 + 2, t0 + 4],
                         "the pair's two halves share their instants")
            suite.expect(pairs[2].first == 500 && pairs[2].second == nil,
                         "a direction with no reading is a gap in one line, not a zero in it")
            // A wire with only one direction reading: the figure that has a
            // reading says it, the other says nothing.
            let half = card(NotchDashboardSample(netDown: 6_200), .network)
            suite.expect(figure(half, 0)?.text != nil && figure(half, 1)?.text == nil
                             && figure(half, 1)?.voice == .quiet,
                         "one direction read, one direction silent")
            suite.expect(card(NotchDashboardSample(netDown: -5), .network).figures[0].text == nil
                             && card(NotchDashboardSample(netDown: .nan), .network).figures[0].text == nil,
                         "a negative and a not-a-number are both readings the Mac does not have")
        }

        suite.run("the network pair keeps its order, its arrows and its whole unit at every speed") {
            // The pair is read left to right: the download first and the upload
            // second, at every relation between the two numbers. The order is
            // the directions' and never the numbers', so a wire that is sending
            // more than it takes does not turn the card's first figure into an
            // upload.
            for (down, up) in [(6_200_000.0, 2_400.0), (2_400.0, 986_000.0), (0.0, 0.0),
                               (0.0, 102_400.0), (102_400.0, 0.0), (512.0, 128.0),
                               (17_400.0, 6_450.0)] {
                let pair = card(NotchDashboardSample(netDown: down, netUp: up), .network)
                let first = figure(pair, 0)?.text ?? ""
                let second = figure(pair, 1)?.text ?? ""
                suite.expect(pair.figures.count == 2
                                 && first.hasPrefix(NotchDashboardCards.networkDownloadArrow)
                                 && second.hasPrefix(NotchDashboardCards.networkUploadArrow)
                                 && first.contains(MetricFormat.networkRate(down, inBits: false))
                                 && second.contains(MetricFormat.networkRate(up, inBits: false)),
                             "the download first and the upload second at \(down) / \(up): \(first) \(second)")
                suite.expect(first.contains("/s") && second.contains("/s"),
                             "both directions keep their whole unit: \(first) \(second)")
                suite.expect(pair.figureLines.count == 1 && pair.figureLines[0].figures.count == 2,
                             "the pair is one line whatever the two numbers are")
            }
            // The colour belongs to the direction, so a pair whose upload is the
            // bigger of the two cannot read as a pair that has changed places.
            let sending = card(NotchDashboardSample(netDown: 100, netUp: 9_000_000), .network)
            suite.expect(figure(sending, 0)?.color == NotchSplashPalette.blue
                             && figure(sending, 1)?.color == NotchSplashPalette.orange,
                         "the blue stays with the download and the orange with the upload")
            // The card's own mark names the direction, and the mapping is the
            // sample's: the first figure is the download's reading, the second
            // the upload's, and not the bigger of the two.
            let asymmetric = card(NotchDashboardSample(netDown: 1_024, netUp: 8_192), .network)
            suite.expect(figure(asymmetric, 0)?.text == NotchDashboardCards.networkDownloadArrow + " "
                             + MetricFormat.networkRate(1_024, inBits: false)
                             && figure(asymmetric, 1)?.text == NotchDashboardCards.networkUploadArrow + " "
                             + MetricFormat.networkRate(8_192, inBits: false),
                         "the download's figure is the download's reading, and the upload's the upload's")
        }

        suite.run("the disk card is always two lines, the room above its arrows") {
            for (free, read, write) in [(193_000_000_000.0, 2_400_000.0, 6_200_000.0),
                                         (1_000.0, 0.0, 0.0),
                                         (500_000_000_000.0, 0.0, 900.0),
                                         (193_000_000_000.0, 5_120_000.0, 128.0)] {
                let disk = card(NotchDashboardSample(diskRead: read, diskWrite: write,
                                                     diskFreeBytes: UInt64(free)), .disk)
                let lines = disk.figureLines
                suite.expect(lines.count == 2 && lines[0].figures.count == 1 && lines[1].figures.count == 2,
                             "the room on its line and the two arrows under it: \(lines.count) lines")
                suite.expect(lines[0].figures[0].text == MetricFormat.diskBytes(UInt64(free)),
                             "the room left stands alone on the first line")
                suite.expect(lines[1].figures[0].text?.hasPrefix(NotchDashboardCards.diskWriteArrow) == true
                                 && lines[1].figures[1].text?.hasPrefix(NotchDashboardCards.diskReadArrow) == true,
                             "the write is the first arrow and the read the second, at \(read) / \(write)")
                suite.expect((lines[1].figures[0].text ?? "").contains("/s")
                                 && (lines[1].figures[1].text ?? "").contains("/s"),
                             "both of the disk's arrows carry their whole unit")
                suite.expect(lines[1].figures[0].color == NotchSplashPalette.blue
                                 && lines[1].figures[1].color == NotchSplashPalette.green,
                             "the write is the blue going in and the read the green coming out")
                suite.expect(!disk.sharesOneLine, "the disk's corner is never one line of three")
            }
        }

        suite.run("the disk card reads its room and what goes in and comes out") {
            let disk = card(full, .disk)
            suite.expect(disk.figures.count == 3, "the room, the write, and the read")
            suite.expect(figure(disk, 0)?.text == MetricFormat.diskBytes(193_000_000_000),
                         "the room left in the volume, and it is not a bar: \(figure(disk, 0)?.text ?? "")")
            suite.expect(figure(disk, 1)?.text == NotchDashboardCards.diskWriteArrow + " "
                             + MetricFormat.networkRate(6_200_000, inBits: false),
                         "what is written into the volume: \(figure(disk, 1)?.text ?? "")")
            suite.expect(figure(disk, 2)?.text == NotchDashboardCards.diskReadArrow + " "
                             + MetricFormat.networkRate(2_400_000, inBits: false),
                         "what is read out of it: \(figure(disk, 2)?.text ?? "")")
            suite.expect(figure(disk, 1)?.color == NotchSplashPalette.blue
                             && figure(disk, 2)?.color == NotchSplashPalette.green,
                         "the write is the blue going in, the read is the green coming out")
            expectFullUnits(suite, [disk, card(NotchDashboardSample(diskRead: 0, diskWrite: 0), .disk),
                                    card(NotchDashboardSample(diskRead: 900, diskWrite: 5_120_000,
                                                              diskFreeBytes: 1_000), .disk)],
                            "the disk's two arrows carry their whole unit, as the network's do")
            // The arrows, stated: a disk's down is a write and its up is a read,
            // which is the direction IOKit's block-storage counters keep from.
            suite.expect(NotchDashboardCards.diskWriteArrow == NotchDashboardCards.networkDownloadArrow
                             && NotchDashboardCards.diskReadArrow == NotchDashboardCards.networkUploadArrow,
                         "one arrow convention, written down: into the volume is down, out of it is up")
            suite.expect(NotchChartRole.diskWrite.color == NotchChartRole.networkDown.color
                             && NotchChartRole.diskRead.color != NotchChartRole.networkUp.color,
                         "the volume's write is the wire's blue; its read is a green of its own")
            // The room is the one reading of the three that is a verdict.
            suite.expect(verdict(disk) == .nominal, "a volume with four tenths left is ordinary")
            let tight = card(NotchDashboardSample(diskFreeBytes: 8_000_000_000,
                                                  diskTotalBytes: 100_000_000_000), .disk)
            suite.expect(verdict(tight) == .critical, "eight per cent left is the news: \(figure(tight)?.text ?? "")")
            let short = card(NotchDashboardSample(diskFreeBytes: 15_000_000_000,
                                                  diskTotalBytes: 100_000_000_000), .disk)
            suite.expect(verdict(short) == .warning, "fifteen per cent left is worth a glance")
            // No volume, no counters: three figures with nothing to say.
            let nothing = card(NotchDashboardSample(), .disk)
            suite.expect(nothing.figures.allSatisfy { $0.text == nil && $0.voice == .quiet },
                         "a Mac with no volume reading says so three times, and draws no bar")
            // The volume the card speaks for, and its throughput: a volume seen
            // as partitions and as its whole disk is counted once.
            let volume = DiskDeviceReading(id: "disk0", name: "Macintosh HD", mountPath: "/",
                                           totalBytes: 500_000_000_000, freeBytes: 193_000_000_000,
                                           usedBytes: 307_000_000_000,
                                           isInternal: true, isRemovable: false, isEjectable: false)
            suite.expect(NotchDashboardCards.activity(of: nil) == nil, "no reading is not a reading of nothing")
            let io = DiskDeviceReading(id: "disk0", name: "Macintosh HD", mountPath: "/",
                                       totalBytes: 1, freeBytes: 1, usedBytes: 0,
                                       isInternal: true, isRemovable: false, isEjectable: false,
                                       readBytesPerSec: 1_000, writeBytesPerSec: 2_000)
            let whole = DiskDeviceReading(id: "disk0s1", name: "Data", mountPath: "/System/Volumes/Data",
                                          totalBytes: 1, freeBytes: 1, usedBytes: 0,
                                          isInternal: true, isRemovable: false, isEjectable: false,
                                          readBytesPerSec: 500, writeBytesPerSec: 500)
            let summed = NotchDashboardCards.activity(of: DiskReading(devices: [io, whole]))
            suite.expect(summed?.read == 1_500 && summed?.write == 2_500,
                         "the volume's throughput is its devices' sum, read from the counters")
            suite.expect(volume.freeBytes == 193_000_000_000, "the card's room is the volume's own")
        }

        suite.run("a chart is the moments the monitor kept, and not the moment repeated") {
            let samples = [SystemMetricSample(at: t0, cpu: 0.10, gpu: 0.30, diskRead: 10, diskWrite: 20, watts: 5),
                           SystemMetricSample(at: t0 + 2, cpu: 0.25, gpu: 0.30, diskRead: 30, diskWrite: 60, watts: 8),
                           SystemMetricSample(at: t0 + 4, cpu: 0.40, gpu: nil, diskRead: nil, diskWrite: 100, watts: 12)]
            let cpu = card(NotchDashboardSample(samples: samples), .cpu, at: t0 + 4)
            suite.expect(cpu.lines[0].points.map(\.value) == [0.10, 0.25, 0.40],
                         "the line is the readings, oldest first")
            suite.expect(cpu.lines[0].points.map(\.at) == [t0, t0 + 2, t0 + 4],
                         "and each point stands at its own instant, not at its place in the array")
            suite.expect(card(NotchDashboardSample(samples: samples), .gpu, at: t0 + 4)
                             .lines[0].points.map(\.value) == [0.30, 0.30],
                         "a reading the monitor did not take is not drawn as a zero")
            // The window: the last minutes, and nothing older.
            let old = SystemMetricSample(at: t0 - 600, cpu: 0.99)
            suite.expect(SystemMetricSeries.points(in: [old] + samples, \.cpu, window: 3, endingAt: t0 + 4)
                             .map(\.value) == [0.25, 0.40],
                         "a window of three seconds draws the two readings inside it, and not the hour before")
            suite.expect(SystemMetricSeries.points(in: [], \.cpu, window: 600, endingAt: t0).isEmpty,
                         "no moments, no points")
            suite.expect(SystemMetricSeries.points(in: [SystemMetricSample(at: t0, cpu: .nan),
                                                        SystemMetricSample(at: t0 + 2, cpu: 0.5)],
                                                   \.cpu, window: 600, endingAt: t0 + 2).count == 1,
                         "a reading that is not a number is no point, and no line")
            // Two lines of one card share their heights, so a card's two lines
            // are a comparison and not two shapes.
            let scale = SystemMetricSeries.scale(of: [[SystemMetricPoint(at: t0, value: 10),
                                                       SystemMetricPoint(at: t0 + 2, value: 20)],
                                                      [SystemMetricPoint(at: t0, value: 100),
                                                       SystemMetricPoint(at: t0 + 2, value: 40)]])
            suite.expect(scale == 0...100, "the tallest of the two lines sets the height for both")
            suite.expect(SystemMetricSeries.scale(of: []) == nil, "nothing measured sets no scale")
            // A gap in the readings is a gap in the line.
            let gapped = [SystemMetricPoint(at: t0, value: 1), SystemMetricPoint(at: t0 + 2, value: 2),
                          SystemMetricPoint(at: t0 + 4, value: 3), SystemMetricPoint(at: t0 + 60, value: 4)]
            suite.expect(SystemMetricSeries.usualStep(of: gapped) == 2, "the usual step is the sampler's own")
            suite.expect(SystemMetricSeries.runs(of: gapped).map(\.count) == [3, 1],
                         "a minute without a reading breaks the line, and a card does not guess across it")
            suite.expect(SystemMetricSeries.runs(of: []).isEmpty, "no points, no runs")
        }

        suite.run("the monitor's moments are bounded, paired, and its own readings") {
            var history = SystemMetricSampleHistory(capacity: 4)
            for index in 0..<10 {
                history.push(SystemMetricSample(at: Double(index), cpu: Double(index) / 100))
            }
            suite.expect(history.samples.count == 4 && history.samples.map(\.at) == [6, 7, 8, 9],
                         "a rolling window of four: the oldest go first, whatever the machine has been running")
            history.push(SystemMetricSample(at: 10))
            suite.expect(history.samples.last?.at == 9, "a tick that sampled nothing adds no moment")
            history.push(SystemMetricSample(at: 9, gpu: 0.5))
            suite.expect(history.samples.count == 4 && history.samples.last?.gpu == 0.5,
                         "a repeat of the last instant is the same moment filled in, not a second moment")
            suite.expect(history.publishedValues(whileVisible: false).isEmpty
                             && history.publishedValues(whileVisible: true).count == 4,
                         "a surface with no chart asks for no array, and the window is kept for the next opening")
            // A pair is one moment: the network's two directions and the
            // volume's two faces are carried together, so the two lines of a
            // card are the two halves of one instant.
            let pair = SystemMetricSample(at: t0, netDown: 1_000, netUp: 2_000, diskRead: 3, diskWrite: 4)
            suite.expect(pair.hasReading, "a moment with a reading is worth keeping")
            suite.expect(!SystemMetricSample(at: t0).hasReading, "a moment with none is not")
            let pairs = SystemMetricSeries.pairs(in: [pair], \.diskWrite, \.diskRead,
                                                 window: 600, endingAt: t0)
            suite.expect(pairs.count == 1 && pairs[0].first == 4 && pairs[0].second == 3,
                         "the volume's write and read, at one instant")
            // The card's chart window is the sampler's whole kept span.
            suite.expect(NotchDashboardCards.chartWindow >= 60
                             && NotchDashboardCards.chartWindow <= 15 * 60,
                         "a card's line is a span of minutes, not of an hour")
        }
    }

    private static func expect(_ suite: TestSuite, _ actual: [NotchDashboardMetric],
                               _ expected: [NotchDashboardMetric], _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        suite.expect(actual == expected, "\(what): got \(actual.map { $0.rawValue }), expected "
            + "\(expected.map { $0.rawValue })", file: file, line: line)
    }
}
