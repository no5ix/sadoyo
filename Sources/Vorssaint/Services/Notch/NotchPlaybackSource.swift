// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchPlaybackSource: Equatable {
    struct Selection: Equatable {
        let pid: Int32
        let bundleIdentifier: String

        var isValid: Bool { pid > 0 && NotchPlaybackCommand.validIdentifier(bundleIdentifier) }
    }

    let pid: Int32
    let bundleIdentifier: String
    let isMusicApp: Bool
    /// The player's own state, which a second read of the player can correct.
    var isPlaying: Bool
    let hasTrack: Bool

    /// Whether this player has media being heard: it says it is playing, and
    /// it has a recording to play. A session left paused, stopped, or holding
    /// a recording with nothing running is not media being heard, and the
    /// island draws no card for it; a player that says it is playing with
    /// nothing to play has nothing to draw either.
    var displayName: String? = nil
    /// What the player reports of its own recording, read from that player's
    /// path: its card draws these, never the words of the player in effect.
    var title: String? = nil
    var artist: String? = nil
    var elapsed: Double? = nil
    var duration: Double? = nil
    /// The recording this cover belongs to, and the cover itself. The adapter
    /// reads a cover once per recording, so a watched stream does not carry the
    /// same bytes on every change; a card falls back to the app's icon where no
    /// cover is reported.
    var itemIdentifier: String? = nil
    var artworkData: Data? = nil

    /// The largest cover one source carries in one reply. Covers of several
    /// players travel in the same line as the readings, so each is kept to a
    /// size a watched stream can repeat.
    static let maximumArtworkBytes = 1_024 * 1_024

    var isActivelyPlaying: Bool { isPlaying && hasTrack }

    var selection: Selection { Selection(pid: pid, bundleIdentifier: bundleIdentifier) }

    static func isMusicApplication(bundleIdentifier: String?, parentBundleIdentifier: String?, category: String?) -> Bool {
        let knownMusicApps: Set<String> = ["com.apple.Music", "com.apple.iTunes", "com.spotify.client"]
        return category == "public.app-category.music"
            || [bundleIdentifier, parentBundleIdentifier].compactMap { $0 }.contains(where: knownMusicApps.contains)
    }

    var reply: [String: Any] {
        var value: [String: Any] = ["pid": pid, "bundleIdentifier": bundleIdentifier, "isMusicApp": isMusicApp,
                                   "isPlaying": isPlaying, "hasTrack": hasTrack]
        value["displayName"] = displayName
        value["title"] = title
        value["artist"] = artist
        value["elapsed"] = elapsed
        value["duration"] = duration
        value["itemIdentifier"] = itemIdentifier
        // The primary reading's cover travels the same way, as base64.
        if let artworkData, artworkData.count <= Self.maximumArtworkBytes {
            value["artworkBase64"] = artworkData.base64EncodedString()
        }
        return value
    }

    /// A process identifier from the adapter: a positive whole number, never a Boolean.
    static func decodePID(_ value: Any?) -> Int32? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let pid = Int32(exactly: number.doubleValue), pid > 0 else { return nil }
        return pid
    }

    /// Only the chosen source is listed without a track: it stays chosen for
    /// a moment while it waits for its next one.
    static func decode(_ value: Any?, selectedPID: Int32? = nil) -> [Self] {
        guard let entries = value as? [[String: Any]], entries.count <= 16 else { return [] }
        var sources: [Self] = []
        for entry in entries {
            guard let pid = decodePID(entry["pid"]),
                  let bundle = entry["bundleIdentifier"] as? String, NotchPlaybackCommand.validIdentifier(bundle),
                  let music = entry["isMusicApp"] as? Bool, let playing = entry["isPlaying"] as? Bool,
                  let track = entry["hasTrack"] as? Bool, track || pid == selectedPID,
                  !sources.contains(where: { $0.pid == pid }) else { continue }
            let name = (entry["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let artwork = (entry["artworkBase64"] as? String).flatMap { Data(base64Encoded: $0) }
            sources.append(Self(pid: pid, bundleIdentifier: bundle, isMusicApp: music, isPlaying: playing, hasTrack: track,
                                displayName: name.flatMap { Self.validText($0) },
                                title: Self.text(entry["title"]),
                                artist: Self.text(entry["artist"]),
                                elapsed: Self.position(entry["elapsed"]),
                                duration: Self.position(entry["duration"]),
                                itemIdentifier: (entry["itemIdentifier"] as? String)
                                    .flatMap { NotchPlaybackCommand.validIdentifier($0) ? $0 : nil },
                                artworkData: artwork.flatMap { $0.count <= Self.maximumArtworkBytes ? $0 : nil }))
        }
        return sources.sorted { $0.pid < $1.pid }
    }

    /// One text of a source, bounded as the names are: a player that reports a
    /// megabyte of lyrics in its title field is not shown.
    static func text(_ value: Any?) -> String? {
        guard let value = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return validText(value)
    }

    static func validText(_ value: String) -> String? {
        !value.isEmpty && value.utf8.count <= 256 ? value : nil
    }

    /// A position a player reports, in seconds. A player that has not read its
    /// own position reports nothing, which the card shows as no timeline.
    static func position(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 604_800
        else { return nil }
        return number.doubleValue
    }

    /// Automatic playback follows music apps and, unless the user turns them
    /// off, other players too. A manual source choice always takes precedence.
    /// Paused music keeps its resume control when nothing eligible is playing,
    /// except that a followed player that is not a music app keeps its place
    /// while paused.
    static func preferred(in sources: [Self], previousPID: Int32?, systemPID: Int32?, selection: Selection? = nil,
                          includeOtherPlayers: Bool = false) -> Self? {
        let available = sources.filter { $0.pid > 0 && $0.hasTrack }
        // An explicit choice remains controllable while paused, even if another
        // source is playing. Without a track, the automatic order fills in.
        if let selection, let chosen = available.first(where: { $0.selection == selection }) { return chosen }
        let music = available.filter(\.isMusicApp)
        // Registered clients can be playing while macOS still remembers a
        // paused music app as its system player. Other players follow their
        // live playback too; ownership only breaks a tie between eligible clients.
        let other = includeOtherPlayers ? available.filter { !$0.isMusicApp } : []
        // The followed player keeps its place while paused, so pausing a
        // video never switches playback to music paused earlier.
        for candidates in [music.filter(\.isPlaying), other.filter(\.isPlaying),
                           other.filter { $0.pid == previousPID }, music] {
            if let previous = candidates.first(where: { $0.pid == previousPID }) { return previous }
            if let current = candidates.first(where: { $0.pid == systemPID }) { return current }
            if let first = candidates.sorted(by: { $0.pid < $1.pid }).first { return first }
        }
        return includeOtherPlayers ? available.first { $0.pid == systemPID } : nil
    }
}
