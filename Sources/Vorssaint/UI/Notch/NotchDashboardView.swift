// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The open island's one page: the month, the readings, and the running
/// things, all at once.
///
/// The island is a dashboard, not a stack of destinations. The page has a
/// fixed order - the month first, the readings under it, and every running
/// activity below them both - so a song starting adds a card to the bottom of
/// the page and takes nothing away, a timer ending leaves the month, the
/// readings and every other card where they were, and no activity can push a
/// fixed section out of its place. A tile of the grid opens its detail, which
/// is a page of its own over the dashboard — the drill-down, not a rebuild of
/// the page.
///
/// The page draws no headings: the month, the cards, the grid and the meters
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
    @ObservedObject private var sustain = NotchMetricSustain.shared
    @Environment(\.notchBand) private var band
    @AppStorage(DefaultsKey.networkSpeedUnit) private var networkSpeedUnit = NetworkSpeedUnit.bytes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The system's own session, the one with the cover, the queue and the
    /// lyrics. Its process is the id its card is known by.
    private var primaryPlayerID: Int? {
        guard NotchSupport.watchesMusicActivity(), music.playback != nil else { return nil }
        return Int(music.playback?.track.appPID ?? -1)
    }


    /// The cards of the middle section, decided apart from one another: the
    /// players first, then the timer, then a Splash session being read. The
    /// service decides the list, because the page measures itself by the same
    /// list and a card the page draws without measuring, or measures without
    /// drawing, is a page of the wrong height. The page watches the splash
    /// service as it watches the players and the timer, so a session begun on
    /// its own page appears here at once, and its readings keep arriving here
    /// while it stands.
    private var activities: [NotchDashboardActivity] {
        service.dashboardActivities
    }

    /// The page's six readings, at the page's own order, each with its figure
    /// and the line of what it has measured. The loads are read through the
    /// gate that keeps a second's spike off the page, so the cards and the menu
    /// bar agree about what is busy, and the chart is drawn from the moments the
    /// monitor kept and never from the reading of the moment repeated.
    private var readings: [NotchDashboardCardReading] {
        NotchDashboardCards.readings(dashboardSample,
                                     networkSpeedInBits: networkSpeedUnit == .bits,
                                     now: ProcessInfo.processInfo.systemUptime)
    }

    /// The monitor's snapshot, told to the cards: the moment's readings, the
    /// moments that make the charts, and the volume the disk card speaks for.
    private var dashboardSample: NotchDashboardSample {
        let snapshot = monitor.snapshot
        let volume = NotchDashboardView.primaryVolume(of: snapshot.disk)
        let activity = NotchDashboardCards.activity(of: snapshot.disk)
        return NotchDashboardSample(cpu: snapshot.cpuUsage, gpu: snapshot.gpuUsage,
                                    memory: snapshot.memoryUsed.flatMap { used in
                                        snapshot.memoryTotal.flatMap { total in
                                            total > 0 ? Double(used) / Double(total) : nil
                                        }
                                    },
                                    netDown: snapshot.netDownBytesPerSec,
                                    netUp: snapshot.netUpBytesPerSec,
                                    diskRead: activity?.read, diskWrite: activity?.write,
                                    watts: snapshot.power?.systemWatts,
                                    diskFreeBytes: volume?.freeBytes, diskTotalBytes: volume?.totalBytes,
                                    samples: snapshot.metricSamples, sustained: sustain.tones)
    }

    /// The volume the disk card names: the one the Mac starts from, and the
    /// first internal one when that volume is not in the reading - the panel's
    /// disk page's own choice, so card and page speak of one volume.
    private static func primaryVolume(of disk: DiskReading?) -> DiskDeviceReading? {
        disk?.devices.first(where: { $0.mountPath == "/" })
            ?? disk?.devices.first(where: \.isInternal)
            ?? disk?.devices.first
    }

    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
    private var activityText: NotchActivityStrings { FeatureStrings.notchActivities(l10n.language) }

    var body: some View {
        // The page's order is fixed and does not depend on what is running:
        // the month, then the readings, then every activity. A card starting or
        // ending appends and removes in the last section alone, so the month and
        // the grid never move.
        VStack(alignment: .leading, spacing: NotchDashboardLayout.sectionSpacing) {
            if service.showsDashboardCalendar {
                calendar
            }
            systemMonitoring
            if !activities.isEmpty {
                liveActivities
            }
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

    /// The running activities, one card each, in the order they were decided,
    /// appended under the month and the readings. Every card has its own
    /// background and its own boundary, so two players at once read as two
    /// controls, and the timer's card is neither of theirs.
    ///
    /// A card's coming and going is one movement: it fades and slides the short
    /// way while the section's height eases, so a song ending leaves the page
    /// without a jump. The list of cards is what the animation is keyed to, so
    /// one card leaving is one animation whatever number of readings changed on
    /// the way, and a card that stays keeps its own identity - its process, its
    /// timer, its reading - and is not rebuilt.
    private var liveActivities: some View {
        VStack(alignment: .leading, spacing: NotchDashboardLayout.cardSpacing) {
            ForEach(activities) { activity in
                activityCard(activity)
                    .transition(NotchDashboardLayout.cardTransition(reduceMotion: reduceMotion))
            }
        }
        // One movement, and the island's own. The cards and the page's height
        // are animated by the spring the window's sides are drawn with - the
        // shrinking spring when a card leaves, the growing spring when one
        // arrives - so the card going and the page taking its place are one
        // event on the screen and not a card leaving followed by a collapse.
        // With motion reduced, the card is only faded and nothing is carried.
        .animation(reduceMotion ? nil
                             : NotchDashboardLayout.cardMotion(grew: service.dashboardActivitiesGrew),
                   value: activities)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NotchDashboardSection.liveActivities.title(l10n.language))
        .accessibilityIdentifier("notch.dashboard.activities")
    }

    /// The card of one activity, chosen by the activity alone: a player's card
    /// is read from that player's own report, and never from another's.
    @ViewBuilder private func activityCard(_ activity: NotchDashboardActivity) -> some View {
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

    /// The system's player as a card: its cover, the song beside it with its
    /// position and the two times, and the transport at the card's end.
    ///
    /// The card is the way to the app that plays: a click on its cover, its
    /// words, its edges or its empty end brings that app forward. The transport
    /// and the timeline are the card's own work and keep every click they are
    /// given, because they sit in front of the card's action and not under it:
    /// a press on play is a press on play, and a drag on the bar is a seek.
    private func nowPlayingCard(_ playback: NotchPlayback) -> some View {
        NotchDashboardCard(open: { NotchDashboardSupport.openApplication(
                                    pid: Int(playback.track.appPID ?? -1),
                                    bundleIdentifier: playback.track.appBundleIdentifier ?? "") },
                           openLabel: text.open) {
            HStack(spacing: 8) {
                // The cover is the way to the app that plays, and it wears no
                // highlight of its own: the card is the region that lights.
                openAppButton(pid: Int(playback.track.appPID ?? -1),
                              bundleIdentifier: playback.track.appBundleIdentifier ?? "",
                              identifier: "notch.dashboard.nowPlaying.open",
                              label: NotchArtwork(image: music.artwork, size: NotchDashboardLayout.activityArtwork,
                                                  source: playback.track))
                VStack(alignment: .leading, spacing: 0) {
                    // The words are the way to the app as the cover is: a
                    // control, so the click that arrives with a pointer new to
                    // the island is given to it, and no highlight of its own,
                    // because the card is the thing that lights. The bar under
                    // them is not: it is the card's own work, and a drag on it
                    // is a seek.
                    openAppButton(pid: Int(playback.track.appPID ?? -1),
                                  bundleIdentifier: playback.track.appBundleIdentifier ?? "",
                                  identifier: "notch.dashboard.nowPlaying.words",
                                  label: VStack(alignment: .leading, spacing: 0) {
                        Text(playback.track.title ?? "")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                        Text(playback.track.artist ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    })
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
    /// marks that would do nothing. The card's own body is the way to the app
    /// that plays it, and its marks stay its marks.
    private func playerCard(_ source: NotchPlaybackSource) -> some View {
        let reading = music.sourcePlayback(source)
        return NotchDashboardCard(height: NotchDashboardLayout.playerCardHeight,
                                  open: { NotchDashboardSupport.openApplication(
                                    pid: Int(source.pid), bundleIdentifier: source.bundleIdentifier) },
                                  openLabel: text.open) {
            HStack(spacing: 8) {
                // The cover is the way to the app that plays it, and it wears
                // no highlight of its own.
                openAppButton(pid: Int(source.pid), bundleIdentifier: source.bundleIdentifier,
                              identifier: "notch.dashboard.player.\(Int(source.pid)).open",
                              label: NotchArtwork(image: music.sourceArtwork(source),
                                                  size: NotchDashboardLayout.activityArtwork,
                                                  source: reading?.track ?? sourceTrack(source)))
                VStack(alignment: .leading, spacing: 0) {
                    // The words are the way to the app that plays them, as the
                    // cover is, and the bar under them is the player's own
                    // position and asks nothing of the click.
                    openAppButton(pid: Int(source.pid), bundleIdentifier: source.bundleIdentifier,
                                  identifier: "notch.dashboard.player.\(Int(source.pid)).words",
                                  label: VStack(alignment: .leading, spacing: 0) {
                        Text(reading?.track.title ?? playerName(source))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                        Text(reading?.track.artist ?? playerDetail(source))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    })
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

    /// The mark of the app that plays, as the way to that app: the app comes
    /// to the front, running or not. The card's body and its controls are
    /// untouched by this, and the mark keeps its normal look under the pointer:
    /// the card is the region that lights, and the cover is not a plate.
    private func openAppButton(pid: Int, bundleIdentifier: String, identifier: String,
                               label: some View) -> some View {
        Button { NotchDashboardSupport.openApplication(pid: pid, bundleIdentifier: bundleIdentifier) } label: {
            label
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: NotchDashboardLayout.appMarkCorner,
                                      lifts: false, highlights: false))
        .accessibilityLabel(text.open)
        .accessibilityIdentifier(identifier)
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
                // the same size, the same lit plate under the pointer as the
                // marks beside it and the controls in the Explorer wear - and it
                // does not move: the card is the thing that leaves, and a way out
                // that springs away from the card it belongs to tells the person
                // the card is going twice, in two places, at two speeds.
                NotchCircularIconButton(symbol: "xmark",
                                        title: timer.session.completed ? l10n.s.supportIntroDoneButton : l10n.s.mediaCancel,
                                        side: NotchDashboardLayout.timerControlSide, filled: true, tint: .orange,
                                        lifts: false) {
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
    /// colours, and with the same four charts, memory and trend. The card
    /// lights under the pointer and a click opens the section's page, as the
    /// dashboard's other interactive cards do; its one mark stops the reading,
    /// and asks nothing of the work running in Splash. The session is not the
    /// card's owner: navigating away leaves it reading, and the card with it.
    private var splashCard: some View {
        NotchSplashDashboardCard(
            snapshot: splash.snapshot,
            phase: splash.phase,
            elapsed: splash.elapsed(),
            taskTokens: splash.taskTokens,
            isMonitoring: splash.isMonitoring,
            isSpilling: splash.isSpilling,
            history: splash.history,
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

    /// The six readings at once: two rows of three cards, each card its mark,
    /// its figures in the corner and the line of what it has measured. The grid
    /// is the page's grid and not a summary: the cards are the six the page has
    /// room for, in one order, at one size, and a card opens its reading's page.
    ///
    /// What is not here is the page's decision too. The charge and the devices
    /// on the cables are the Power page's readings, where each has room to be
    /// named; their sampling, their pages, and their menu bar indicators are
    /// untouched.
    private var systemMonitoring: some View {
        VStack(spacing: NotchDashboardLayout.metricSpacing) {
            ForEach(NotchDashboardLayout.metricRowRanges(tiles: readings.count,
                                                         columns: NotchDashboardLayout.metricColumns),
                    id: \.lowerBound) { row in
                HStack(spacing: NotchDashboardLayout.metricSpacing) {
                    ForEach(Array(readings[row])) { reading in
                        NotchSystemMetricTile(reading: reading, title: title(for: reading.metric),
                                              selected: service.selectedMetric == reading.metric.detailKind,
                                              select: { service.showMetric(reading.metric.detailKind) })
                    }
                    // An unfilled row keeps its cards at the width of the
                    // others, so the grid stays a grid.
                    ForEach(0..<max(0, NotchDashboardLayout.metricColumns - readings[row].count),
                            id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
            if readings.isEmpty {
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

    /// What a card is called, where a name costs the page no room: the screen
    /// reader's label, and the pointer's help. The card itself is drawn with no
    /// title, and says what it is by its mark.
    private func title(for metric: NotchDashboardMetric) -> String {
        let strings = l10n.s
        switch metric {
        case .cpu: return strings.cpuLabel
        case .gpu: return strings.gpuLabel
        case .memory: return strings.memorySection
        case .network: return strings.networkSection
        case .disk: return strings.diskAvailable.localizedCapitalized
        case .power: return strings.powerSection
        case .battery: return strings.batteryLabel
        case .fan: return FeatureStrings.fanControl(l10n.language).title
        case .devices: return FeatureStrings.connectedDevices(l10n.language).title
        }
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
///
/// A card given an `open` action is the way to the thing it speaks for, and not
/// only where its words are: a clear button is laid under the content, so every
/// part of the card that is not a control of its own - the cover, the title,
/// the artist, the padding, the empty end of the row - takes the card's action.
/// The controls sit in front of it and are given every click first, so the
/// transport is the transport and the timeline is the timeline, and one press
/// is never answered twice.
private struct NotchDashboardCard<Content: View>: View {
    /// The card's height, or `nil` for a card as tall as what it holds. A card
    /// with a height of its own centres its content in it; a card measured to
    /// its content keeps the edge the same on every side, which is what a card
    /// of one line of text needs.
    var height: CGFloat? = NotchDashboardLayout.activityCardHeight
    /// What a click on the card asks of the app, when the card leads somewhere.
    var open: (() -> Void)? = nil
    /// The words the card's own controls use for that action, so the card's
    /// hidden way and the mark in front of it are named the same.
    var openLabel: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let open {
                // Under the content, and answered where the content leaves the
                // click: the card's empty end, its edges, and the ground between
                // its words and its marks. It is a control and not a tap
                // gesture, because the island's panel is not the key window, and
                // a panel that is not key gives the first click of a pointer that
                // has just arrived to a control and to nothing else. The
                // transport and the timeline are in front of it, so a press on
                // play is a press on play and a drag on the bar is a seek.
                Button(action: open) { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
            }
            contentBody
        }
        .modifier(NotchControlSurface(cornerRadius: NotchDashboardLayout.cornerRadius,
                                      selected: hover, fillOpacity: NotchDashboardLayout.fillOpacity))
        .contentShape(RoundedRectangle(cornerRadius: NotchDashboardLayout.cornerRadius, style: .continuous))
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: hover)
    }

    @ViewBuilder private var contentBody: some View {
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
            // The card is the way to the page, and the way is a control: the
            // island's panel is not the key window, and a panel that is not key
            // gives the first click of a pointer that has just arrived to a
            // control. Everything in front of it keeps its own click: a day picks
            // a day, a chevron moves a month, the corner mark opens Calendar
            // itself, and an appointment opens the page at that appointment.
            Button(action: open) { Color.clear.contentShape(Rectangle()) }
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
        // Calendar itself, in the card's own corner: the mark is there whatever
        // month is read and whatever day is picked, and its click is its own -
        // it opens the app, and asks nothing of the grid behind it.
        .overlay(alignment: .topTrailing) {
            openCalendarButton
                .padding(.top, 5)
                .padding(.trailing, 6)
        }
        // Day, month and clock follow the app's language and the user's region,
        // as the Calendar page does.
        .environment(\.locale, l10n.language.formattingLocale())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NotchDashboardSection.calendar.title(l10n.language))
    }

    /// The way to Calendar, the app: the same ask the page's row makes, the
    /// same mark the page's row wears, and the same bundle behind it.
    private var openCalendarButton: some View {
        Button { NotchCalendarSupport.openApplication() } label: {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: NotchDashboardLayout.calendarOpenMarkSide,
                       height: NotchDashboardLayout.calendarOpenMarkSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 5, lifts: false))
        .accessibilityLabel(text.openCalendar)
        .accessibilityIdentifier("notch.dashboard.calendar.openApp")
        .help(text.openCalendar)
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
                    // The card's corner is the way to Calendar, and it is drawn
                    // there in every month: the day's name stands clear of it.
                    .padding(.trailing, NotchDashboardLayout.calendarOpenMarkSide + 2)
                events
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// The month's name and the way through it, as the Calendar page's own row
    /// draws them: the month centred in the pane the grid is built in, and the
    /// arrows and the way back to today at that pane's far edge. The name is
    /// centred in the calendar's half of the card and not in the whole card,
    /// because it names the grid under it, and it keeps room at both edges for
    /// the marks, so a long month's name is scaled before it is overlapped.
    ///
    /// The way back to today is the page's round mark, and no word: the card is
    /// a narrow thing, and the circle is the shape the page taught.
    private var header: some View {
        ZStack {
            HStack(spacing: 4) {
                // The month's name leads with the section's own mark, as the
                // gallery's tile wears it, at the size the page's header wears
                // a mark, so the card says what it is before it is read.
                Image(systemName: NotchModule.calendar.symbol)
                    .font(.system(size: NotchDashboardLayout.calendarMarkSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityHidden(true)
                Text(focus, format: .dateTime.month(.wide).year())
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            // Room at both edges for the marks, and the name centred between
            // them, which is the middle of the pane the grid stands in.
            .padding(.horizontal, NotchDashboardLayout.calendarHeaderTitleInset)
            .layoutPriority(1)
            HStack(spacing: 2) {
                Spacer(minLength: 0)
                monthButton("chevron.left", text.previousMonth, -1)
                monthButton("circle.circle", text.today, 0)
                monthButton("chevron.right", text.nextMonth, 1)
            }
        }
        .frame(height: NotchDashboardLayout.calendarHeaderHeight)
    }

    private func monthButton(_ symbol: String, _ title: String, _ offset: Int) -> some View {
        Button { offset == 0 ? today() : moveMonth(offset) } label: {
            Image(systemName: symbol)
                .font(.system(size: offset == 0 ? 10 : 9, weight: .semibold))
                .frame(width: 16, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 5, lifts: false))
        .accessibilityLabel(title)
        .accessibilityIdentifier(offset == 0
                                 ? "notch.dashboard.calendar.today"
                                 : "notch.dashboard.calendar.\(offset < 0 ? "previous" : "next")")
        .help(title)
    }

    /// Back to the month the day is in, and to the day itself.
    private func today() {
        focus = now
        selectedDay = nil
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
