// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// One monitoring reading as a tile: what it is called, what it reads, how
/// full it is, and how it reads. `metric` is where the tile leads when it is
/// clicked.
///
/// The tone is the reading's verdict, and the tile's figure, its meter and its
/// mark are all drawn from it: one rule, three places, no disagreement.
struct NotchSystemCard: Identifiable {
    let metric: NotchDashboardMetric
    let title: String
    let symbol: String
    let value: String?
    var detail: String? = nil
    var level: Double? = nil
    var tone: NotchMetricTone = .nominal

    var id: String { metric.rawValue }

    /// The reading is the news on its own, so the tile says so without the
    /// person having to read the number.
    var wantsAttention: Bool { tone.wantsAttention }
}

/// The tiles, read from the monitor's snapshot, in one order, with only the
/// metrics this Mac reports.
///
/// The island's System page and the dashboard's grid both ask for these, so a
/// reading says the same thing wherever it shows and the rules for what is
/// available — a battery card only with a battery, a fan card only with fans —
/// live in one place. A metric left out here has no tile anywhere, which is
/// what keeps a click from opening a detail with nothing behind it.
enum NotchSystemCards {
    /// A reading this far along is the news on its own.
    static let busyLevel = 0.85
    /// A disk this full is worth mentioning before it fills.
    static let diskLowFraction = 0.1
    /// A charge this low, on battery, is worth mentioning.
    static let lowChargePercent = 20

    /// The tiles. `sustained` carries the tones of the loads that have to hold
    /// before they are believed - the CPU and the GPU - so a second's spike
    /// does not colour a card, and every surface that draws these tiles gates
    /// the same way.
    static func cards(snapshot: SystemSnapshot, language: AppLanguage,
                      networkSpeedInBits: Bool,
                      sustained: [NotchDashboardMetric: NotchMetricTone] = [:]) -> [NotchSystemCard] {
        let strings = L10n.shared.s
        var cards: [NotchSystemCard] = []
        if AppFeature.monitorCPU.isAvailable {
            cards.append(NotchSystemCard(metric: .cpu, title: strings.cpuLabel, symbol: "cpu",
                                         value: percent(snapshot.cpuUsage), level: snapshot.cpuUsage,
                                         tone: tone(.cpu, percent: percentValue(snapshot.cpuUsage),
                                                    sustained: sustained)))
        }
        if AppFeature.monitorGPU.isAvailable {
            cards.append(NotchSystemCard(metric: .gpu, title: strings.gpuLabel,
                                         symbol: "rectangle.connected.to.line.below",
                                         value: percent(snapshot.gpuUsage), level: snapshot.gpuUsage,
                                         tone: tone(.gpu, percent: percentValue(snapshot.gpuUsage),
                                                    sustained: sustained)))
        }
        if AppFeature.monitorMemory.isAvailable {
            let ratio = snapshot.memoryUsed.flatMap { used in
                snapshot.memoryTotal.flatMap { total in total > 0 ? Double(used) / Double(total) : nil }
            }
            cards.append(NotchSystemCard(metric: .memory, title: strings.memorySection, symbol: "memorychip",
                                         value: percent(ratio), level: ratio,
                                         tone: NotchMetricHealth.tone(metric: .memory,
                                                                      percent: percentValue(ratio))))
        }
        if AppFeature.monitorPower.isAvailable, let power = snapshot.power, power.hasBattery {
            // A charge is the one reading where a big number is the good news,
            // and a laptop with the cable in has room whatever the number says.
            cards.append(NotchSystemCard(metric: .battery, title: strings.batteryLabel,
                                         symbol: power.externalConnected ? "battery.100percent.bolt" : "battery.100percent",
                                         value: power.chargePercent.map { "\($0)%" },
                                         level: power.chargePercent.map { Double($0) / 100 },
                                         tone: NotchMetricHealth.tone(metric: .battery,
                                                                      percent: power.chargePercent.map(Double.init),
                                                                      charging: power.externalConnected)))
        }
        if AppFeature.monitorNetwork.isAvailable {
            // The observed unit, so a switch redraws the tile at once, not on
            // the next sample. A fast network is not an ill one: the tile keeps
            // the network's own colour whatever it carries.
            cards.append(NotchSystemCard(metric: .network, title: strings.networkSection, symbol: "network",
                                         value: snapshot.netDownBytesPerSec.map {
                                             "↓ " + MetricFormat.networkRate($0, inBits: networkSpeedInBits)
                                         },
                                         detail: snapshot.netUpBytesPerSec.map {
                                             "↑ " + MetricFormat.networkRate($0, inBits: networkSpeedInBits)
                                         },
                                         tone: NotchMetricHealth.tone(metric: .network, percent: nil)))
        }
        if AppFeature.monitorDisk.isAvailable {
            let disk = snapshot.disk?.devices.first(where: { $0.mountPath == "/" })
                ?? snapshot.disk?.devices.first(where: \.isInternal)
            // The share of the volume that is free, from the two numbers that
            // make it: a 500 GB disk and a 4 TB one run short at the same
            // share, and a tile that read only bytes would not know that.
            let free = disk.flatMap { device in
                device.totalBytes > 0
                    ? min(1, max(0, Double(device.freeBytes) / Double(device.totalBytes))) : nil
            }
            cards.append(NotchSystemCard(metric: .disk, title: strings.diskAvailable.localizedCapitalized,
                                         symbol: "internaldrive",
                                         value: disk.map { MetricFormat.diskBytes($0.freeBytes) },
                                         level: free.map { 1 - $0 },
                                         tone: NotchMetricHealth.tone(metric: .disk,
                                                                      percent: percentValue(free))))
        }
        // The panel's power and fan sections, as tiles opening the same details.
        if AppFeature.monitorPower.isAvailable {
            let power = snapshot.power
            cards.append(NotchSystemCard(metric: .power, title: strings.powerSection, symbol: "powerplug.fill",
                                         value: power?.systemWatts.map(MetricFormat.wattsCompact),
                                         detail: power?.externalConnected == true
                                             ? power?.adapterWatts.map(MetricFormat.watts) : nil,
                                         tone: NotchMetricHealth.tone(metric: .power, percent: nil)))
        }
        if AppFeature.fanControl.isAvailable, !snapshot.fanSpeeds.isEmpty {
            let fan = FeatureStrings.fanControl(language)
            cards.append(NotchSystemCard(metric: .fan, title: fan.title, symbol: "fanblades",
                                         value: snapshot.fanSpeeds.first.map {
                                             String(format: fan.rpmFormat, Int($0.rounded()))
                                         },
                                         tone: NotchMetricHealth.tone(metric: .fan, percent: nil)))
        }
        if AppFeature.connectedDevices.isAvailable {
            let devices = FeatureStrings.connectedDevices(language)
            cards.append(NotchSystemCard(metric: .devices, title: devices.title, symbol: "cable.connector",
                                         value: "\(snapshot.connectedDevices.count)",
                                         tone: NotchMetricHealth.tone(metric: .devices, percent: nil)))
        }
        return cards
    }

