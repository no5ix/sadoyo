// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// The players other than the system's own, as the dashboard's cards need them.
///
/// MediaRemote answers for one session — the application the system names as
/// playing — and macOS 26 offers no way to list the players behind it. Every
/// player that installs a scripting dictionary, though, answers for itself:
/// its state, its song and its transport, addressed at its own process. This
/// service asks those applications, so the page can show Spotify and Music at
/// once, each card driving the process it belongs to.
///
/// It asks only while the island is showing, only the applications that
/// declare the playback vocabulary, and only a few at a time. Consent belongs
/// to each pair of applications, as the system requires: a player that has not
/// agreed is asked once, from its card, and never behind the person's back.
final class PlaybackSessionsService: ObservableObject {
    static let shared = PlaybackSessionsService()

    /// The buttons a player's card offers, in the order the transport draws
    /// them.
    static let cardCommands: [NotchPlaybackCommand] = [.previous, .toggle, .next]

    @Published private(set) var sessions: [NotchPlaybackSession] = []
    /// A consent request is in flight, so its card shows that and asks once.
    @Published private(set) var requesting = false

    /// One application being watched, with what its dictionary declared.
    private struct Player {
        let pid: Int32
        let bundleIdentifier: String
        let name: String
        let capabilities: NotchMusicAutomationCapabilities
        let state: UInt32
        let title: UInt32?
        let artist: UInt32?
        let position: UInt32?
        let duration: UInt32?
    }

    private var players: [Player] = []
    /// Dictionaries read from disk, so an application is asked once per launch.
    private var dictionaries: [String: NotchMusicAutomationCapabilities?] = [:]
    /// Applications whose consent was declined: they are not asked again, and
    /// their cards say so once.
    private var declined: Set<String> = []
    private var work: DispatchWorkItem?
    /// Applications that stopped answering are forgotten after this many passes.
    private var generation = 0
    private let queue = DispatchQueue(label: "vorssaint.playback-sessions", qos: .utility)

    private init() {}

    /// The cards the page draws, in order: the system's own player first, then
    /// the other players that say they are playing.
    static func cardPlayerIDs(primary: Int?, sessions: [NotchPlaybackSession]) -> [Int] {
        PlaybackSessionsSupport.cardPlayerIDs(primary: primary, sessions: sessions)
    }

    func session(id: Int32) -> NotchPlaybackSession? {
        sessions.first { $0.pid == id }
    }

    // MARK: - Watching

    /// The island asks for the players while it is open and shows the page; a
    /// closed island stops the asking at once.
    func setWatching(_ watching: Bool) {
        work?.cancel()
        work = nil
        guard watching else {
            if !sessions.isEmpty { sessions = [] }
            players = []
            return
        }
        let loop = DispatchWorkItem { [weak self] in self?.poll() }
        work = loop
        queue.async(execute: loop)
    }

    // MARK: - Reading

