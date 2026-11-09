// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The measurements of a compact card, drawn as lines over time.
///
/// The horizontal axis is the machine's clock, not the order the app happened
/// to draw in: each point is placed at its own instant, so two lines of one
/// card — a network's two directions, a volume's write and read — are drawn
/// against the same instants, and a stretch with no samples is a stretch with
/// no line. Where the monitor stopped reading, the line stops too: the space
/// between the last reading and the next is not crossed by a straight guess at
/// what the machine did in the meantime.
///
/// Two lines of one card share their height scale, because the card is a
/// comparison. Each line is drawn in its metric's own colour and never in the
/// colour of a threshold: the figure above it says how the reading is, and the
/// line says which reading this is.
struct NotchTimedChart: View {
    let lines: [NotchChartLine]
    var height: CGFloat = NotchDashboardLayout.metricChartHeight
    /// The room kept at the top and bottom, so a peak and a trough are both
    /// seen as the line's own thickness.
    var padding: CGFloat = 2
    var lineWidth: CGFloat = 1.25

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if hasLine {
                    ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                        Path { path in
                            var started = false
                            for point in run.points {
                                let at = position(of: point, in: proxy.size)
                                if started {
                                    path.addLine(to: at)
                                } else {
                                    path.move(to: at)
                                    started = true
                                }
                            }
                        }
                        .stroke(run.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round,
                                                             lineJoin: .round))
                    }
                } else {
                    // Nothing measured: the place where the line will go.
                    Path { path in
                        let y = (proxy.size.height - padding * 2) / 2 + padding
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.22),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 3], dashPhase: 1))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var points: [SystemMetricPoint] { lines.flatMap(\.points) }

    private var hasLine: Bool {
        lines.contains { $0.points.count > 1 } && domain.upperBound > domain.lowerBound
    }

    /// The instants the chart spans: the whole window the lines were measured
    /// across, so both lines of a card are drawn against one clock.
    private var domain: ClosedRange<TimeInterval> {
        let times = points.times
        guard let low = times.min(), let high = times.max(), high > low else { return 0...1 }
        return low...high
    }

    /// The heights shared by the card's lines, so one line's spike is not
    /// drawn as tall as the other line's whole history.
    private var scale: ClosedRange<Double> {
        SystemMetricSeries.scale(of: lines.map(\.points)) ?? 0...1
    }

    /// One unbroken run of one line: its colour, and the points it joins.
    private struct Run {
        let tint: Color
        let points: [SystemMetricPoint]
    }

    private var runs: [Run] {
        lines.flatMap { line in
            SystemMetricSeries.runs(of: line.points).map { range in
                Run(tint: line.role.color, points: Array(line.points[range]))
            }
        }.filter { $0.points.count > 1 }
    }

    private func position(of point: SystemMetricPoint, in size: CGSize) -> CGPoint {
        let span = domain.upperBound - domain.lowerBound
        let share = span > 0 ? (point.at - domain.lowerBound) / span : 0
        let heights = scale.upperBound - scale.lowerBound
        let top = heights > 0 ? (scale.upperBound - point.value) / heights : 0.5
        let usable = max(0, size.height - padding * 2)
        return CGPoint(x: CGFloat(share) * size.width,
                       y: padding + CGFloat(max(0, min(1, top))) * usable)
    }
}

/// One card of the dashboard's grid: its mark, its readings in the corner, and
/// the line of what it has measured.
///
/// The card has no title. Six of them fill the page in two rows of three, and
/// a seventh word in a small card is a word the page has to take from the
/// reading: the mark says which reading this is, the figure in the corner says
/// what it reads, and the line under it says what it has been doing. The
/// reading's name is spoken to a screen reader and shown as the pointer's
/// help, where it costs the page nothing.
///
/// The card is a whole, and it is drawn as one: the mark, the figures and the
/// chart are laid out at the height the page measures the card at, so the
/// page's height and the card's own agree before either is drawn.
struct NotchSystemMetricTile: View {
    let reading: NotchDashboardCardReading
    /// The reading's name, for the screen reader and the pointer's help. The
    /// card draws no title, and the page never says less about itself.
    let title: String
    let selected: Bool
    let select: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The colour the card's mark wears: the figure's, when the reading is the
    /// news, and the page's quiet white when it is not.
    private var markColor: Color {
        guard reading.wantsAttention else { return .white.opacity(0.6) }
        return reading.figures.first(where: { if case .verdict = $0.voice { return true }; return false })?.color
            ?? .white.opacity(0.6)
    }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: reading.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(markColor)
                        .frame(width: 15)
                    Spacer(minLength: 2)
                    figures
                }
                Spacer(minLength: 0)
                NotchTimedChart(lines: reading.lines, height: NotchDashboardLayout.metricChartHeight)
            }
            .padding(NotchDashboardLayout.metricTilePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: NotchDashboardLayout.metricTileHeight)
            .modifier(NotchControlSurface(cornerRadius: 10, selected: selected,
                                          fillOpacity: NotchDashboardLayout.fillOpacity))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 10, lifts: false))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(reading.figures.map { $0.text ?? NotchSplashSupport.placeholder }
            .joined(separator: " "))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("notch.dashboard.metric.\(reading.metric.rawValue)")
        .help(title)
    }

    /// The readings, in the card's top-right corner.
    ///
    /// One and two figures sit on the card's one line. The disk's three are
    /// the page's one wide card: its room left, and the two arrows of what is
    /// going in and coming out. The corner is the width a tile has left, so a
    /// row is tried at its full size, then at the size that fits, and then in
    /// the short spelling of the same readings; the disk's three end as the
    /// room on one line with the two arrows under it. Nothing is clipped and
    /// nothing is shrunk past what can be read: the corner keeps its figures,
    /// and the card keeps its height.
    @ViewBuilder private var figures: some View {
        if reading.metric == .disk && reading.figures.count > 2 {
            let head = Array(reading.figures.prefix(1))
            let arrows = Array(reading.figures.dropFirst(1))
            ViewThatFits(in: .horizontal) {
                figureRow(reading.figures, size: 10, spacing: 5)
                figureRow(reading.figures, size: 9, spacing: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    figureRow(head, size: 11, spacing: 4)
                    figureRow(arrows, size: 9, spacing: 4)
                }
                VStack(alignment: .trailing, spacing: 1) {
                    figureRow(head, size: 11, spacing: 4)
                    figureRow(arrows, size: 10, spacing: 4, short: true)
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                figureRow(reading.figures, size: 13, spacing: 5)
                figureRow(reading.figures, size: 11, spacing: 4)
                figureRow(reading.figures, size: 11, spacing: 4, short: true)
            }
        }
    }

    private func figureRow(_ figures: [NotchMetricFigure], size: CGFloat, spacing: CGFloat,
                           short: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            ForEach(Array(figures.enumerated()), id: \.offset) { _, figure in
                Text((short ? figure.compact ?? figure.text : figure.text) ?? NotchSplashSupport.placeholder)
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(figure.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25),
                               value: short ? figure.compact ?? figure.text : figure.text)
            }
        }
    }
}
