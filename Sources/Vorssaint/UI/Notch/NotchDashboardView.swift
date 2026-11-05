// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The open island's one page: the levels, the activities that are running,
/// the monitoring grid, and the way to the sections, all at once.
///
/// The island is a dashboard, not a stack of destinations. Each section keeps
/// its place, so a song starting adds a card to the middle of the page and
/// takes nothing away, and a timer ending leaves the levels, the grid and the
/// sections exactly where they were. A tile of the grid opens its detail, which
/// is a page of its own over the dashboard — the drill-down, not a rebuild of
/// the page.
///
/// The sizes of everything here come from `NotchDashboardLayout`, which the
/// island's own height is measured from too, so the page and the shape around
/// it agree before either is drawn.
struct NotchDashboardView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var timer = NotchTimerService.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @AppStorage(DefaultsKey.networkSpeedUnit) private var networkSpeedUnit = NetworkSpeedUnit.bytes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The cards the middle section holds, decided apart from one another.
    private var activities: [NotchDashboardActivity] {
        NotchDashboardSupport.activities(music: music.playback != nil && NotchSupport.watchesMusicActivity(),
                                         timer: timer.session.hasSession && service.modules.contains(.timer))
    }

    /// The same readings the System page draws.
    private var tiles: [NotchSystemCard] {
        NotchSystemCards.cards(snapshot: monitor.snapshot, language: l10n.language,
                               networkSpeedInBits: networkSpeedUnit == .bits)
    }

    private var sections: [NotchModule] { service.filteredSections }
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
    private var activityText: NotchActivityStrings { FeatureStrings.notchActivities(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchDashboardLayout.sectionSpacing) {
            quickControls
            if !activities.isEmpty {
                liveActivities
            }
            systemMonitoring
            explore
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.title)
    }

        /// A section of the dashboard: a card of one shape, its name above its
    /// content, the same at every height, so two of them stacked never read as
    /// one surface.
    private func section<Content: View>(_ identifier: String,
                                        _ section: NotchDashboardSection,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: NotchDashboardLayout.headerSpacing) {
            Text(section.title(l10n.language))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(section.headerTint)
                .lineLimit(1)
                .frame(height: NotchDashboardLayout.headerHeight, alignment: .leading)
            content()
        }
        .padding(.vertical, NotchDashboardLayout.sectionPadding)
        .padding(.horizontal, NotchDashboardLayout.sectionInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(NotchControlSurface(cornerRadius: NotchDashboardLayout.cornerRadius,
                                      fillOpacity: NotchDashboardLayout.fillOpacity))
        .accessibilityIdentifier("notch.dashboard.\(identifier)")
    }

    // MARK: - Quick Controls

    /// The levels, on one row: every slider the home page has, in the order
    /// the home page lists them, each as wide as the next. They set the system
    /// levels the volume and brightness keys move, through the same controls.
    private var quickControls: some View {
        section("controls", .quickControls) {
            HStack(spacing: NotchDashboardLayout.sectionSpacing) {
                ForEach(NotchSupport.controls().filter(\.isLevel)) { item in
                    NotchLevelControls(item: item, service: service)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: NotchDashboardLayout.quickControlsHeight)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Live Activities

    /// The running activities, in order, one card each. The two are decided
    /// apart, so a song and a timer share the section and neither's ending
    /// takes the other's card, the levels, the grid or the sections away.
    private var liveActivities: some View {
        section("activities", .liveActivities) {
            VStack(alignment: .leading, spacing: NotchDashboardLayout.activityCardSpacing) {
                ForEach(activities) { activity in
                    switch activity {
                    case .nowPlaying:
                        if let playback = music.playback {
                            nowPlayingCard(playback)
                        }
                    case .timer:
                        timerCard
                    }
                }
            }
        }
    }

    /// The player as a card: its cover, the song beside it with its position
    /// and the two times, and the transport at the card's end. The card opens
    /// the player's page, where the queue, the lyrics and the output are.
    private func nowPlayingCard(_ playback: NotchPlayback) -> some View {
        HStack(spacing: 8) {
            Button { service.select(.music) } label: {
                HStack(spacing: 8) {
                    NotchArtwork(image: music.artwork, size: NotchDashboardLayout.nowPlayingArtwork,
                                 source: playback.track)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(playback.track.title ?? "")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                        Text(playback.track.artist ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        NotchMusicTimeline(playback: playback, service: music,
                                           tint: music.artworkTint?.color ?? .white, timesBeside: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 8, lifts: false))
            .accessibilityLabel(NotchModule.music.title(l10n.language))
            .accessibilityValue([playback.track.title, playback.track.artist].compactMap { $0 }.joined(separator: ", "))
            .accessibilityHint(text.open)
            NotchMusicTransport(playback: playback, compact: true)
        }
        .frame(height: NotchDashboardLayout.nowPlayingHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notch.dashboard.nowPlaying")
    }

    /// A running timer as a card: its phase, its clock, and the pause that
    /// holds it. The clock and the phase open the timer's page, where the way
    /// to start another one is.
    private var timerCard: some View {
        HStack(spacing: 8) {
            Button { service.select(.timer) } label: {
                HStack(spacing: 7) {
                    Image(systemName: timerSymbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.orange)
                    Text(phaseTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                    timerClock
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 8, lifts: false))
            .accessibilityLabel(phaseTitle)
            .accessibilityHint(text.open)
            Spacer(minLength: 0)
            timerPauseButton
        }
        .frame(height: NotchDashboardLayout.timerHeight)
        .tint(.orange)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notch.dashboard.timer")
    }

    private var timerSymbol: String {
        let session = timer.session
        return session.completed ? "checkmark.circle.fill"
            : session.isPaused ? "pause.circle.fill" : session.countsUp ? "stopwatch" : "timer"
    }

    private var phaseTitle: String {
        let session = timer.session
        if session.cycleFinished { return activityText.pomodoroFinished }
        if session.completed { return activityText.finished }
        return activityText.phase(session.phase)
    }

    /// The countdown, ticking once a second while it runs, and steady when the
    /// timer is held. A stopwatch counts up in the same figure.
    @ViewBuilder private var timerClock: some View {
        let value = NotchTimerSupport.clockText(for: timer.session, at: timer.now)
        if timer.session.isRunning {
            TimelineView(.periodic(from: Date(timeIntervalSinceNow: NotchTimerSupport.tickScheduleOffset(
                for: timer.session, at: timer.now)), by: 1)) { _ in
                clockText(value)
            }
        } else {
            clockText(value)
        }
    }

    private func clockText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.orange)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: value)
            .accessibilityLabel(phaseTitle)
            .accessibilityValue(value)
    }

    /// The pause and the start of the session the card shows. A finished
    /// timer has nothing to hold, so the card offers the page's dismissal.
    private var timerPauseButton: some View {
        let session = timer.session
        let symbol = session.isPaused ? "play.fill" : "pause.fill"
        let title = session.isPaused ? activityText.resume : l10n.s.actionPause
        return Button { timer.pauseOrResume() } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)
                .background(.orange.opacity(0.22), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 12))
        .disabled(!session.isRunning && !session.isPaused)
        .accessibilityLabel(title)
        .help(title)
    }

    // MARK: - System Monitoring

    /// Every reading at once, in four columns, each tile opening its detail.
    /// The grid is the page's grid, not a summary: nothing is folded into a
    /// chosen metric, and the tiles are as they are on the System page.
    private var systemMonitoring: some View {
        section("system", .systemMonitoring) {
            let rows = NotchDashboardLayout.metricRowRanges(tiles: tiles.count,
                                                            columns: NotchDashboardLayout.metricColumns)
            Group {
                if tiles.isEmpty {
                    Text(l10n.s.monitorUnavailable)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: NotchDashboardLayout.metricTileHeight)
                } else {
                    VStack(spacing: NotchDashboardLayout.metricSpacing) {
                        ForEach(rows, id: \.lowerBound) { row in
                            HStack(spacing: NotchDashboardLayout.metricSpacing) {
                                ForEach(Array(tiles[row])) { tile in
                                    metricTile(tile)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func metricTile(_ tile: NotchSystemCard) -> some View {
        let selected = service.selectedMetric == tile.metric.detailKind
        return Button { service.showMetric(tile.metric.detailKind) } label: {
            HStack(spacing: 5) {
                Image(systemName: tile.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tile.wantsAttention ? .orange : .white.opacity(0.65))
                    .frame(width: 13)
                VStack(alignment: .leading, spacing: 0) {
                    Text(tile.title)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                    Text(tile.value ?? "…")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: tile.value)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: NotchDashboardLayout.metricTileHeight)
            .background(.white.opacity(selected ? 0.16 : 0.05),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.white.opacity(selected ? 0.5 : 0.04), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 9, lifts: false))
        .accessibilityLabel(tile.title)
        .accessibilityValue([tile.value, tile.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("notch.dashboard.metric.\(tile.metric.rawValue)")
        .help(tile.title)
    }

    // MARK: - Explore

    /// The sections as round marks, one row where they fit. No words and no
    /// shortcut hints: the marks are the ones the gallery's tiles carry, and a
    /// mark goes to the page it has always gone to.
    private var explore: some View {
        section("explore", .explore) {
            let columns = NotchDashboardLayout.exploreColumns(width: service.dashboardContentWidth
                - NotchDashboardLayout.sectionInset * 2)
            let rows = NotchDashboardSupport.rows(count: sections.count, columns: columns)
            VStack(spacing: NotchDashboardLayout.exploreSpacing) {
                ForEach(rows, id: \.lowerBound) { row in
                    HStack(spacing: NotchDashboardLayout.exploreSpacing) {
                        ForEach(Array(sections[row])) { module in
                            exploreButton(module)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func exploreButton(_ module: NotchModule) -> some View {
        let current = service.selected == module
        return Button { service.select(module) } label: {
            Image(systemName: module.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(module.dashboardTint)
                .frame(width: NotchDashboardLayout.exploreButton, height: NotchDashboardLayout.exploreButton)
                .background(.white.opacity(current ? 0.18 : 0.07), in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(current ? 0.45 : 0.04), lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: NotchDashboardLayout.exploreButton / 2, lifts: false))
        .accessibilityLabel(module.title(l10n.language))
        .accessibilityAddTraits(current ? .isSelected : [])
        .accessibilityIdentifier("notch.dashboard.section.\(module.rawValue)")
        .help(module.title(l10n.language))
    }
}

/// The mark's own colour, shared by the gallery's tiles and the dashboard's
/// circles, so the same section is the same colour in both.
extension NotchModule {
    var dashboardTint: Color {
        switch self {
        case .music: return .pink
        case .calendar: return .red
        case .timer: return .orange
        default: return .white.opacity(0.85)
        }
    }
}

/// The two sections that lead somewhere are labelled in the island's warm
/// ink, so the page says where its labels are followed by a control and where
/// they are followed by a way in.
extension NotchDashboardSection {
    var headerTint: Color {
        switch self {
        case .quickControls, .systemMonitoring: return .secondary
        case .liveActivities, .explore: return Color(red: 0.83, green: 0.77, blue: 0.67)
        }
    }
}
