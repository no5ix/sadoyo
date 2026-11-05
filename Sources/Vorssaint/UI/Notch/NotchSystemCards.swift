// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One monitoring reading as a tile: what it is called, what it reads, and how
/// full it is. `metric` is where the tile leads when it is clicked.
struct NotchSystemCard: Identifiable {
    let metric: NotchDashboardMetric
    let title: String
    let symbol: String
    let value: String?
    var detail: String? = nil
    var level: Double? = nil
    /// Set when the reading itself is the news, so the meter says so without
    /// the person having to read the number.
    var wantsAttention = false

    var id: String { metric.rawValue }
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

    static func cards(snapshot: SystemSnapshot, language: AppLanguage,
                      networkSpeedInBits: Bool) -> [NotchSystemCard] {
        let strings = L10n.shared.s
        var cards: [NotchSystemCard] = []
        if AppFeature.monitorCPU.isAvailable {
            cards.append(NotchSystemCard(metric: .cpu, title: strings.cpuLabel, symbol: "cpu",
                                         value: percent(snapshot.cpuUsage), level: snapshot.cpuUsage,
                                         wantsAttention: isBusy(snapshot.cpuUsage)))
        }
        if AppFeature.monitorGPU.isAvailable {
            cards.append(NotchSystemCard(metric: .gpu, title: strings.gpuLabel,
                                         symbol: "rectangle.connected.to.line.below",
                                         value: percent(snapshot.gpuUsage), level: snapshot.gpuUsage,
                                         wantsAttention: isBusy(snapshot.gpuUsage)))
        }
        if AppFeature.monitorMemory.isAvailable {
            let ratio = snapshot.memoryUsed.flatMap { used in
                snapshot.memoryTotal.flatMap { total in total > 0 ? Double(used) / Double(total) : nil }
            }
            cards.append(NotchSystemCard(metric: .memory, title: strings.memorySection, symbol: "memorychip",
                                         value: percent(ratio), level: ratio, wantsAttention: isBusy(ratio)))
        }
        if AppFeature.monitorPower.isAvailable, let power = snapshot.power, power.hasBattery {
            cards.append(NotchSystemCard(metric: .battery, title: strings.batteryLabel,
                                         symbol: power.externalConnected ? "battery.100percent.bolt" : "battery.100percent",
                                         value: power.chargePercent.map { "\($0)%" },
                                         level: power.chargePercent.map { Double($0) / 100 },
                                         wantsAttention: !power.externalConnected
                                             && (power.chargePercent ?? 100) <= lowChargePercent))
        }
        if AppFeature.monitorNetwork.isAvailable {
            // The observed unit, so a switch redraws the tile at once, not on
            // the next sample.
            cards.append(NotchSystemCard(metric: .network, title: strings.networkSection, symbol: "network",
                                         value: snapshot.netDownBytesPerSec.map {
                                             "↓ " + MetricFormat.networkRate($0, inBits: networkSpeedInBits)
                                         },
                                         detail: snapshot.netUpBytesPerSec.map {
                                             "↑ " + MetricFormat.networkRate($0, inBits: networkSpeedInBits)
                                         }))
        }
        if AppFeature.monitorDisk.isAvailable {
            let disk = snapshot.disk?.devices.first(where: { $0.mountPath == "/" })
                ?? snapshot.disk?.devices.first(where: \.isInternal)
            cards.append(NotchSystemCard(metric: .disk, title: strings.diskAvailable.localizedCapitalized,
                                         symbol: "internaldrive",
                                         value: disk.map { MetricFormat.diskBytes($0.freeBytes) },
                                         level: disk.map { 1 - $0.usedFraction },
                                         wantsAttention: disk.map { 1 - $0.usedFraction < diskLowFraction } ?? false))
        }
        // The panel's power and fan sections, as tiles opening the same details.
        if AppFeature.monitorPower.isAvailable {
            let power = snapshot.power
            cards.append(NotchSystemCard(metric: .power, title: strings.powerSection, symbol: "powerplug.fill",
                                         value: power?.systemWatts.map(MetricFormat.wattsCompact),
                                         detail: power?.externalConnected == true
                                             ? power?.adapterWatts.map(MetricFormat.watts) : nil))
        }
        if AppFeature.fanControl.isAvailable, !snapshot.fanSpeeds.isEmpty {
            let fan = FeatureStrings.fanControl(language)
            cards.append(NotchSystemCard(metric: .fan, title: fan.title, symbol: "fanblades",
                                         value: snapshot.fanSpeeds.first.map {
                                             String(format: fan.rpmFormat, Int($0.rounded()))
                                         }))
        }
        if AppFeature.connectedDevices.isAvailable {
            let devices = FeatureStrings.connectedDevices(language)
            cards.append(NotchSystemCard(metric: .devices, title: devices.title, symbol: "cable.connector",
                                         value: "\(snapshot.connectedDevices.count)"))
        }
        return cards
    }

    static func isBusy(_ level: Double?) -> Bool {
        guard let level, level.isFinite else { return false }
        return level >= busyLevel
    }

    static func percent(_ value: Double?) -> String? {
        value.flatMap { $0.isFinite ? "\(Int((min(1, max(0, $0)) * 100).rounded()))%" : nil }
    }
}
