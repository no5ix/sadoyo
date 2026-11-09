// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SwiftUI

/// The dashboard's compact cards: six of them, in one fixed order.
///
/// The page is two rows of three, and the six are the six the page has room
/// for: the machine's work, its memory, its cable, its volume, its draw. A
/// reading the machine does not have is drawn as missing, and the card stays in
/// its place — a page whose cards come and go with the weather is not a page a
/// person can learn.
///
/// What is *not* here is decided as deliberately as what is. The charge and
/// the devices on the cables are not compact cards: they are the Power page's
/// own readings, where each has room to be named, and their sampling is
/// untouched by the page they left. The fans are the panel's page and the menu
/// bar's, and were never a reading of the machine's work.
enum NotchDashboardCards {
    /// The six, in the order the page reads them: left to right, top row first.
    static let metrics: [NotchDashboardMetric] = [.cpu, .gpu, .memory, .network, .disk, .power]

    /// How far back a card's line looks.
    ///
    /// The sampler keeps a bounded window of moments, so this is the whole of
    /// what it retains: a chart is the machine's recent past, and a machine
    /// left running for a month draws the same span it drew in its first
    /// minute.
    static let chartWindow: TimeInterval = 6 * 60

    /// The arrows, and what each one means here.
    ///
    /// A network's arrow is the direction the bytes travel over the wire: down
    /// into the Mac, up out of it. A disk's arrow is the same journey from the
    /// Mac's side of the volume: what is written into the volume goes down,
    /// what is read out of it comes up. That is the direction the counter is
    /// kept from — IOKit's block-storage statistics count `Bytes (Written)`
    /// going in and `Bytes (Read)` coming out — and it is written down because
    /// a disk's arrow read as a download would be a lie about the machine.
    static let networkDownloadArrow = "\u{2193}"
    static let networkUploadArrow = "\u{2191}"
    static let diskWriteArrow = "\u{2193}"
    static let diskReadArrow = "\u{2191}"

    /// The six cards, from the readings of one moment and the moments that
    /// made the charts.
    ///
    /// The figures and the lines are decided here, in the order the card draws
    /// them, so a test can ask what a card says and what it is drawn in without
    /// drawing it. A reading that is missing is a figure with nothing to say,
    /// and a line with no measurements, which is drawn as the place where a
    /// line will go.
    static func readings(_ sample: NotchDashboardSample,
                         networkSpeedInBits: Bool,
                         now: TimeInterval) -> [NotchDashboardCardReading] {
        metrics.map { metric in
            reading(metric, sample, networkSpeedInBits: networkSpeedInBits, now: now)
        }
    }

    private static func reading(_ metric: NotchDashboardMetric, _ sample: NotchDashboardSample,
                                networkSpeedInBits: Bool, now: TimeInterval) -> NotchDashboardCardReading {
        let samples = sample.samples
        let window = chartWindow
        switch metric {
        case .cpu:
            let tone = NotchMetricReading.tone(.cpu, percent: NotchMetricReading.percentValue(sample.cpu),
                                               sustained: sample.sustained)
            return NotchDashboardCardReading(metric: .cpu, symbol: "cpu",
                                             figures: [verdict(NotchMetricReading.percent(sample.cpu), tone)],
                                             lines: [line(.cpu, in: samples, \.cpu, window: window, now: now)])
        case .gpu:
            let tone = NotchMetricReading.tone(.gpu, percent: NotchMetricReading.percentValue(sample.gpu),
                                               sustained: sample.sustained)
            return NotchDashboardCardReading(metric: .gpu,
                                             symbol: "rectangle.connected.to.line.below",
                                             figures: [verdict(NotchMetricReading.percent(sample.gpu), tone)],
                                             lines: [line(.gpu, in: samples, \.gpu, window: window, now: now)])
        case .memory:
            let tone = NotchMetricHealth.tone(metric: .memory,
                                              percent: NotchMetricReading.percentValue(sample.memory))
            return NotchDashboardCardReading(metric: .memory, symbol: "memorychip",
                                             figures: [verdict(NotchMetricReading.percent(sample.memory), tone)],
                                             lines: [line(.memory, in: samples, \.memory,
                                                          window: window, now: now)])
        case .network:
            // The two directions of one wire: the same unit, the same window,
            // the two colours of the two arrows. A fast network is not an ill
            // one, so neither figure takes a warning's colour.
            let down = line(.networkDown, in: samples, \.netDown, window: window, now: now)
            let up = line(.networkUp, in: samples, \.netUp, window: window, now: now)
            return NotchDashboardCardReading(metric: .network, symbol: "network",
                                             figures: [
                                                 arrowFigure(rate(sample.netDown, inBits: networkSpeedInBits,
                                                             prefix: networkDownloadArrow), .networkDown),
                                                 arrowFigure(rate(sample.netUp, inBits: networkSpeedInBits,
                                                             prefix: networkUploadArrow), .networkUp),
                                             ],
                                             lines: [down, up])
        case .disk:
            // Three readings of one volume: the room left in it, and what is
            // going in and coming out of it now. The room is the only one of
            // the three that is a verdict — a volume running short is news, and
            // the two throughputs are numbers.
            let free = sample.diskFreeBytes
            let freeShare: Double? = free.flatMap { free in
                sample.diskTotalBytes.flatMap { total in
                    total > 0 ? min(1, Double(free) / Double(total)) * 100 : nil
                }
            }
            let tone = NotchMetricHealth.tone(metric: .disk, percent: freeShare)
            return NotchDashboardCardReading(metric: .disk, symbol: "internaldrive",
                                             figures: [
                                                 verdict(free.map { MetricFormat.diskBytes($0) }, tone,
                                                           .diskCapacity),
                                                 arrowFigure(rate(sample.diskWrite, inBits: false,
                                                             prefix: diskWriteArrow), .diskWrite),
                                                 arrowFigure(rate(sample.diskRead, inBits: false,
                                                             prefix: diskReadArrow), .diskRead),
                                             ],
                                             lines: [
                                                 line(.diskWrite, in: samples, \.diskWrite,
                                                      window: window, now: now),
                                                 line(.diskRead, in: samples, \.diskRead,
                                                      window: window, now: now),
                                             ])
        case .power:
            // Watts are a number and not a verdict: the dashboard has no limit
            // for a machine's draw, and a figure with no limit has no colour
            // but its own. The watt-keeping page says what a draw means.
            return NotchDashboardCardReading(metric: .power, symbol: "powerplug.fill",
                                             figures: [figure(sample.watts.map(MetricFormat.wattsCompact), .power)],
                                             lines: [line(.power, in: samples, \.watts, window: window, now: now)])
        case .battery, .fan, .devices:
            // Not the page's cards. Their readings are the Power page's, and
            // Fan Control's own page, and this function is only ever asked for
            // the six.
            return NotchDashboardCardReading(metric: metric, symbol: "questionmark", figures: [], lines: [])
        }
    }

