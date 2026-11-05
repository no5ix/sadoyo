// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The rules the dashboard's player cards are built from: what a player's own
/// words mean, how long a card may keep a reading, which cards the page draws
/// and in which order, and what a card is allowed to send.
///
/// A card stands for one process, so these tests are the promise that two
/// players playing at once are two cards, that each card's buttons belong to
/// its own process, and that a player that stopped answering leaves the page.
enum PlaybackSessionsTests {
    static func run(_ suite: TestSuite) {
        suite.run("a player's own word for its state is read as it is said") {
            expect(suite, PlaybackSessionsSupport.state(for: "playing"), .playing, "playing means playing")
            expect(suite, PlaybackSessionsSupport.state(for: "  PLAYING \n"), .playing, "case and space are noise")
            expect(suite, PlaybackSessionsSupport.state(for: "paused"), .paused, "paused means paused")
            expect(suite, PlaybackSessionsSupport.state(for: "stopped"), .stopped, "stopped means stopped")
            expect(suite, PlaybackSessionsSupport.state(for: "reproducing music, playing"), .playing,
                   "a sentence around the word still says the player plays")
            for word in [nil, "", "   ", "waiting", "buffering", "idle"] {
                expect(suite, PlaybackSessionsSupport.state(for: word), .unknown,
                       "\(String(describing: word)) says nothing about playing")
            }
        }

        suite.run("a player's numbers are read the two ways players give them") {
            func seconds(_ text: String?) -> String {
                guard let value = PlaybackSessionsSupport.seconds(from: text) else { return "nil" }
                return String(format: "%.0f", value)
            }
            suite.expect(seconds("241") == "241", "a plain number is seconds")
            suite.expect(seconds("241.5") == "242" || seconds("241.5") == "241", "a fraction is accepted")
            suite.expect(seconds("4:01") == "241", "a clock of minutes and seconds")
            suite.expect(seconds("1:02:03") == "3723", "a clock with hours")
            for bad in [nil, "", "  ", "seven", "3:ab", "-20", "1:2:3:4"] {
                suite.expect(PlaybackSessionsSupport.seconds(from: bad) == nil,
                             "\(String(describing: bad)) is not a length")
            }
            suite.expect(PlaybackSessionsSupport.clock(0) == "0:00"
                             && PlaybackSessionsSupport.clock(75) == "1:15"
                             && PlaybackSessionsSupport.clock(3725) == "1:02:05",
                         "a position is written the way the players write it")
            suite.expect(PlaybackSessionsSupport.clock(-1) == "0:00"
                             && PlaybackSessionsSupport.clock(.nan) == "0:00",
                         "a number out of range is shown as nothing, not as a negative song")
        }

        suite.run("a card is shown for a player that is playing and answering") {
            let now = Date(timeIntervalSince1970: 2_000)
            func card(_ pid: Int32, _ name: String, playing: Bool = true, at updated: Date = now) -> NotchPlaybackSession {
                var session = NotchPlaybackSession(pid: pid, bundleIdentifier: "\(name).player", appName: name)
                session.state = playing ? .playing : .paused
                session.updated = updated
                return session
            }
            let fresh = card(7, "A")
            let paused = card(9, "B", playing: false)
            let quiet = card(11, "C", at: now.addingTimeInterval(-PlaybackSessionsSupport.staleAfter - 1))
            let alsoPlaying = card(13, "D")

            suite.expect(!PlaybackSessionsSupport.isStale(updated: fresh.updated, now: now),
                         "a reading taken now is fresh")
            suite.expect(PlaybackSessionsSupport.isStale(updated: now.addingTimeInterval(-60), now: now),
                         "a player that stopped answering loses its card, so no stale song stays on the page")
            // Every player playing gets a card: nothing caps them at one, the
            // system's own player leads, and no player is listed twice.
            expect(suite, PlaybackSessionsSupport.cardPlayerIDs(primary: nil, sessions: [fresh, alsoPlaying], now: now),
                   [7, 13], "two players playing are two cards")
            expect(suite, PlaybackSessionsSupport.cardPlayerIDs(primary: 3, sessions: [fresh, alsoPlaying], now: now),
                   [3, 7, 13], "the system's player leads, and the others follow")
            expect(suite, PlaybackSessionsSupport.cardPlayerIDs(primary: 7, sessions: [fresh, alsoPlaying], now: now),
                   [7, 13], "a player that owns the system's session is not listed twice")
            expect(suite, PlaybackSessionsSupport.cardPlayerIDs(primary: nil, sessions: [paused], now: now), [],
                   "a paused player keeps no card")
            expect(suite, PlaybackSessionsSupport.cardPlayerIDs(primary: nil, sessions: [quiet], now: now), [],
                   "a player that stopped answering keeps no card")
            expect(suite, PlaybackSessionsSupport.cardPlayerIDs(primary: nil,
                                                               sessions: [fresh, alsoPlaying, paused, quiet],
                                                               now: now), [7, 13],
                   "the page keeps every player that is playing, in the order they were found")
            suite.expect(PlaybackSessionsSupport.pollInterval >= 1 && PlaybackSessionsSupport.pollInterval <= 5
                             && PlaybackSessionsSupport.maxPlayers >= 3,
                         "the asking is steady, not a busy loop, and the page can show more than one player")
        }

        suite.run("a card's own reading and its own buttons") {
            var session = NotchPlaybackSession(pid: 7, bundleIdentifier: "a.player", appName: "A Player")
            suite.expect(session.fraction == nil && session.elapsedText == nil && session.remainingText == nil,
                         "nothing read means nothing drawn as a position")
            session.elapsed = 60
            session.duration = 240
            suite.expect(session.fraction == 0.25, "the position is the song's own fraction")
            suite.expect(session.elapsedText == "1:00" && session.remainingText == "3:00",
                         "the two times beside the bar are the player's own")
            session.elapsed = 300
            suite.expect(session.fraction == nil,
                         "a position past a song that has not been re-read is not a position")
            session.elapsed = 60
            session.duration = 0
            suite.expect(session.fraction == nil, "a song of no length has no fraction")

            // The card's buttons belong to the process the card is about, and
            // only to what that player declared and agreed to receive.
            var driving = NotchPlaybackSession(pid: 8, bundleIdentifier: "b.player", appName: "B Player")
            driving.access = .granted
            driving.canSkipNext = true
            suite.expect(driving.canSend(.toggle), "a player that has agreed can be played and paused")
            suite.expect(driving.canSend(.next) && !driving.canSend(.previous),
                         "a player that declares only one skip gets one button")
            for access in [NotchMusicAutomation.Access.consent, .denied, .unavailable] {
                var silent = driving
                silent.access = access
                suite.expect(!silent.canSend(.toggle) && !silent.canSend(.next) && !silent.canSend(.previous),
                             "a player that has not agreed gets no buttons, so no click drives it")
            }
            suite.expect(!NotchPlaybackSession(pid: 9, bundleIdentifier: "c.player", appName: "C Player")
                .canSend(.seek(10)), "a card's row does not drive what it cannot show")
        }

        suite.run("the words a card reads are the player's own") {
            let naming = ["name", "artist"]
            suite.expect(PlaybackSessionsSupport.firstProperty(naming, in: ["artist": 2, "name": 1]) == 1,
                         "the first word the page asks for wins, as players name their song")
            suite.expect(PlaybackSessionsSupport.firstProperty(["track name", "name"],
                                                               in: ["artist": 2, "name": 1]) == 1,
                         "a player that names its song 'name' is read by the same rule")
            suite.expect(PlaybackSessionsSupport.firstProperty(naming, in: ["duration": 3]) == nil,
                         "a player that declares neither word has no song to show")
            suite.expect(PlaybackSessionsSupport.stateNames.contains("player state")
                             && PlaybackSessionsSupport.durationNames.contains("duration")
                             && PlaybackSessionsSupport.positionNames.contains("player position"),
                         "the words are the Standard Suites' own, not invented names")
        }
    }

    private static func expect(_ suite: TestSuite, _ actual: NotchPlaybackSession.State,
                               _ expected: NotchPlaybackSession.State, _ message: String) {
        suite.expect(actual == expected, "\(message): got \(actual)")
    }

    private static func expect(_ suite: TestSuite, _ actual: [Int], _ expected: [Int], _ message: String) {
        suite.expect(actual == expected, "\(message): got \(actual)")
    }
}
