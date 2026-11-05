// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Foundation

/// The players the system will not name, read from the windows they draw.
///
/// macOS answers for one media session at a time, and a player that installs no
/// scripting dictionary has nothing else to be asked. What such a player always
/// has is its own window, and in that window a control that plays and pauses,
/// and the words of what it plays. The Accessibility API reads both, at that
/// process alone, and pressing the control drives that process alone: two
/// players at once stay two controls, and neither drives the other.
///
/// Only the transport and the words the window carries are read this way. A
/// player's cover, queue and lyrics belong to the system's own session, and a
/// player read through its window is offered no skipping, because its window
/// does not say what the next piece is.
struct NotchAccessibilityReading: Equatable {
    let state: NotchPlaybackSession.State
    let title: String?
    let artist: String?
    /// The window carries a control that plays and pauses, so a card may drive it.
    let canToggle: Bool
}

enum AccessibilityPlayerSupport {
    /// The words a transport control answers with, in the languages the players
    /// on this system are written in. A control named with a "pause" word means
    /// pressing it pauses, which is to say the player is playing.
    static let playingWords = ["pause", "pausar", "pausa", "暂停", "一時停止", "stop playback"]
    static let pausedWords = ["play", "reproducir", "播放", "再生"]

    /// The category a music app declares for itself. A player that declares
    /// another category is not walked through: a video editor and a music
    /// player are not the same kind of window.
    static let musicCategoryPrefix = "public.app-category.music"

    /// Windows and controls to walk per player, so a player with a large window
    /// costs a bounded read, and no player is asked every two seconds.
    static let maxWindows = 3
    static let maxDepth = 7
    static let maxElements = 220
    /// The reply time for one element, so a player that does not answer the
    /// Accessibility API is left out of the page rather than holding the read.
    static let messageTimeout: Float = 0.25

    /// A control's own words decide the state: a control that would pause the
    /// player means the player is playing, and the reverse. Words for both, in
    /// one label, leave the state unknown, and a card that does not know leaves
    /// the page: the page shows what plays, and never guesses.
    static func state(controlWords: [String]) -> NotchPlaybackSession.State {
        let words = controlWords.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let playing = words.contains { label in playingWords.contains { label.contains($0) } }
        let paused = words.contains { label in pausedWords.contains { label.contains($0) } }
        if playing && !paused { return .playing }
        if paused && !playing { return .paused }
        return .unknown
    }

    /// The words a window carries for what it plays. A player writes the song
    /// and its artist on one line, in "song - artist" order, and the two ends
    /// of that line are what a card has.
    static func credit(in texts: [String]) -> (title: String, artist: String)? {
        let splits = [" – ", " — ", " - "]
        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 4, trimmed.count <= 160 else { continue }
            guard let split = splits.first(where: { trimmed.contains($0) }) else { continue }
            let parts = trimmed.components(separatedBy: split)
            guard parts.count == 2 else { continue }
            let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 2, artist.count >= 1, !title.hasPrefix("http"), !artist.hasPrefix("http") else {
                continue
            }
            return (title, artist)
        }
        return nil
    }

    /// The reading of a window becomes a card only when the window says what it
    /// plays and offers the control to play it.
    static func reading(state: NotchPlaybackSession.State, texts: [String], toggles: Int) -> NotchAccessibilityReading {
        let credit = credit(in: texts)
        return NotchAccessibilityReading(state: state, title: credit?.title, artist: credit?.artist,
                                         canToggle: toggles > 0)
    }

    /// Which applications are worth walking. A player that installs a scripting
    /// dictionary is read by that, which answers more and costs less; the system's
    /// own session is drawn by its own card. What is left, and declares itself a
    /// music application, is asked through its window.
    static func isWindowPlayer(category: String?, scripted: Bool, isPrimary: Bool) -> Bool {
        !scripted && !isPrimary && (category ?? "").hasPrefix(musicCategoryPrefix)
    }

    /// The category an application declares, from its own bundle.
    static func category(bundleURL: URL?) -> String? {
        guard let bundleURL, let bundle = Bundle(url: bundleURL) else { return nil }
        return bundle.infoDictionary?["LSApplicationCategoryType"] as? String
    }
}

/// The read itself: one player's windows, walked once, on a queue of its own.
enum AccessibilityPlayerReader {
    /// One player's window, as far as the bounds allow.
    static func read(pid: pid_t) -> NotchAccessibilityReading? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AccessibilityPlayerSupport.messageTimeout)
        var controls: [String] = []
        var texts: [String] = []
        var elements = 0
        guard let windows = attribute(app, kAXWindowsAttribute as CFString) as? [AXUIElement] else { return nil }
        for window in windows.prefix(AccessibilityPlayerSupport.maxWindows) {
            walk(window, depth: 0, controls: &controls, texts: &texts, elements: &elements)
            if elements >= AccessibilityPlayerSupport.maxElements { break }
        }
        guard !controls.isEmpty else { return nil }
        return AccessibilityPlayerSupport.reading(state: AccessibilityPlayerSupport.state(controlWords: controls),
                                                  texts: texts, toggles: controls.count)
    }

    /// Press the player's own play/pause control, in that process.
    static func toggle(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AccessibilityPlayerSupport.messageTimeout)
        guard let windows = attribute(app, kAXWindowsAttribute as CFString) as? [AXUIElement] else { return false }
        var index = 0
        for window in windows.prefix(AccessibilityPlayerSupport.maxWindows) {
            if let control = findToggle(window, depth: 0, elements: &index),
               AXUIElementPerformAction(control, kAXPressAction as CFString) == .success {
                return true
            }
        }
        return false
    }

    private static func findToggle(_ element: AXUIElement, depth: Int, elements: inout Int) -> AXUIElement? {
        guard depth <= AccessibilityPlayerSupport.maxDepth,
              elements < AccessibilityPlayerSupport.maxElements else { return nil }
        elements += 1
        if role(element) == (kAXButtonRole as String),
           AccessibilityPlayerSupport.state(controlWords: words(of: element)) != .unknown {
            return element
        }
        for child in children(element) {
            if let found = findToggle(child, depth: depth + 1, elements: &elements) { return found }
        }
        return nil
    }

    private static func walk(_ element: AXUIElement, depth: Int, controls: inout [String],
                             texts: inout [String], elements: inout Int) {
        guard depth <= AccessibilityPlayerSupport.maxDepth,
              elements < AccessibilityPlayerSupport.maxElements else { return }
        elements += 1
        let role = role(element)
        if role == (kAXButtonRole as String) {
            controls += words(of: element)
        } else if role == (kAXStaticTextRole as String) || role == (kAXTextFieldRole as String) {
            texts += words(of: element)
        }
        for child in children(element) {
            walk(child, depth: depth + 1, controls: &controls, texts: &texts, elements: &elements)
        }
    }

    /// A control's own words: its title, its description and what its help says,
    /// which is where players that are not localised into the app's language
    /// still say what the button is.
    private static func words(of element: AXUIElement) -> [String] {
        var words: [String] = []
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute] as [String] {
            if let value = attribute(element, name as CFString) as? String, !value.isEmpty { words.append(value) }
        }
        return words
    }

    private static func role(_ element: AXUIElement) -> String {
        (attribute(element, kAXRoleAttribute as CFString) as? String) ?? ""
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement]) ?? []
    }

    private static func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }
}
