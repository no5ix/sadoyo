// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// One player's session as the dashboard's card shows it: the process it
/// belongs to, what that process plays, and how far the card may drive it.
///
/// A session is always one process. The system's own Now Playing session has
/// its card through the player's page; the sessions here are the other players,
/// read from the scripting dictionary each installs for itself.
struct NotchPlaybackSession: Identifiable, Equatable {
    enum State: Equatable {
        case playing, paused, stopped, unknown
    }

    /// How the player is read and driven. A player that installs a scripting
    /// dictionary answers its state, its song and its transport to events sent
    /// at its process; a player that installs none is read from, and driven by,
    /// the transport control in the window it draws.
    enum Source: Equatable {
        case scripting, window
    }

    let pid: Int32
    let bundleIdentifier: String
    let appName: String
    var state: State = .unknown
    var title: String?
    var artist: String?
    var elapsed: TimeInterval?
    var duration: TimeInterval?
    /// Whether this process may be sent its own play, previous and next events.
    var access: NotchMusicAutomation.Access = .unavailable
    /// Which of the two ways this session is read, so the card drives it the way
    /// that player answers to, and offers only the controls that player has.
    var source: Source = .scripting
    /// What the player's dictionary declares. A player that does not declare
    /// skipping gets no skip button, rather than a button that does nothing.
    var canSkipPrevious = false
    var canSkipNext = false
    /// When the reading was taken, so a player that stopped answering loses its
    /// card instead of keeping a song on the page forever.
    var updated = Date.distantPast

    var id: Int32 { pid }
    var app: NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }
    var icon: NSImage? { app?.icon }
    var isPlaying: Bool { state == .playing }

    /// The player is known - its process runs and it is a player that the page
    /// can drive - and its state is not readable, because macOS has not granted
    /// the automation of the app, or the reading of its window. A card is kept
    /// for such a player: it names the app, says that the reading is blocked,
    /// and carries the way to grant it. The state is never guessed at, so a
    /// player whose state is unknown is not shown as playing.
    var needsPermission: Bool { state == .unknown && access != .granted }

    /// The song's position, only when the player answered with both ends of it.
    var fraction: Double? {
        guard let elapsed, let duration, duration > 0, elapsed >= 0, elapsed <= duration * 1.05 else { return nil }
        return elapsed / duration
    }

    var elapsedText: String? { elapsed.map(PlaybackSessionsSupport.clock) }
    var remainingText: String? {
        guard let elapsed, let duration else { return nil }
        return PlaybackSessionsSupport.clock(max(0, duration - elapsed))
    }

    /// A button is offered only for a command this player declares and this
    /// process has agreed to receive.
    func canSend(_ command: NotchPlaybackCommand) -> Bool {
        guard access == .granted else { return false }
        switch command {
        case .toggle: return true
        case .next: return canSkipNext
        case .previous: return canSkipPrevious
        default: return false
        }
    }
}

/// The rules the player cards are built from, apart from the reading of them:
/// which words in a player's dictionary mean what a card shows, how a state
/// reads, when a card has outlived its answer, and which cards the page draws.
enum PlaybackSessionsSupport {
    /// The Standard Suites call the transport state "player state" and the song
    /// "name" and "artist"; players that name their properties "track name" are
    /// read by the same rule.
    static let stateNames = ["player state"]
    static let titleNames = ["name", "track name", "title"]
    static let artistNames = ["artist", "track artist"]
    static let positionNames = ["player position"]
    static let durationNames = ["duration", "track duration"]

    /// A player that has not answered for this long has lost its card, and the
    /// page stops asking it. A song is longer than this by far, so a card only
    /// goes when the player really stopped answering.
    static let staleAfter: TimeInterval = 8
    /// How often the running players are asked, while the island is showing.
    static let pollInterval: TimeInterval = 2
    /// Players read in one pass, so a page of cards never waits on a queue of
    /// applications that are not playing anything.
    static let maxPlayers = 4

    /// Players that stopped answering are dropped.
    static func isStale(updated: Date, now: Date) -> Bool {
        now.timeIntervalSince(updated) > staleAfter
    }

    /// The player's own word for its state, matched loosely: dictionaries answer
    /// "playing", "paused", "stopped", and some answer with a sentence around it.
    static func state(for text: String?) -> NotchPlaybackSession.State {
        guard let word = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !word.isEmpty else {
            return .unknown
        }
        if word.contains("playing") || word == "play" { return .playing }
        if word.contains("pause") || word.contains("stop") { return word.contains("pause") ? .paused : .stopped }
        return .unknown
    }

    /// Seconds, from the two ways players answer a length: a number of seconds
    /// and a clock "4:01" (or "1:02:03").
    static func seconds(from text: String?) -> TimeInterval? {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let value = Double(raw.replacingOccurrences(of: ",", with: ".")), value.isFinite, value >= 0 {
            return value
        }
        let parts = raw.split(separator: ":").compactMap { Double($0) }
        guard parts.count >= 2, parts.count <= 3, parts.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// A song's position as the player's cards write it: "2:13", "1:02:03".
    static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, secondsIn = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secondsIn)
            : String(format: "%d:%02d", minutes, secondsIn)
    }

    /// The cards the Live Activities section draws: the system's own player
    /// first, when it has one, then every other player that says it is playing
    /// or that the page cannot read without a permission, in the order they
    /// were found. Nothing is capped at one: three players playing at once are
    /// three cards, and a player that is waiting for permission is a card of
    /// its own, because a card that is not drawn cannot be asked for it.
    /// A player that says it is paused, stopped, and answers, has no card.
    static func cardPlayerIDs(primary: Int?, sessions: [NotchPlaybackSession], now: Date = Date()) -> [Int] {
        var ids: [Int] = []
        if let primary { ids.append(primary) }
        ids += sessions.filter { ($0.isPlaying || $0.needsPermission) && !isStale(updated: $0.updated, now: now) }
            .map { Int($0.pid) }
            .filter { $0 != primary }
        return ids
    }

    /// The buttons a card offers for this player: the scripted player declares
    /// its skips and answers them; a player read through its window has the one
    /// control its window carries, and a card does not offer a button that
    /// player has no way to answer.
    static func cardCommands(for session: NotchPlaybackSession) -> [NotchPlaybackCommand] {
        session.source == .window ? [.toggle] : [.previous, .toggle, .next]
    }

    /// The first name a player's dictionary declares among `names`.
    static func firstProperty(_ names: [String], in properties: [String: UInt32]) -> UInt32? {
        names.compactMap { properties[$0] }.first
    }
}
