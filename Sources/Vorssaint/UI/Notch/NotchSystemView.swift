// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Where a monitoring tile leads. `NotchDashboardMetric` is kept apart from
/// the panel's detail kinds, so the dashboard's composition can be compiled
/// and tested without them; this is where the two meet.
extension NotchDashboardMetric {
    var detailKind: MetricDetailKind {
        switch self {
        case .cpu: return .cpu
        case .gpu: return .gpu
        case .memory: return .memory
        case .battery: return .battery
        case .network: return .network
        case .disk: return .disk
        case .power: return .power
        case .fan: return .fan
        case .devices: return .connectedDevices
        }
    }
}

struct NotchSystemView: View {
    let size: CGSize
    let select: (MetricDetailKind) -> Void
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.networkSpeedUnit) private var networkSpeedUnit = NetworkSpeedUnit.bytes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The same readings the dashboard's grid draws, from one place.
    private var cards: [NotchSystemCard] {
        NotchSystemCards.cards(snapshot: monitor.snapshot, language: l10n.language,
                               networkSpeedInBits: networkSpeedUnit == .bits)
    }

    var body: some View {
        let cards = cards
        if cards.isEmpty {
            NotchEmptyView(symbol: "gauge.with.dots.needle.50percent", message: l10n.s.monitorUnavailable)
        } else {
            let inset = NotchLayout.systemHoverInset(width: size.width)
            let rows = NotchLayout.systemRowRanges(count: cards.count, width: size.width - inset * 2)
            let height = NotchLayout.railHeight(rows: rows.count, rowHeight: NotchLayout.systemCardHeight,
                                               spacing: NotchLayout.rowSpacing) + inset * 2
            Group {
                if height > size.height {
                    ScrollView {
                        grid(cards: cards, rows: rows).padding(inset)
                            .contentShape(Rectangle())
                    }
                } else {
                    grid(cards: cards, rows: rows).padding(inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func grid(cards: [NotchSystemCard], rows: [Range<Int>]) -> some View {
        VStack(spacing: NotchLayout.rowSpacing) {
            ForEach(rows, id: \.lowerBound) { row in
                HStack(spacing: NotchLayout.rowSpacing) {
                    ForEach(Array(cards[row])) { card in
                        cardButton(card)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func cardButton(_ card: NotchSystemCard) -> some View {
        Button { select(card.metric.detailKind) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(card.title, systemImage: card.symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary).lineLimit(1)
                Text(card.value ?? "…")
                    .font(.system(size: card.detail == nil ? 22 : 15, weight: .medium, design: .rounded))
                    .monospacedDigit().contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.75)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: card.value)
                if let detail = card.detail {
                    Text(detail).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                } else if let level = card.level {
                    NotchMeter(value: level, tint: card.wantsAttention ? .orange : .white)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: NotchLayout.systemCardHeight)
            .modifier(NotchControlSurface(cornerRadius: 18))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { select(card.metric.detailKind) }
        .accessibilityLabel(card.title)
        .accessibilityValue([card.value, card.detail].compactMap { $0 }.joined(separator: ", "))
    }
}
