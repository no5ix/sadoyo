// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The order the Live Activities are kept in, and the one movement of the page
/// that a card arriving or leaving is.
///
/// The rule is a queue's, and it is one rule for the three kinds of card: the
/// first activity to begin keeps its place, an activity that begins later goes
/// under the ones already there, and the row closes up when one leaves. A
/// card's kind says nothing about its place - a timer is not above a song that
/// started an hour ago - and a page measured against a different order than the
/// list it draws is a page that moves.
enum NotchActivityOrderTests {
    private static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    /// A moment of the machine's clock. The row is asked its dates, so the
    /// clock is never the one the test runs on.
    private static func at(_ seconds: TimeInterval) -> Date {
        epoch.addingTimeInterval(seconds)
    }

    private static func expect(_ suite: TestSuite, _ actual: [String], _ expected: [String], _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        suite.expect(actual == expected, "\(what): got \(actual), expected \(expected)",
                     file: file, line: line)
    }

    /// The text of a source file, read the way the repository's source tests
    /// read it.
    private static func source(_ path: String) -> String {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        url.appendPathComponent(path)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func run(_ suite: TestSuite) {
        suite.run("an activity begun later goes under the ones already there") {
            var row = NotchActivityInsertion()
            suite.expect(row.register(["timer"], at: at(0)) == 1,
                         "the first activity takes the first place")
            suite.expect(row.register(["timer", "splash", "player.7", "player.3"], at: at(5)) == 3,
                         "three activities begun at the next reading are issued three places")
            expect(suite, row.order, ["timer", "splash", "player.7", "player.3"],
                   "the page's order is the order their activities began in")
            suite.expect(row.entry(for: "timer")?.sequence == 1
                             && row.entry(for: "splash")?.sequence == 2
                             && row.entry(for: "player.3")?.sequence == 4
                             && row.entry(for: "timer")?.activatedAt == at(0)
                             && row.entry(for: "player.3")?.activatedAt == at(5),
                         "a place is an instant and a number, and not a rank of the kind of card")

            // The kinds' own order is not the page's. The Splash card begun
            // first keeps the top when a timer and a player follow it.
            var late = NotchActivityInsertion()
            _ = late.register(["splash"], at: at(0))
            _ = late.register(["splash", "timer", "player.9"], at: at(6))
            expect(suite, late.order, ["splash", "timer", "player.9"],
                   "the reading's card that began first stays first when a timer and a player follow")
            suite.expect(NotchDashboardSupport.activities(players: [9], timer: true, splash: true)
                             == [.player(id: 9), .timer, .splash],
                         "the candidates the page hands the row are the settings' order, which the row does not keep")
        }

        suite.run("the first activity keeps its place while the ones after it come and go") {
            var row = NotchActivityInsertion()
            _ = row.register(["timer", "splash", "player.7"], at: at(0))
            expect(suite, row.order, ["timer", "splash", "player.7"], "three, in the order they began")
            _ = row.register(["timer", "splash"], at: at(20))
            expect(suite, row.order, ["timer", "splash"],
                   "the bottom card leaves, the two that stay keep their places, and the row closes up")
            _ = row.register(["splash"], at: at(40))
            expect(suite, row.order, ["splash"],
                   "the first card leaves and the one behind it takes the top, leaving no gap where it stood")
            suite.expect(row.register([], at: at(60)) == 0 && row.isEmpty
                             && row.entry(for: "timer") == nil && row.entry(for: "splash") == nil,
                         "an empty row is an empty row, and a card gone keeps no place")
            // Numbers are never reused, so an activity begun after everything
            // that has been on the page is later than all of it.
            suite.expect(row.issued == 3, "three places were issued, and an empty row takes none back")
        }

        suite.run("an activity begun again is a new activity, at the bottom") {
            var row = NotchActivityInsertion()
            _ = row.register(["timer", "splash"], at: at(0))
            _ = row.register(["splash"], at: at(4))
            suite.expect(row.register(["splash", "timer"], at: at(60)) == 1,
                         "a timer begun again is registered, as any new activity is")
            expect(suite, row.order, ["splash", "timer"],
                   "the begun-again timer is at the bottom, under the card that has been running")
            suite.expect(row.entry(for: "timer")?.activatedAt == at(60)
                             && row.entry(for: "timer")?.sequence == 3,
                         "the second run is a new instance: a fresh instant and a fresh number, and not the old place")
            // A card that never left is not moved, and is not registered twice.
            suite.expect(row.register(["splash", "timer"], at: at(90)) == 0
                             && row.count == 2
                             && row.entry(for: "splash")?.sequence == 2,
                         "a card already in the row is not registered a second time, and keeps its place")
            expect(suite, row.order, ["splash", "timer"], "and the row is the two, in the order they began")
            // A whole page stopped and begun again keeps no place for anything.
            _ = row.register([], at: at(100))
            suite.expect(row.register(["timer", "splash", "player.7"], at: at(120)) == 3
                             && row.order == ["timer", "splash", "player.7"]
                             && row.entry(for: "timer")?.sequence == 4,
                         "a page begun from nothing issues fresh numbers, and nothing is carried over")
        }

        suite.run("activities begun in the same breath have one order, and it is not the settings'") {
            // The clock is only as exact as the clock: activities that become
            // active together are issued their numbers in the order they were
            // offered, and the numbers break the tie.
            var a = NotchActivityInsertion()
            _ = a.register(["player.7", "splash", "timer"], at: at(0))
            expect(suite, a.order, ["player.7", "splash", "timer"],
                   "one instant is ordered by the order the row was handed, first offered first")
            var b = NotchActivityInsertion()
            _ = b.register(["timer", "splash", "player.7"], at: at(0))
            expect(suite, b.order, ["timer", "splash", "player.7"],
                   "the same three, offered in another order, keep that order")
            suite.expect(a.order != b.order,
                         "the order is the row's history, and not a ranking of the kinds of card")
            // No kind is first by right.
            var media = NotchActivityInsertion()
            _ = media.register(["splash"], at: at(2))
            _ = media.register(["splash", "player.7"], at: at(8))
            expect(suite, media.order, ["splash", "player.7"], "a player begun after the reading's card is under it")
            var first = NotchActivityInsertion()
            _ = first.register(["player.7"], at: at(2))
            _ = first.register(["player.7", "splash"], at: at(8))
            expect(suite, first.order, ["player.7", "splash"], "and a player begun before it is over it")
        }

        suite.run("the page's list and the page's drawing are the same order") {
            var row = NotchActivityInsertion()
            _ = row.register(["player.9"], at: at(0))
            _ = row.register(["player.9", "timer"], at: at(4))
            _ = row.register(["player.9", "timer", "splash"], at: at(8))
            _ = row.register(["player.9", "timer", "splash", "player.7"], at: at(12))
            let items: [NotchDashboardActivity] = [.timer, .splash, .player(id: 7), .player(id: 9)]
            expect(suite, row.ordering(items) { $0.id }.map(\.id), ["player.9", "timer", "splash", "player.7"],
                   "the page's items are drawn in the row's order, oldest activity first")
            // A card the page has that the row has not registered is the newest
            // thing on the page, and goes last.
            expect(suite, Array(row.ordering(items + [.player(id: 5)]) { $0.id }.map(\.id).suffix(2)), ["player.7", "player.5"],
                   "a card with no record yet is the newest thing on the page")
            // A page with no row keeps the order it was handed.
            expect(suite, NotchActivityInsertion().ordering(items) { $0.id }.map(\.id),
                   ["timer", "splash", "player.7", "player.9"],
                   "a page with no row keeps the order it was handed, and invents no ranking")
            // The service's list is built the same way: ordered candidates, and
            // the page composes from that list.
            let service = source("Sources/Vorssaint/Services/Notch/NotchService.swift")
            suite.expect(service.contains("private var activityInsertion = NotchActivityInsertion()")
                             && service.contains("activityInsertion.ordering(dashboardActivityCandidates) { $0.id }"),
                         "the page's list is the candidates in the row's order, in the service")
            suite.expect(service.contains("syncActivityTimeline()")
                             && service.contains("let begun = activityInsertion.register(dashboardActivityCandidates.map(\\.id))"),
                         "the row is told of the activities where the island already learns that they began or ended")
        }

        suite.run("a card arriving grows the page, and a card leaving shrinks it") {
            // The page has to know which way the row is moving, to time its
            // height with the card's own fade: a card gained is the page
            // growing, and a card dismissed is the page shrinking.
            var row = NotchActivityInsertion()
            suite.expect(row.register(["timer"], at: at(0)) == 1, "the first card is a page that grows")
            suite.expect(row.register(["timer", "splash"], at: at(5)) == 1, "a card added is a page that grows")
            suite.expect(row.register(["timer", "splash"], at: at(10)) == 0,
                         "the same cards at the next reading move nothing")
            suite.expect(row.register(["timer"], at: at(15)) == 0,
                         "a card dismissed is a page that shrinks: nothing new began, and the row's timing is the other one")
            suite.expect(row.register(["timer", "player.3"], at: at(60)) == 1 && row.order == ["timer", "player.3"],
                         "a player begun again joins at the bottom, and the row grew for it")
            suite.expect(row.register(["timer", "player.3"], at: at(120)) == 0
                             && row.entry(for: "timer")?.activatedAt == at(0),
                         "a card that has been running since the first reading is not moved, and its state is its own")
        }

        suite.run("a dismissed card takes exactly its own height and gap") {
            // The row's measure of a card is the card's own measure, so the
            // height given back when a card leaves is the height that card drew
            // and its gap, and nothing of the cards that stay.
            let three: [NotchDashboardActivity] = [.timer, .splash, .player(id: 7)]
            let two: [NotchDashboardActivity] = [.timer, .splash]
            suite.expect(NotchDashboardLayout.liveActivitiesHeight(three)
                             - NotchDashboardLayout.liveActivitiesHeight(two)
                             == NotchDashboardLayout.activityHeight(.player(id: 7))
                                + NotchDashboardLayout.cardSpacing,
                         "the row gives back the dismissed card and its gap, and nothing of the cards that stay")
            suite.expect(NotchDashboardLayout.liveActivitiesHeight([]) == 0, "an empty row is no height")
            suite.expect(NotchDashboardLayout.liveActivitiesHeight([.player(id: 7), .player(id: 9)])
                             == NotchDashboardLayout.activityHeight(.player(id: 7))
                                + NotchDashboardLayout.activityHeight(.player(id: 9))
                                + NotchDashboardLayout.cardSpacing,
                         "two players are their heights and one gap, and a dismissed one takes one gap with it")
            suite.expect(NotchDashboardLayout.cardSpacing > 0,
                         "the cards are separated, which is the gap a dismissal closes in the same movement")
            suite.expect(NotchDashboardLayout.timerCardHeight
                             == NotchDashboardLayout.activityCardPadding * 2 + NotchDashboardLayout.timerControlSide,
                         "the timer's card is measured to the control it draws, and not to a taller box around it")
            suite.expect(NotchDashboardLayout.activityHeight(.splash) == NotchSplashLayout.cardHeight(compact: true),
                         "the row measures the reading's card as the card measures itself, at the card the row draws")
        }

        suite.run("the row's motion is one movement, and its rules in the source are its rules") {
            // The Growing and shrinking of the island's height are the island's
            // two springs, and the row that gains a card and the row that loses
            // one are timed apart: a card leaving is carried out first, and the
            // height closes after it, which is one movement and not two.
            suite.expect(NotchMotion.growingHeight.duration > NotchMotion.shrinkingHeight.duration,
                         "a row that grows takes its time, and a row that shrinks gets its card out first: "
                         + "\(NotchMotion.growingHeight.duration)s against \(NotchMotion.shrinkingHeight.duration)s")
            let layout = source("Sources/Vorssaint/Services/Notch/NotchDashboardSupport.swift")
            suite.expect(layout.contains("static func cardMotion(grew: Bool) -> Animation")
                             && layout.contains("NotchMotion.growingHeight.duration, bounce: 0")
                             && layout.contains("NotchMotion.shrinkingHeight.duration, bounce: 0"),
                         "the row's height is the island's two springs, and neither is given a bounce")
            // The page animates its height by that one word, and every card by
            // the one transition, on its identity. A card that fades while the
            // height is animated by something else is the jump this is against.
            let view = source("Sources/Vorssaint/UI/Notch/NotchDashboardView.swift")
            suite.expect(view.contains("ForEach(activities)"), "the row's cards are drawn by their identities")
            suite.expect(view.contains("transition(NotchDashboardLayout.cardTransition(reduceMotion: reduceMotion))"),
                         "every card of the row leaves by the row's one transition, the timer's and the reading's and the player's alike")
            suite.expect(view.contains("cardMotion(grew: service.dashboardActivitiesGrew)"),
                         "the page's height is timed by the row's word for which way it is moving")
            suite.expect(layout.contains("reduceMotion ? .opacity"),
                         "with motion reduced a card only fades, and the row's height is the only movement left")
            // The mark in the corner of a card that is closing does not jump:
            // it takes no lift, so the card is the thing that moves.
            suite.expect(view.contains("lifts: false"),
                         "a card's marks are drawn without the lift, so a closing card is one thing going")
        }
    }
}
