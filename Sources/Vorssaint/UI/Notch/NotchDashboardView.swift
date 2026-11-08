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
    @ObservedObject private var splash = NotchSplashService.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @Environment(\.notchBand) private var band
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

    /// The same readings the System page draws, all of them. The page asks the
    /// island for the height they need; the grid is never trimmed to make a page
    /// fit, and an empty grid is a Mac with no sensors, which the page says.
    private var tiles: [NotchSystemCard] {
        NotchSystemCards.cards(snapshot: monitor.snapshot, language: l10n.language,
                               networkSpeedInBits: networkSpeedUnit == .bits)
    }

    private var sections: [NotchModule] { service.filteredSections }
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
    private var activityText: NotchActivityStrings { FeatureStrings.notchActivities(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchDashboardLayout.sectionSpacing) {
            if service.showsDashboardCalendar {
                calendar
            }
            if !activities.isEmpty {
                liveActivities
            }
            systemMonitoring
            explore
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // The levels are handed to the island's top row, which draws them
        // beside the camera: the page starts under them, and the row is filled
        // by the controls instead of left as an empty band.
        .notchBand(leading: { bandLevels(side: .leading) }, trailing: { bandLevels(side: .trailing) })
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.title)
    }

    // MARK: - Quick Controls

    /// The levels, in the island's top row: the Controls page's own controls,
    /// drawn narrow with their chooser of the output or the display kept. The
    /// first sits at the row's leading edge and the last - brightness where a
    /// Mac can set it - at its trailing edge, which is the row the reference
    /// draws and the row the Controls page has always drawn.
    private func bandLevels(side: HorizontalEdge) -> some View {
        NotchBandLevels(band: band, levels: NotchSupport.controls().filter(\.isLevel), side: side) { item in
            NotchLevelControls(item: item, compact: true, service: service)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NotchDashboardSection.quickControls.title(l10n.language))
        .accessibilityIdentifier("notch.dashboard.controls")
    }

    // MARK: - Calendar

    /// The month, the day it is on, and that day's appointments, in a card of
    /// its own: the Calendar page's grid and the Calendar page's events, at the
    /// shortest rows the grid draws itself. The card opens the Calendar page,
    /// where the month has room and the whole week is read.
    private var calendar: some View {
        NotchDashboardCalendarCard(service: service)
            .accessibilityIdentifier("notch.dashboard.calendar")
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
                    } else if let source = playerSource(id) {
                        playerCard(source)
                    }
                case .timer:
                    timerCard
                case .splash:
                    splashCard
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NotchDashboardSection.liveActivities.title(l10n.language))
        .accessibilityIdentifier("notch.dashboard.activities")
    }

    /// The system's player as a card: its cover, the song beside it with its
    /// position and the two times, and the transport at the card's end. The
    /// card is driven where it is - the cover, the words and the times are read,
    /// not pressed - and the player's page is reached from the page's own mark.
    private func nowPlayingCard(_ playback: NotchPlayback) -> some View {
        NotchDashboardCard {
            HStack(spacing: 8) {
                // The cover is the way to the app that plays it, and nothing
                // else: the card's body stays unpressed, and the transport
                // beside it keeps its own clicks.
                openAppButton(pid: Int(playback.track.appPID ?? -1), bundleIdentifier: playback.track.appBundleIdentifier ?? "",
                              identifier: "notch.dashboard.nowPlaying.open",
                              label: NotchArtwork(image: music.artwork, size: NotchDashboardLayout.activityArtwork,
                                                  source: playback.track))
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
                .accessibilityLabel(NotchModule.music.title(l10n.language))
                .accessibilityValue([playback.track.title, playback.track.artist].compactMap { $0 }
                    .joined(separator: ", "))
                NotchMusicTransport(playback: playback, compact: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notch.dashboard.nowPlaying")
    }

    /// Another player's card, read from that player's own report: its cover, its
    /// title and artist, how far along it is, the two times, and the three marks
    /// that drive that process and no other. Nothing is borrowed from the card
    /// above. Where the player reports no cover its app's icon stands in; where
    /// it reports no recording the card says so; where it reports no position no
    /// timeline is drawn, and a player that reports no song to skip is not given
    /// marks that would do nothing.
    private func playerCard(_ source: NotchPlaybackSource) -> some View {
        let reading = music.sourcePlayback(source)
        return NotchDashboardCard(height: NotchDashboardLayout.playerCardHeight) {
            HStack(spacing: 8) {
                // The cover is the way to the app that plays it, and nothing
                // else: the card's body stays unpressed, and the transport
                // beside it keeps its own clicks.
                openAppButton(pid: Int(source.pid), bundleIdentifier: source.bundleIdentifier,
                              identifier: "notch.dashboard.player.\(Int(source.pid)).open",
                              label: NotchArtwork(image: music.sourceArtwork(source),
                                                  size: NotchDashboardLayout.activityArtwork,
                                                  source: reading?.track ?? sourceTrack(source)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(reading?.track.title ?? playerName(source))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Text(reading?.track.artist ?? playerDetail(source))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    // The bar is the player's own position, read-only: seeking
                    // belongs to the player the page follows.
                    if let reading, reading.duration > 0, reading.hasPosition {
                        NotchMusicTimeline(playback: reading, service: music, tint: .white,
                                           timesBeside: true, interactive: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(playerName(source))
                .accessibilityValue([reading?.track.title, reading?.track.artist].compactMap { $0 }
                    .joined(separator: ", "))
                playerTransport(source)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(playerName(source))
        .accessibilityIdentifier("notch.dashboard.player.\(Int(source.pid))")
    }

    /// The app the adapter named for this player, as a track with no song: the
    /// cover of a player that reports none shows the app's own icon.
    private func sourceTrack(_ source: NotchPlaybackSource) -> RadialNowPlayingSnapshot {
        RadialNowPlayingSnapshot(title: nil, artist: nil, album: nil, artworkData: nil,
                                 appBundleIdentifier: source.bundleIdentifier, appPID: source.pid)
    }

    /// What the second line of a card says when the player does not: its name,
    /// and that it is holding nothing, which is what a player reports.
    private func playerDetail(_ source: NotchPlaybackSource) -> String {
        source.hasTrack ? playerName(source)
            : FeatureStrings.radialMenu(l10n.language).mediaNothingPlaying
    }

    /// A player's own transport: the same three round marks as the card above,
    /// each aimed at this player and at no other. The middle mark shows what that
    /// player reports of itself; the two skips are drawn only for a player that
    /// reports a track to skip, so a control that could do nothing is not shown.
    @ViewBuilder private func playerTransport(_ source: NotchPlaybackSource) -> some View {
        // A player that reports no recording of its own cannot be sent a command
        // of its own: the command would reach the player the system is playing.
        // Such a card shows its cover, its words and its position, and no marks.
        if NotchDashboardLayout.commandsReach(player: source) {
            playerMarks(source)
        }
    }

    @ViewBuilder private func playerMarks(_ source: NotchPlaybackSource) -> some View {
        HStack(spacing: NotchDashboardLayout.transportSpacing) {
            let transport = FeatureStrings.radialMenu(l10n.language)
            if source.hasTrack {
                playerMark("backward.fill", NotchPlaybackCommand.previous.dashboardTitle(transport), .previous, source)
            }
            playerMark(source.isPlaying ? "pause.fill" : "play.fill",
                       NotchPlaybackCommand.toggle.dashboardTitle(transport), .toggle, source)
            if source.hasTrack {
                playerMark("forward.fill", NotchPlaybackCommand.next.dashboardTitle(transport), .next, source)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(playerName(source))
    }

    private func playerMark(_ symbol: String, _ title: String, _ command: NotchPlaybackCommand,
                            _ source: NotchPlaybackSource) -> some View {
        NotchCircularIconButton(symbol: symbol, title: title, side: NotchDashboardLayout.transportMarkSide,
                                action: { music.requestCommand(command, for: source) })
            .accessibilityIdentifier("notch.dashboard.player.\(Int(source.pid)).\(command.dashboardName)")
    }

    /// The mark of the app that plays, as the way to that app: a process that
    /// runs is brought forward, and an app the adapter names is opened. The
    /// card's body and its controls are untouched by this.
    private func openAppButton(pid: Int, bundleIdentifier: String, identifier: String,
                               label: some View) -> some View {
        Button { openApplication(pid: pid, bundleIdentifier: bundleIdentifier) } label: {
            label
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: NotchDashboardLayout.appMarkCorner, lifts: false))
        .accessibilityLabel(text.open)
        .accessibilityIdentifier(identifier)
    }

    private func openApplication(pid: Int, bundleIdentifier: String) {
        switch NotchDashboardSupport.appOpening(pid: pid,
                                                isRunning: NSRunningApplication(processIdentifier: pid_t(pid)) != nil,
                                                bundleIdentifier: bundleIdentifier) {
        case .activate(let pid):
            NSRunningApplication(processIdentifier: pid_t(pid))?.activate()
        case .open(let identifier):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(),
                                               completionHandler: nil)
        case .none:
            break
        }
    }

    /// The app's own mark, from the process that reports the track.
    private func appMark(pid: Int) -> some View {
        Group {
            if let icon = NSRunningApplication(processIdentifier: pid_t(pid))?.icon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }

    private func playerSource(_ id: Int) -> NotchPlaybackSource? {
        music.sources.first { Int($0.pid) == id }
    }

    private func playerName(_ source: NotchPlaybackSource) -> String {
        source.displayName
            ?? NSRunningApplication(processIdentifier: pid_t(Int(source.pid)))?.localizedName
            ?? source.bundleIdentifier
    }

    /// A running timer as a card: its phase, its clock, the pause that holds
    /// it and the close that ends it. The reading is read, not pressed - the
    /// card's own buttons drive it - and the Timer page, where another timer is
    /// started, is reached from the page's own mark.
    private var timerCard: some View {
        NotchDashboardCard(height: nil) {
            HStack(spacing: 8) {
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
                .accessibilityLabel(phaseTitle)
                Spacer(minLength: 0)
                // The countdown's own restart: its length again, from the top,
                // running or paused. The marks a card offers are the layout's
                // decision, so a Pomodoro cycle and a stopwatch keep the two
                // marks they have always had.
                if timerCardControls.contains(.reset) {
                    NotchCircularIconButton(symbol: "arrow.triangle.2.circlepath",
                                            title: activityText.reset,
                                            side: NotchDashboardLayout.timerControlSide, filled: true, tint: .orange,
                                            disabled: !timer.session.hasSession) {
                        timer.reset()
                    }
                    .accessibilityIdentifier("notch.dashboard.timer.reset")
                }
                NotchCircularIconButton(symbol: timer.session.isPaused ? "play.fill" : "pause.fill",
                                        title: timer.session.isPaused ? activityText.resume : l10n.s.actionPause,
                                        side: NotchDashboardLayout.timerControlSide, filled: true, tint: .orange,
                                        disabled: !timer.session.isRunning && !timer.session.isPaused) {
                    timer.pauseOrResume()
                }
                .accessibilityIdentifier("notch.dashboard.timer.pause")
                // The card's own way out: it ends the session, and asks nothing
                // of the players, whose cards stay as they are. The same circle,
                // the same size, the same highlight under the pointer.
                NotchCircularIconButton(symbol: "xmark",
                                        title: timer.session.completed ? l10n.s.supportIntroDoneButton : l10n.s.mediaCancel,
                                        side: NotchDashboardLayout.timerControlSide, filled: false) {
                    timer.cancel()
                }
                .accessibilityIdentifier("notch.dashboard.timer.close")
            }
        }
        .tint(.orange)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notch.dashboard.timer")
    }

    /// A Splash session as a card: the same header and the same four readings
    /// as the page's own dashboard, at the width the section has, in the same
    /// colours. The card is read, not pressed; its one mark stops the reading,
    /// and asks nothing of the work running in Splash. The session is not the
    /// card's owner: navigating away leaves it reading, and the card with it.
    private var splashCard: some View {
        NotchSplashDashboardCard(
            snapshot: splash.snapshot,
            phase: splash.phase,
            elapsed: splash.elapsed(),
            isMonitoring: splash.isMonitoring,
            isSpilling: splash.isSpilling,
            failure: splash.failure,
            address: splash.endpointDescription,
            onStop: splash.isMonitoring ? { splash.stop() } : nil,
            compact: true)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(FeatureStrings.notchSplash(l10n.language).title)
            .accessibilityIdentifier("notch.dashboard.splash")
    }

    /// The marks this session's card offers, as the page's layout decides them.
    private var timerCardControls: [NotchDashboardTimerControl] {
        NotchDashboardLayout.timerCardControls(countdown: timer.session.mode == .timer)
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
            .padding(NotchDashboardLayout.metricTilePadding)
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
        case .splash: return .mint
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

    var dashboardName: String {
        switch self {
        case .previous: return "previous"
        case .toggle: return "toggle"
        case .next: return "next"
        default: return "command"
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

/// One card of the page, with the hover of its own. The whole card is the
/// region the pointer lights — the padding and the empty end of the row count
/// as the card, not only the words in it — and the state belongs to this view,
/// so lighting one card cannot light its neighbours. The controls placed inside
/// keep their own clicks: the highlight is the card's background, drawn under
/// them, and the shape that catches the pointer is the card's own outline.
private struct NotchDashboardCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    /// The card's height, or `nil` for a card as tall as what it holds. A card
    /// with a height of its own centres its content in it; a card measured to
    /// its content keeps the edge the same on every side, which is what a card
    /// of one line of text needs.
    var height: CGFloat? = NotchDashboardLayout.activityCardHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false

    var body: some View {
        Group {
            if let height {
                content()
                    .padding(NotchDashboardLayout.activityCardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: .infinity)
                    .frame(height: height)
            } else {
                content()
                    .padding(NotchDashboardLayout.activityCardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
            .modifier(NotchControlSurface(cornerRadius: NotchDashboardLayout.cornerRadius,
                                          selected: hover, fillOpacity: NotchDashboardLayout.fillOpacity))
            .contentShape(RoundedRectangle(cornerRadius: NotchDashboardLayout.cornerRadius, style: .continuous))
            .onHover { hover = $0 }
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: hover)
    }
}

/// The calendar as the page shows it: the month's grid at the rows the grid
/// draws itself, the day's appointments beside it in the page's own colours,
/// and the month's name with the way through the months above. It is the
/// Calendar page's data, read by the Calendar page's own service — no second
/// calendar, no second event list — drawn at the height of six weeks, and the
/// card opens the page, where the month has room.
private struct NotchDashboardCalendarCard: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The month the grid is built around, and the day the appointments are read
    /// for: the page's own two questions, asked here of the same grid.
    @State private var focus = Date()
    @State private var selectedDay: Date?
    @State private var hover = false

    private var text: NotchCalendarStrings { FeatureStrings.notchCalendar(l10n.language) }
    private var now: Date { Date() }
    private var selected: Date { selectedDay ?? Calendar.current.startOfDay(for: now) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The card is the way to the page. Everything in front of this
            // button keeps its own click: a day picks a day, a chevron moves a
            // month, an appointment opens the page at that appointment.
            Button(action: open) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            Group {
                if permissions.calendarAccess == .fullAccess {
                    content
                } else {
                    permission
                }
            }
            .padding(NotchDashboardLayout.calendarCardPadding)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: NotchDashboardLayout.calendarCardHeight)
        .modifier(NotchControlSurface(cornerRadius: NotchDashboardLayout.cornerRadius,
                                      selected: hover, fillOpacity: NotchDashboardLayout.fillOpacity))
        .contentShape(RoundedRectangle(cornerRadius: NotchDashboardLayout.cornerRadius, style: .continuous))
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: hover)
        // Day, month and clock follow the app's language and the user's region,
        // as the Calendar page does.
        .environment(\.locale, l10n.language.formattingLocale())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NotchDashboardSection.calendar.title(l10n.language))
    }

    private var content: some View {
        HStack(alignment: .top, spacing: NotchDashboardLayout.calendarColumnSpacing) {
            VStack(alignment: .leading, spacing: NotchDashboardLayout.calendarHeaderGap) {
                header
                NotchCalendarMonthGrid(month: focus, selectedDay: selectedDay, now: now,
                                       height: NotchDashboardLayout.calendarGridHeight,
                                       events: calendar.events, text: text) { date in
                    selectedDay = Calendar.current.startOfDay(for: date)
                }
                .frame(width: NotchDashboardLayout.calendarGridWidth)
            }
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                .padding(.vertical, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(selected, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                events
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// The month's name and the way through it, and the way back to today when
    /// the grid has wandered off. The row is a header, not a heading: it moves
    /// the grid the Calendar page's grid moves.
    private var header: some View {
        HStack(spacing: 3) {
            Text(focus, format: .dateTime.month(.wide).year())
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
                .layoutPriority(1)
            monthButton("chevron.left", text.previousMonth, -1)
            monthButton("chevron.right", text.nextMonth, 1)
            if !Calendar.current.isDate(focus, equalTo: now, toGranularity: .month) {
                Button(text.today) { focus = now; selectedDay = nil }
                    .buttonStyle(.borderless)
                    .font(.system(size: 9, weight: .medium))
            }
            Spacer(minLength: 0)
        }
        .frame(height: NotchDashboardLayout.calendarHeaderHeight)
    }

    private func monthButton(_ symbol: String, _ title: String, _ offset: Int) -> some View {
        Button { moveMonth(offset) } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 16, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 5, lifts: false))
        .accessibilityLabel(title)
        .help(title)
    }

    private func moveMonth(_ offset: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: offset, to: focus) else { return }
        focus = next
        // The appointments follow the month being read, so the card never shows
        // a day the grid no longer holds.
        if let selectedDay, !Calendar.current.isDate(selectedDay, equalTo: next, toGranularity: .month) {
            self.selectedDay = nil
        }
    }

    /// The chosen day's appointments, in the page's order, with the page's
    /// colours. The card has room for a few; the page has room for all of them.
    @ViewBuilder private var events: some View {
        let day = NotchCalendarSupport.events(calendar.events, on: selected)
        let next = NotchCalendarSupport.next(calendar.events, now: now)
        if calendar.loading {
            ProgressView().controlSize(.mini)
        } else if day.isEmpty {
            Text(text.emptyDay)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(day.prefix(3)) { event in
                eventRow(event, isNext: event.id == next?.id)
            }
            if day.count > 3 {
                Text("+\(day.count - 3)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func eventRow(_ event: NotchCalendarEvent, isNext: Bool) -> some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(event.color.color)
                    .frame(width: 3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(event.title.isEmpty ? text.untitled : event.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if isNext {
                            Text(text.next)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    Text(eventTime(event))
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 6, lifts: false))
        .accessibilityLabel(event.title.isEmpty ? text.untitled : event.title)
        .accessibilityValue(eventTime(event))
        .accessibilityHint(text.openCalendar)
    }

    /// The same span the page's card spells for the same appointment.
    private func eventTime(_ event: NotchCalendarEvent) -> String {
        if event.allDay { return text.allDay }
        let formatter = DateFormatter()
        formatter.locale = l10n.language.formattingLocale()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "\(formatter.string(from: event.start)) – \(formatter.string(from: event.end))"
    }

    /// The page's own way of asking: the card says what is missing and offers
    /// the setting, as the Calendar page does when it has no access to read.
    private var permission: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(permissions.calendarAccess == .denied || permissions.calendarAccess == .restricted
                     ? text.denied : text.permission)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                if permissions.calendarAccess == .denied || permissions.calendarAccess == .restricted {
                    Button(text.settings) { Permissions.shared.openCalendarSettings() }
                        .buttonStyle(.borderless).font(.system(size: 10, weight: .medium))
                } else {
                    Button(text.allow) {
                        NotchService.shared.open(.calendar)
                        Permissions.shared.requestCalendar()
                    }
                    .buttonStyle(.borderless).font(.system(size: 10, weight: .medium))
                    .disabled(permissions.requestingCalendar)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func open() {
        service.select(.calendar)
    }
}
