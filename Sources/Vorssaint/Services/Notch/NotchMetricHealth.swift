// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SwiftUI

/// How one monitoring reading reads, and what that is worth to the eye.
///
/// The thresholds, not the views, decide this. A tile's figure, its meter and
/// its mark are drawn from one tone, so a reading cannot say "fine" in its
/// number and "low" in its bar.
enum NotchMetricTone: Equatable {
    /// The reading is what it should be. A tile rests in the page's own
    /// white: a healthy page is not painted green, which would leave a
    /// warning nowhere to be seen.
    case nominal
    /// A limit crossed, worth a glance.
    case warning
    /// A limit crossed hard, worth acting on now.
    case critical
    /// A number that is not a verdict - throughput, watts, a count of devices.
    /// It keeps the metric's own colour and never turns red on its own.
    case identity

    /// How loud the tone is, for a gate that only escalates.
    var severity: Int {
        switch self {
        case .nominal, .identity: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    /// Whether the tone says the reading has a problem.
    var wantsAttention: Bool { self == .warning || self == .critical }
}

/// The thresholds a reading is measured against.
///
/// The numbers are the dashboard's: the point where a reading stops being
/// ordinary and the point where it is out of room. A band is written the way a
/// person reads it - the level at which to look twice, and the level at which
/// to act - and one rule serves both directions, because a low charge and a
/// high load are the same news in opposite words.
struct NotchMetricBand: Equatable {
    /// The level at which the reading is worth a glance.
    let warning: Double
    /// The level at which the reading is out of room.
    let critical: Double
    /// Whether a bigger number is the worse one. A charge and a disk's free
    /// space go the other way: there, less is the news.
    var higherIsWorse = true

    /// The tone of a percentage measured against the band. Missing and
    /// unreadable readings are drawn as missing, and carry no verdict.
    func tone(_ percent: Double?) -> NotchMetricTone {
        guard let percent, percent.isFinite else { return .nominal }
        let low = Swift.min(warning, critical), high = Swift.max(warning, critical)
        if higherIsWorse {
            if percent > high { return .critical }
            if percent >= low { return .warning }
        } else {
            if percent < low { return .critical }
            if percent <= high { return .warning }
        }
        return .nominal
    }
}

/// The rules that colour the monitoring readings, in one place.
///
/// The tiles, the menu bar, and every detail page ask the same question here,
/// so a reading does not read green on one surface and amber on the next. The
/// palette is the Splash dashboard's: amber for a limit crossed and red for a
/// limit crossed hard, with the metric's own colour kept while it is ordinary.
enum NotchMetricHealth {
    /// Above this share of a core's work the CPU is worth watching.
    static let cpu = NotchMetricBand(warning: 60, critical: 85)
    static let gpu = NotchMetricBand(warning: 70, critical: 90)
    static let memory = NotchMetricBand(warning: 70, critical: 85)
    /// A charge at this share, and below this one, on battery. The charge is
    /// the one reading where a big number is the good news.
    static let battery = NotchMetricBand(warning: 40, critical: 20, higherIsWorse: false)
    /// A disk's free space at this share, and below it. The free share is
    /// measured as a share of the whole volume, so a 500 GB disk running short
    /// at the same point a 4 TB one does.
    static let diskFree = NotchMetricBand(warning: 20, critical: 10, higherIsWorse: false)
    /// How long a load has to hold before the colour follows it. The monitor
    /// reads every couple of seconds, so this is a handful of readings: long
    /// enough that a second's spike is not news, short enough that a real
    /// load is not hidden.
    static let sustainedSeconds: TimeInterval = 6

    /// The tone of one reading. `metric` decides the band and the direction,
    /// so a caller hands over a percentage and asks nothing else.
    ///
    /// `charging` covers the charge alone: a laptop plugged in has room, and a
    /// low charge with the cable in is a fact about the last hour, not about
    /// the next one.
    static func tone(metric: NotchDashboardMetric, percent: Double?, charging: Bool = false) -> NotchMetricTone {
        switch metric {
        case .cpu: return cpu.tone(percent)
        case .gpu: return gpu.tone(percent)
        case .memory: return memory.tone(percent)
        case .battery: return charging ? .identity : battery.tone(percent)
        case .disk: return diskFree.tone(percent)
        // A busy network, a watt, a device on a cable: numbers, not verdicts.
        // Bandwidth is not illness, and a device count never is.
        case .network, .power, .fan, .devices: return .identity
        }
    }

    /// The colour of a tone, in the metric's own voice.
    ///
    /// A healthy reading wears the metric's identity - a network's blue-cyan, a
    /// power figure's orange, a tile that reports a count in the page's white -
    /// and a reading in trouble wears amber, then red, whichever metric it is:
    /// a warning has to read as a warning in every tile, and a colour that
    /// means one thing for the network and another for memory is not a colour
    /// system.
    static func color(_ tone: NotchMetricTone, metric: NotchDashboardMetric = .cpu) -> Color {
        switch tone {
        case .nominal: return .white
        case .warning: return NotchSplashPalette.amber
        case .critical: return NotchSplashPalette.red
        case .identity: return identityColor(metric)
        }
    }

    /// The metric's own colour, while it carries no verdict.
    static func identityColor(_ metric: NotchDashboardMetric) -> Color {
        switch metric {
        case .network: return Color(red: 0.30, green: 0.72, blue: 0.94)
        case .power: return NotchSplashPalette.orange
        case .battery: return NotchSplashPalette.green
        case .fan, .devices: return .white.opacity(0.75)
        case .cpu, .gpu, .memory, .disk: return .white
        }
    }
}

/// The tone of the readings that must hold before they are believed.
///
/// A single sample proves nothing: a second of compiles, one frame of a game,
/// a photo library indexing itself. The colour follows a load that stays, the
/// same rule the Monitor's notifications use, and lets go at once when the
/// load leaves. A tone is never made louder by a reading that has gone quiet.
struct NotchSustainedTone {
    private var escalated: NotchMetricTone = .nominal
    private var heldSince: TimeInterval?
    private var lastSampleAt: TimeInterval?

    /// The tone to draw, given the tone the reading carries now.
    ///
    /// `sampleAt` is when the reading was really taken, on the system uptime
    /// clock, and nil when the value is only being carried over. The monitor
    /// keeps serving the last reading between reads, and counting those
    /// repeats would let one spike age into a warning on its own.
    mutating func tone(_ reading: NotchMetricTone, at sampleAt: TimeInterval?) -> NotchMetricTone {
        guard reading.severity > NotchMetricTone.nominal.severity else {
            reset()
            return reading
        }
        guard let sampleAt else { return escalated }
        guard sampleAt != lastSampleAt else { return escalated }
        lastSampleAt = sampleAt
        guard reading.severity > escalated.severity else { return escalated }
        guard let since = heldSince else {
            heldSince = sampleAt
            return escalated
        }
        guard sampleAt - since >= NotchMetricHealth.sustainedSeconds else { return escalated }
        escalated = reading
        heldSince = nil
        return reading
    }

    mutating func reset() {
        escalated = .nominal
        heldSince = nil
        lastSampleAt = nil
    }
}