    /// A throughput with its arrow, in the unit the settings chose for the
    /// network, and the same reading in the short spelling. A reading that is
    /// not a number says nothing in either.
    private static func rate(_ bytesPerSecond: Double?, inBits: Bool,
                             prefix: String) -> (full: String?, short: String?) {
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return (nil, nil) }
        return (prefix + " " + MetricFormat.networkRate(bytesPerSecond, inBits: inBits),
                prefix + MetricFormat.networkRateCompact(bytesPerSecond, inBits: inBits))
    }

    /// A throughput's figure: the full spelling and the short one, in the
    /// arrow's colour, and quiet when there is nothing to say.
    /// A figure that is only a number: the metric's own colour, and no shorter
    /// spelling of its own.
    private static func figure(_ text: String?, _ role: NotchChartRole) -> NotchMetricFigure {
        NotchMetricFigure(text: text, voice: text == nil ? .quiet : .identity(role))
    }

    private static func arrowFigure(_ rate: (full: String?, short: String?),
                                    _ role: NotchChartRole) -> NotchMetricFigure {
        NotchMetricFigure(text: rate.full, compact: rate.short,
                          voice: rate.full == nil ? .quiet : .identity(role))
    }

    private static func verdict(_ text: String?, _ tone: NotchMetricTone,
                                _ role: NotchChartRole? = nil) -> NotchMetricFigure {
        guard let text else { return NotchMetricFigure(text: nil, voice: .quiet) }
        // A reading with no verdict of its own keeps the metric's colour: the
        // page has no limit for a volume's room until the volume runs short,
        // and no limit at all for a watt.
        return NotchMetricFigure(text: text, voice: tone == .identity && role != nil ? .identity(role!) : .verdict(tone))
    }

    /// The readings of one moment and the moments of the charts, from the
    /// monitor's snapshot. Asked in the page, which is where the snapshot
    /// lives: the cards' rules stay a function of a value, and a test asks them
    /// about a value it built and not about the sampler, the IOKit clients, or
    /// the machine's sensors.
    static func activity(of disk: DiskReading?) -> (read: Double, write: Double)? {
        let devices = disk?.uniqueIODevices ?? []
        let readValues = devices.compactMap(\.readBytesPerSec)
        let writeValues = devices.compactMap(\.writeBytesPerSec)
        guard !readValues.isEmpty || !writeValues.isEmpty else { return nil }
        return (readValues.reduce(0, +), writeValues.reduce(0, +))
    }

    private static func line(_ role: NotchChartRole, in samples: [SystemMetricSample],
                             _ field: KeyPath<SystemMetricSample, Double?>,
                             window: TimeInterval, now: TimeInterval) -> NotchChartLine {
        NotchChartLine(role: role, points: SystemMetricSeries.points(in: samples, field,
                                                                    window: window, endingAt: now))
    }
}

/// The colour a card's line is drawn in: which line it is, whatever the
/// reading says.
///
/// Kept apart from the health colours on purpose. A line belongs to its metric
/// and says *which* reading this is; a figure belongs to a threshold and says
/// *how it reads*. A card that wore its threshold's colour twice would shout
/// one piece of news in two voices, and a line that changed colour with its
/// figure could not be known by its shape and colour at a glance.
enum NotchChartRole: String, Equatable, CaseIterable, Identifiable {
    case cpu, gpu, memory, power, networkDown, networkUp, diskWrite, diskRead
    /// The room a volume has left, in the volume's own voice.
    case diskCapacity