    static func isBusy(_ level: Double?) -> Bool {
        guard let level, level.isFinite else { return false }
        return level >= busyLevel
    }

    /// A share as a figure, and the same share as the thresholds read it. The
    /// rules are the page-shared ones, so a tile, a compact card, a menu bar
    /// indicator and a detail page write the same number and mean the same thing.
    static func percent(_ value: Double?) -> String? { NotchMetricReading.percent(value) }
    static func percentValue(_ value: Double?) -> Double? { NotchMetricReading.percentValue(value) }

    /// The tone of a load: the threshold's answer, with the gate's answer over
    /// it when the gate has one. A load that has not held keeps the page's
    /// white.
    static func tone(_ metric: NotchDashboardMetric, percent: Double?,
                     sustained: [NotchDashboardMetric: NotchMetricTone]) -> NotchMetricTone {
        NotchMetricReading.tone(metric, percent: percent, sustained: sustained)
    }
}

/// The tones of the readings that have to hold before they are believed: the
/// load, not the moment.
///
/// The gate needs the samples, and only the sampler has them, so this is the
/// one object that watches the monitor and publishes what the tiles draw. A
/// tile asks it for its metric and gets the same answer the menu bar and the
/// detail pages give, from the same samples.
final class NotchMetricSustain: ObservableObject {
    static let shared = NotchMetricSustain()

    /// The gated tone of the metrics that need one, in percent units.
    @Published private(set) var tones: [NotchDashboardMetric: NotchMetricTone] = [:]

    private var gates: [NotchDashboardMetric: NotchSustainedTone] = [:]
    private var cancellables = Set<AnyCancellable>()

    private init() {
        SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.evaluate(snapshot) }
            .store(in: &cancellables)
    }

    /// The tone a tile draws: the reading's own, with the load's gates applied.
    func tone(for metric: NotchDashboardMetric, percent: Double?, charging: Bool = false) -> NotchMetricTone {
        NotchMetricReading.gate(NotchMetricHealth.tone(metric: metric, percent: percent, charging: charging),
                                gated: tones[metric])
    }

    private func evaluate(_ snapshot: SystemSnapshot) {
        var next = tones
        gate(&next, .cpu, percent: snapshot.cpuUsage.map { $0 * 100 }, at: snapshot.cpuUsageReadAt)
        gate(&next, .gpu, percent: snapshot.gpuUsage.map { $0 * 100 }, at: snapshot.gpuUsageReadAt)
        if next != tones { tones = next }
    }

    private func gate(_ tones: inout [NotchDashboardMetric: NotchMetricTone], _ metric: NotchDashboardMetric,
                      percent: Double?, at readAt: TimeInterval?) {
        let reading = NotchMetricHealth.tone(metric: metric, percent: percent)
        var gate = self.gates[metric] ?? NotchSustainedTone()
        tones[metric] = gate.tone(reading, at: readAt)
        self.gates[metric] = gate
    }
}
