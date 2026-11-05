// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The open island's one page: the levels, the players and the timer that are
/// running, the monitoring grid, and the way to the sections, all at once.
///
/// The island is a dashboard, not a stack of destinations. Each section keeps
/// its place, so a song starting adds a card to the middle of the page and
/// takes nothing away, and a timer ending leaves the levels, the grid and the
/// sections exactly where they were. A tile of the grid opens its detail, which
/// is a page of its own over the dashboard — the drill-down, not a rebuild of
/// the page.
///
/// The page draws no headings: the sliders, the cards, the grid and the circles
/// say what they are. Every measurement here comes from `NotchDashboardLayout`,
/// which the island's own size is measured from too, so the page and the shape
/// around it agree before either is drawn.
struct NotchDashboardView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var timer = NotchTimerService.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var sessions = PlaybackSessionsService.shared
    @AppStorage(DefaultsKey.networkSpeedUnit) private var networkSpeedUnit = NetworkSpeedUnit.bytes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The players this page shows: the one the system names as playing, and
    /// every other player whose own dictionary says it is playing. Each is a
    /// card; none of them is the other's owner. The island measures the page
    /// from the same list, so it comes from the service.
    private var players: [Int] { service.dashboardPlayerIDs }
    /// The system's own session, the one with the cover, the queue and the
    /// lyrics. Its process is the id its card is known by.
    private var primaryPlayerID: Int? {
        guard NotchSupport.watchesMusicActivity(), music.playback != nil else { return nil }
        return Int(music.playback?.track.appPID ?? -1)
    }


    /// The cards of the middle section, decided apart from one another: the
    /// players first, then the timer.
    private var activities: [NotchDashboardActivity] {
        NotchDashboardSupport.activities(players: players,
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

    // MARK: - Quick Controls

    /// The levels, on one row: volume and brightness, the Controls page's own
    /// controls drawn narrow — a mark and a bar each, no chooser, no headings —
    /// with the rest of the row left empty.
    private var quickControls: some View {
        HStack(spacing: NotchDashboardLayout.quickControlsSpacing) {
            ForEach(NotchSupport.controls().filter(\.isLevel)) { item in
                NotchLevelControls(item: item, compact: true, service: service)
            }
            Spacer(minLength: 0)
        }
        .frame(height: NotchDashboardLayout.quickControlsHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NotchDashboardSection.quickControls.title(l10n.language))
        .accessibilityIdentifier("notch.dashboard.controls")
    }

    // MARK: - Live Activities

    /// The running activities, one card each, in order. Every card has its own
    /// background and its own boundary, so two players at once read as two
    /// controls, and the timer's card is neither of theirs.
    private var liveActivities: some View {
        VStack(alignment: .leading, spacing: NotchDashboardLayout.cardSpacing) {
            ForEach(activities) { activity in
                switch activity {
                case .player(let id):
                    if id == primaryPlayerID, let playback = music.playback {
                        nowPlayingCard(playback)
                    } else if let session = sessions.session(id: Int32(id)) {
                        playerCard(session)
                    }
                case .timer:
                    timerCard
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NotchDashboardSection.liveActivities.title(l10n.language))
        .accessibilityIdentifier("notch.dashboard.activities")
    }

    /// A card of the section: the page's charcoal, its own corners, its own
    /// hairline, and the height the layout measured for it.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: NotchDashboardLayout.activityCardHeight)
            .modifier(NotchControlSurface(cornerRadius: NotchDashboardLayout.cornerRadius,
                                          fillOpacity: NotchDashboardLayout.fillOpacity))
    }

    /// The system's player as a card: its cover, the song beside it with its
    /// position and the two times, and the transport at the card's end. The
    /// card opens the player's page, where the queue, the lyrics and the
    /// output are.
    private func nowPlayingCard(_ playback: NotchPlayback) -> some View {
        card {
            HStack(spacing: 8) {
                Button { service.select(.music) } label: {
                    HStack(spacing: 8) {
                        NotchArtwork(image: music.artwork, size: NotchDashboardLayout.activityArtwork,
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
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notch.dashboard.nowPlaying")
    }

    /// Another player's card, read from that player's own scripting dictionary:
    /// its mark and name, what it plays and how far along it is, and the
    /// transport that drives that process and no other. A player that has not
    /// agreed to be automated shows its name and the way to ask it.
    private func playerCard(_ session: NotchPlaybackSession) -> some View {
        card {
            HStack(spacing: 8) {
                appMark(session)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title ?? session.appName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Text(session.artist ?? session.appName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    playerProgress(session)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                playerTransport(session)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(session.appName)
        .accessibilityIdentifier("notch.dashboard.player.\(session.pid)")
    }

    /// The player's own icon, so two cards at once are told apart at a glance.
    private func appMark(_ session: NotchPlaybackSession) -> some View {
        Group {
            if let icon = session.icon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .frame(width: NotchDashboardLayout.activityArtwork, height: NotchDashboardLayout.activityArtwork)
        .accessibilityHidden(true)
    }

    /// The song's position, and the two times the player's own clock gives.
    /// A player that does not answer with a length says what it is doing.
    @ViewBuilder private func playerProgress(_ session: NotchPlaybackSession) -> some View {
        if let fraction = session.fraction {
            HStack(spacing: 4) {
                Text(session.elapsedText ?? "0:00")
                    .font(.system(size: 8, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.secondary)
                NotchMeter(value: fraction, height: 3, tint: .white.opacity(0.85))
                Text(session.remainingText ?? "0:00")
                    .font(.system(size: 8, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else {
            // A player that gives no length has no position to draw; the card
            // says what it plays and leaves the bar empty.
            NotchMeter(value: 0, height: 3)
        }
    }

    /// The card drives the player it belongs to. A player that has not agreed
    /// to be automated gets the way to agree, in the player's page's own words.
    @ViewBuilder private func playerTransport(_ session: NotchPlaybackSession) -> some View {
        switch session.access {
        case .granted:
            HStack(spacing: 2) {
                ForEach(PlaybackSessionsService.cardCommands.indices, id: \.self) { index in
                    transportButton(session, PlaybackSessionsService.cardCommands[index])
                }
            }
        case .consent:
            VStack(spacing: 3) {
                Button(FeatureStrings.notchMusicExtras(l10n.language).allowPlayback) { sessions.requestConsent(session) }
                    .buttonStyle(.borderless).font(.system(size: 10, weight: .medium))
                    .disabled(sessions.requesting)
                if sessions.requesting { ProgressView().controlSize(.small) }
            }
        case .denied:
            Button(l10n.s.permissionOpenSettings) { Permissions.shared.openAutomationSettings() }
                .buttonStyle(.borderless).font(.system(size: 10, weight: .medium))
        case .unavailable:
            Button(FeatureStrings.notchMusicExtras(l10n.language).openPlayer) { session.app?.activate(options: [.activateAllWindows]) }
                .buttonStyle(.borderless).font(.system(size: 10, weight: .medium))
        }
    }

    private func transportButton(_ session: NotchPlaybackSession, _ command: NotchPlaybackCommand) -> some View {
        Button { sessions.send(command, to: session) } label: {
            Image(systemName: command.dashboardSymbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 7, lifts: false))
        .disabled(!session.canSend(command))
        .accessibilityLabel(command.dashboardTitle(FeatureStrings.radialMenu(l10n.language)))
    }

    /// A running timer as a card: its phase, its clock, and the pause that
    /// holds it. The clock and the phase open the timer's page, where the way
    /// to start another one is.
    private var timerCard: some View {
        card {
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
        }
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

    /// Every reading at once, four in a row, each tile a label, a value and a
    /// meter of its own. The grid is the page's grid, not a summary: nothing is
    /// folded into a chosen metric, and a tile opens its detail at once.
    private var systemMonitoring: some View {
        VStack(spacing: NotchDashboardLayout.metricSpacing) {
            ForEach(NotchDashboardLayout.metricRowRanges(tiles: tiles.count,
                                                         columns: NotchDashboardLayout.metricColumns),
                    id: \.lowerBound) { row in
                HStack(spacing: NotchDashboardLayout.metricSpacing) {
                    ForEach(Array(tiles[row])) { tile in
                        metricTile(tile)
                    }
                    // An unfilled row keeps its tiles at the width of the
                    // others, so the grid stays a grid.
                    ForEach(0..<(NotchDashboardLayout.metricColumns - tiles[row].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
            if tiles.isEmpty {
                Text(l10n.s.monitorUnavailable)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: NotchDashboardLayout.metricTileHeight)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NotchDashboardSection.systemMonitoring.title(l10n.language))
        .accessibilityIdentifier("notch.dashboard.system")
    }

    private func metricTile(_ tile: NotchSystemCard) -> some View {
        let selected = service.selectedMetric == tile.metric.detailKind
        return Button { service.showMetric(tile.metric.detailKind) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: tile.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(tile.wantsAttention ? .orange : .white.opacity(0.6))
                        .frame(width: 12)
                    Text(tile.title)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                Text(tile.value ?? "…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: tile.value)
                Spacer(minLength: 0)
                if let level = tile.level {
                    NotchMeter(value: level, height: 3, tint: tile.wantsAttention ? .orange : .white)
                } else {
                    NotchMeter(value: 0, height: 3)
                }
            }
            .padding(EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: NotchDashboardLayout.metricTileHeight)
            .modifier(NotchControlSurface(cornerRadius: 10, selected: selected,
                                          fillOpacity: NotchDashboardLayout.fillOpacity))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 10, lifts: false))
        .accessibilityLabel(tile.title)
        .accessibilityValue([tile.value, tile.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("notch.dashboard.metric.\(tile.metric.rawValue)")
        .help(tile.title)
    }

    // MARK: - Explore

    /// The sections as round marks, seven in a row. No words, no shortcut
    /// hints and no border: the marks are the ones the gallery's tiles carry,
    /// and a mark goes to the page it has always gone to.
    private var explore: some View {
        let columns = NotchDashboardLayout.exploreColumns(width: pageWidth)
        let rows = NotchDashboardSupport.rows(count: sections.count, columns: columns)
        return VStack(spacing: NotchDashboardLayout.exploreSpacing) {
            ForEach(rows, id: \.lowerBound) { row in
                HStack(spacing: NotchDashboardLayout.exploreSpacing) {
                    ForEach(Array(sections[row])) { module in
                        exploreButton(module)
                            .frame(maxWidth: .infinity)
                    }
                    // A short row keeps its marks at the width of a full one.
                    ForEach(0..<(rows.first?.count ?? columns) - sections[row].count, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NotchDashboardSection.explore.title(l10n.language))
        .accessibilityIdentifier("notch.dashboard.explore")
    }

    /// The width the page has, which the island measures the same way.
    private var pageWidth: CGFloat { service.dashboardContentWidth }


    private func exploreButton(_ module: NotchModule) -> some View {
        let current = service.selected == module
        return Button { service.select(module) } label: {
            Image(systemName: module.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(module.dashboardTint)
                .frame(width: NotchDashboardLayout.exploreButton, height: NotchDashboardLayout.exploreButton)
                .background(.white.opacity(current ? 0.18 : 0.08), in: Circle())
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

private extension NotchPlaybackCommand {
    var dashboardSymbol: String {
        switch self {
        case .previous: return "backward.fill"
        case .toggle: return "play.pause"
        case .next: return "forward.fill"
        default: return "play.fill"
        }
    }

    func dashboardTitle(_ text: RadialMenuFeatureStrings) -> String {
        switch self {
        case .previous: return text.mediaPrevious
        case .next: return text.mediaNext
        default: return text.mediaPlayPause
        }
    }
}