    var id: String { rawValue }

    /// The line's colour.
    ///
    /// The palette is the dashboard's own, and one reading never borrows
    /// another's colour: the two directions of the network are the network's
    /// blue and the watt's orange, which are the two colours the machine's own
    /// meters use for in and out, and the disk's two are the same pair turned
    /// around — the volume's write is the blue going in, its read is the green
    /// coming out.
    var color: Color {
        switch self {
        case .cpu: return NotchChartPalette.teal
        case .gpu: return NotchSplashPalette.blue
        case .memory: return NotchSplashPalette.purple
        case .power: return NotchSplashPalette.orange
        case .networkDown, .diskWrite: return NotchSplashPalette.blue
        case .networkUp: return NotchSplashPalette.orange
        case .diskRead: return NotchSplashPalette.green
        case .diskCapacity: return NotchSplashPalette.beige
        }
    }
}

/// The dashboard's chart palette, as one small set.
///
/// A load's own colour is a teal, so a healthy CPU's line, a healthy CPU's
/// figure and a disk's read are not all the same green: six cards on one page
/// are six things to tell apart.
enum NotchChartPalette {
    static let teal = Color(red: 0.231, green: 0.776, blue: 0.686)
}

/// One figure of a compact card: what it says, and the voice it is spoken in.
struct NotchMetricFigure: Equatable {
    /// The figure, or nil when the machine has no reading for it.
    let text: String?
    /// The same reading in the page's short spelling, for a corner too narrow
    /// for the full one: `↓ 17 KB/s` written `↓ 17K`. The reading and the unit
    /// family are the same; only the spelling is shorter, so a card whose
    /// corner is narrow says less about the width of its words and nothing less
    /// about the machine. A figure with no shorter spelling of its own has none
    /// here, and the card has one fewer way to shrink.
    let compact: String?
    enum Voice: Equatable {
        /// The reading's verdict: green while ordinary, amber at a limit, red
        /// past it. The sustained-load gate has already been answered, so the
        /// tone drawn is the tone the menu bar and the detail page give.
        case verdict(NotchMetricTone)
        /// The metric's own colour, for a number that carries no verdict.
        case identity(NotchChartRole)
        /// Nothing to say, drawn in the page's quiet colour.
        case quiet
    }

    let voice: Voice

    /// The colour the figure is drawn in.
    var color: Color {
        switch voice {
        case .verdict(let tone): return NotchMetricHealth.verdictColor(tone)
        case .identity(let role): return role.color
        case .quiet: return .white.opacity(0.45)
        }
    }

    init(text: String?, compact: String? = nil, voice: Voice) {
        self.text = text
        self.compact = compact
        self.voice = voice
    }
}

/// One line of a compact card's chart.
struct NotchChartLine: Equatable {
    let role: NotchChartRole
    let points: [SystemMetricPoint]

    var hasLine: Bool { points.count > 1 }
}

/// One compact card, ready to draw.
struct NotchDashboardCardReading: Identifiable, Equatable {
    let metric: NotchDashboardMetric
    let symbol: String
    /// The figures in the card's top-right corner, in the order it draws them.
    let figures: [NotchMetricFigure]
    /// The card's lines: one for a single reading, two for a pair.
    let lines: [NotchChartLine]

    var id: String { metric.rawValue }

    /// The card's mark wears the figure's colour when the reading is the news.
    var wantsAttention: Bool {
        figures.contains { if case .verdict(let tone) = $0.voice { return tone.wantsAttention }
            return false }
    }

    /// The figures that fit on one line of the corner.
    ///
    /// A card of one reading has one figure, and a card of two has a line. The
    /// disk's three are the page's one exception: its card draws the room on
    /// one line and the two arrows under it when the width will not hold all
    /// three, which is the view's doing, not this model's.
    var sharesOneLine: Bool { figures.count <= 2 }
}

/// The readings the six cards are built from.
///
/// A plain value, made from the monitor's snapshot where the snapshot lives —
/// in the page. The cards' rules are then a function of a value a test can
/// build, and no test has to reach the sampler, the IOKit clients, or the
/// machine's sensors to ask what a card says when a reading is missing.
struct NotchDashboardSample: Equatable {
    /// The moment's readings. Shares are 0…1, throughputs bytes a second.
    var cpu: Double? = nil
    var gpu: Double? = nil
    var memory: Double? = nil
    var netDown: Double? = nil
    var netUp: Double? = nil
    var diskRead: Double? = nil
    var diskWrite: Double? = nil
    var watts: Double? = nil
    /// The volume the page speaks for: its room left, and its whole.
    var diskFreeBytes: UInt64? = nil
    var diskTotalBytes: UInt64? = nil
    /// The moments the charts draw.
    var samples: [SystemMetricSample] = []
    /// The tones of the loads that have to hold before they are believed.
    var sustained: [NotchDashboardMetric: NotchMetricTone] = [:]
}