    /// Reads the running players on the background queue and publishes what
    /// they answer. Publishing happens on the main actor, so a card never sees
    /// half a reading.
    private func poll() {
        generation &+= 1
        let now = Date()
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let candidates = runningPlayers(in: frontmost)
        DispatchQueue.main.async { [weak self] in self?.players = candidates }
        var readings: [NotchPlaybackSession] = []
        for player in candidates {
            readings.append(reading(for: player))
        }
        let staleDropped = readings.filter { !PlaybackSessionsSupport.isStale(updated: $0.updated, now: now) }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.work != nil else { return }
            if self.sessions != staleDropped { self.sessions = staleDropped }
        }
        let next = DispatchWorkItem { [weak self] in self?.poll() }
        work = next
        queue.asyncAfter(deadline: .now() + PlaybackSessionsSupport.pollInterval, execute: next)
    }

    /// The applications that declare a player, as few as the page can show at
    /// once. The application in front is kept even when it has not agreed to
    /// be read, because its card is the way to ask.
    private func runningPlayers(in frontmost: String?) -> [Player] {
        let own = ProcessInfo.processInfo.processIdentifier
        var found: [Player] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard pid != own, !app.isTerminated, let bundleID = app.bundleIdentifier,
                  let url = app.bundleURL else { continue }
            if pid == NotchMusicService.shared.playback?.track.appPID { continue }
            let capabilities = dictionary(for: bundleID, url: url)
            guard let capabilities,
                  let state = PlaybackSessionsSupport.firstProperty(PlaybackSessionsSupport.stateNames,
                                                                    in: capabilities.properties),
                  capabilities.canToggle else { continue }
            let player = Player(
                pid: pid, bundleIdentifier: bundleID, name: app.localizedName ?? bundleID,
                capabilities: capabilities, state: state,
                title: PlaybackSessionsSupport.firstProperty(PlaybackSessionsSupport.titleNames,
                                                             in: capabilities.properties),
                artist: PlaybackSessionsSupport.firstProperty(PlaybackSessionsSupport.artistNames,
                                                              in: capabilities.properties),
                position: PlaybackSessionsSupport.firstProperty(PlaybackSessionsSupport.positionNames,
                                                                in: capabilities.properties),
                duration: PlaybackSessionsSupport.firstProperty(PlaybackSessionsSupport.durationNames,
                                                                in: capabilities.properties))
            // The frontmost player leads the list, so the card the person is
            // most likely to use is the first one the page asks about.
            if bundleID == frontmost {
                found.insert(player, at: 0)
            } else if found.count < PlaybackSessionsSupport.maxPlayers {
                found.append(player)
            }
        }
        return Array(found.prefix(PlaybackSessionsSupport.maxPlayers))
    }

    /// The player's installed dictionary, once per application per run.
    private func dictionary(for bundleID: String, url: URL) -> NotchMusicAutomationCapabilities? {
        if let cached = dictionaries[bundleID] { return cached }
        let capabilities = NotchMusicAutomationCapabilities.load(bundleURL: url)
        dictionaries[bundleID] = capabilities
        return capabilities
    }

    /// One application's reading. Consent is asked without a prompt here; the
    /// card asks, when the person presses its button.
    private func reading(for player: Player) -> NotchPlaybackSession {
        var session = NotchPlaybackSession(pid: player.pid, bundleIdentifier: player.bundleIdentifier,
                                           appName: player.name, updated: Date())
        guard NSRunningApplication(processIdentifier: player.pid) != nil else {
            session.state = .unknown
            return session
        }
        let access = NotchMusicAutomation.access(pid: player.pid, bundleIdentifier: player.bundleIdentifier)
        session.access = access
        switch access {
        case .granted:
            guard let state = NotchMusicAutomation.textProperty(player.state, pid: player.pid) else {
                session.state = .unknown
                return session
            }
            session.state = PlaybackSessionsSupport.state(for: state)
            session.canSkipPrevious = player.capabilities.commands["previous track"] != nil
            session.canSkipNext = player.capabilities.commands["next track"] != nil
            // A player that is not playing has no card, so its song is not
            // asked for; the next pass asks about the state again.
            guard session.isPlaying else { return session }
            if let title = player.title { session.title = NotchMusicAutomation.textProperty(title, pid: player.pid) }
            if let artist = player.artist { session.artist = NotchMusicAutomation.textProperty(artist, pid: player.pid) }
            if let position = player.position {
                session.elapsed = NotchMusicAutomation.numberProperty(position, pid: player.pid)
            }
            if let duration = player.duration {
                session.duration = NotchMusicAutomation.numberProperty(duration, pid: player.pid)
            }
        case .consent, .denied, .unavailable:
            session.state = .unknown
        }
        return session
    }

    // MARK: - Driving one player

    /// Asks the system for permission to control that player, in the words the
    /// player's own page uses. The system remembers the answer.
    func requestConsent(_ session: NotchPlaybackSession) {
        guard !requesting else { return }
        requesting = true
        let bundleID = session.bundleIdentifier
        let pid = session.pid
        queue.async { [weak self] in
            _ = AppleScriptRunner.consentToAutomate(bundleID: bundleID)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.requesting = false
                self.declined.remove(bundleID)
                self.dictionaries.removeValue(forKey: bundleID)
                if let current = self.session(id: pid), current.access == .denied {
                    self.declined.insert(bundleID)
                }
            }
        }
    }

    /// Sends one command to the process the card belongs to. Nothing is retried:
    /// a player that answers late has had the event, and sending it twice would
    /// take the song back.
    func send(_ command: NotchPlaybackCommand, to session: NotchPlaybackSession) {
        guard session.access == .granted, session.canSend(command),
              let player = players.first(where: { $0.pid == session.pid }),
              NSRunningApplication(processIdentifier: session.pid) != nil else { return }
        // The state the card shows is what the transport's play/pause toggles.
        let isPlaying = session.isPlaying
        queue.async {
            _ = NotchMusicAutomation.sendToPlayer(command, isPlaying: isPlaying,
                                                 capabilities: player.capabilities, pid: player.pid)
        }
    }
}
