// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// MARK: - What the feature knows, and what it decides
//
// The whole of the per-application input source feature is a small machine over
// three facts: which application the window server says is frontmost, which
// input source the text-input server says is typing, and which source each
// application was last seen typing with. The hard part is not the storage, it is
// that a change notification from the text-input server says *that* the source
// changed and never *who asked for it* — so the machine keeps its own request in
// flight and judges each notification against it.
//
// Everything below is pure: no AppKit, no Carbon, no clocks of its own. Times
// come in as `systemUptime` seconds from the caller, the applications arrive as
// their identity strings, and the sources as their stable TIS identifiers. The
// service beside this file owns the observers and the selection, and does
// exactly what this machine tells it to do.

/// The rule the feature runs by, in one place.
enum InputSourceMemorySupport {
    /// How long a restoration may stay in flight before the machine stops
    /// waiting for the text-input server to agree. A request that lands after
    /// that is still recognised, because the request is remembered for longer
    /// than it is waited for.
    static let restorationTimeout: TimeInterval = 2.0
    /// How long a superseded request is remembered, so a change that lands late
    /// — after the user has already moved to a third application — is read as
    /// the tail of our own request and not as something the user did in the
    /// application that is frontmost now.
    static let supersedeGrace: TimeInterval = 2.0
    /// How many applications are remembered. Each entry is two short strings,
    /// and the least recently used application is the one dropped.
    static let maxRememberedApplications = 300
    /// How often the service checks for a restoration whose notification never
    /// arrived, while one is in flight.
    static let timeoutPoll: TimeInterval = 0.5

    /// Whether the feature should be watching at all. No Accessibility grant is
    /// needed: selecting an input source is a public Text Input Source Service
    /// call, not an injection.
    static func shouldRun(featureInstalled: Bool, enabled: Bool, sessionIsActive: Bool) -> Bool {
        featureInstalled && enabled && sessionIsActive
    }

    /// The key an application is remembered under.
    ///
    /// A bundle identifier is the identity: it survives renames, icon changes
    /// and upgrades, and it is the only application fact this feature keeps. A
    /// process with no bundle identifier — a bare executable from a terminal,
    /// the login window — is keyed by the path of the bundle that launched it,
    /// under a prefix no bundle identifier can have, so the two kinds of key can
    /// never merge two applications into one. An application with neither is
    /// given no key at all: it is remembered as nothing rather than as somebody.
    static func applicationKey(bundleIdentifier: String?, bundlePath: String?) -> String? {
        if let bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleIdentifier.isEmpty, isUsableIdentifier(bundleIdentifier) {
            return "bundle:" + bundleIdentifier
        }
        if let bundlePath = bundlePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundlePath.isEmpty, bundlePath.hasPrefix("/"), isUsableIdentifier(bundlePath) {
            return "path:" + bundlePath
        }
        return nil
    }

    /// The application key's kind, for the settings page's words and for the
    /// tests that keep the two namespaces apart.
    static func isBundleIdentifierKey(_ key: String) -> Bool { key.hasPrefix("bundle:") }

    /// The stored identifiers are compared exactly, so they must be short,
    /// printable, and free of the separators the codec leans on.
    static func isUsableIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 1024 else { return false }
        return !value.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    /// An input source id as the Text Input Source Service writes it, such as
    /// `com.apple.keylayout.ABC` or `com.apple.inputmethod.SCIM.ITABC`.
    static func isUsableSourceID(_ sourceID: String) -> Bool {
        guard sourceID == sourceID.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceID.isEmpty, sourceID.utf8.count <= 256 else { return false }
        return !sourceID.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    /// The source the change notification names, when it names one.
    ///
    /// The distributed notification carries the new source's identifier under a
    /// key, and the key has been spelled more than one way across macOS
    /// versions, so all the known spellings are read and the reading is used as
    /// a hint only: the machine is driven by what the service reads back out of
    /// the text-input server, which is the fact.
    static func sourceID(fromNotificationUserInfo userInfo: [AnyHashable: Any]?) -> String? {
        guard let userInfo else { return nil }
        for key in ["selectedKeyboardInputSource",
                    "com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged",
                    "kTISPropertyInputSourceID"] {
            if let value = userInfo[key] as? String, isUsableSourceID(value) { return value }
        }
        return nil
    }
}

// MARK: - What is remembered

/// The applications the user's sources are remembered for, in the order they
/// were last remembered.
///
/// The order is not decoration: the settings page lists the applications a
/// person has used most recently first, and the limit drops from the far end,
/// so the map cannot grow without bound while an app is installed for years.
struct InputSourcePreferenceMap: Equatable {
    struct Entry: Equatable {
        let key: String
        let sourceID: String
    }

    private(set) var entries: [Entry]
    /// Applications kept before the oldest of them is dropped.
    var limit: Int

    init(entries: [Entry] = [], limit: Int = InputSourceMemorySupport.maxRememberedApplications) {
        var kept: [Entry] = []
        for entry in entries where InputSourceMemorySupport.isUsableIdentifier(entry.key)
            && InputSourceMemorySupport.isUsableSourceID(entry.sourceID) {
            kept.removeAll { $0.key == entry.key }
            kept.append(entry)
        }
        self.entries = kept
        self.limit = max(1, limit)
    }

    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }
    var keys: [String] { entries.map(\.key) }

    subscript(key: String) -> String? {
        entries.first { $0.key == key }?.sourceID
    }

    /// Remembers a source for an application and moves that application to the
    /// recent end, so the remembered source of an application in use is never
    /// the one the limit drops.
    mutating func set(sourceID: String, for key: String) {
        guard InputSourceMemorySupport.isUsableIdentifier(key),
              InputSourceMemorySupport.isUsableSourceID(sourceID) else { return }
        entries.removeAll { $0.key == key }
        entries.append(Entry(key: key, sourceID: sourceID))
        while entries.count > limit { entries.removeFirst() }
    }

    @discardableResult
    mutating func remove(_ key: String) -> Bool {
        let before = entries.count
        entries.removeAll { $0.key == key }
        return entries.count != before
    }
}

/// Reading and writing the remembered applications.
///
/// The shape on disk is an array of pairs, not a dictionary, because the order
/// is part of what is stored and a JSON object makes a liar of it. Anything the
/// reader cannot account for is dropped rather than repaired: a preference file
/// written by a future version, or a value that arrived through an import, is
/// not a reason to invent an application's input source.
enum InputSourcePreferenceCodec {
    private struct Pair: Codable {
        let app: String
        let source: String
    }

    static func encode(_ map: InputSourcePreferenceMap) -> Data? {
        let pairs = map.entries.map { Pair(app: $0.key, source: $0.sourceID) }
        guard !pairs.isEmpty else { return Data("[]".utf8) }
        return try? JSONEncoder().encode(pairs)
    }

    static func decode(_ data: Data?, limit: Int = InputSourceMemorySupport.maxRememberedApplications)
        -> InputSourcePreferenceMap {
        guard let data, !data.isEmpty else { return InputSourcePreferenceMap(limit: limit) }
        guard let pairs = try? JSONDecoder().decode([Pair].self, from: data) else {
            return InputSourcePreferenceMap(limit: limit)
        }
        return InputSourcePreferenceMap(
            entries: pairs.map { InputSourcePreferenceMap.Entry(key: $0.app, sourceID: $0.source) },
            limit: limit)
    }
}

// MARK: - The machine

/// One thing the machine decided.
enum InputSourceMemoryEvent: Equatable {
    /// The frontmost application has never been seen, and its current source is
    /// recorded as what it prefers. Nothing is switched.
    case firstContact(key: String, sourceID: String)
    /// The application's remembered source is the one already typing, so the
    /// machine asks for nothing.
    case alreadyCurrent(key: String, sourceID: String)
    /// The application's remembered source is not typing, and the machine asked
    /// the service to select it. The token names this one request.
    case restoreRequested(key: String, sourceID: String, token: Int)
    /// A request the machine made for this application landed. The notification
    /// is ours, and the user is not asked to have caused it.
    case restored(key: String, sourceID: String)
    /// A request of ours landed after the user had already moved on, so it is
    /// read as our own tail and not as a choice made in the application that is
    /// frontmost now.
    case lateAutomaticChange(key: String, sourceID: String)
    /// The service reported that the select call was refused.
    case restorationFailed(key: String, sourceID: String)
    /// No notification arrived for a request, so the machine stopped waiting.
    case restorationTimedOut(key: String, sourceID: String)
    /// A request was cancelled because the user moved to another application
    /// while it was in flight.
    case superseded(key: String, sourceID: String)
    /// A change with no request of ours behind it, read as the user's. The key is
    /// the application that was frontmost, and nil when no application is known
    /// to be frontmost — which is the case the machine refuses to guess about.
    case manualChange(key: String?, sourceID: String)
    /// The frontmost application is one the machine cannot name, so it remembers
    /// nothing and switches nothing.
    case unidentifiedApplication
    /// The application has a remembered source that is no longer installed, so
    /// the machine adopts what is typing instead of asking for the impossible.
    case rememberedSourceUnavailable(key: String, sourceID: String)
    /// Nothing is known about what is typing, so nothing can be decided.
    case noCurrentSource
}

/// One thing the machine told the service to do.
enum InputSourceMemoryAction: Equatable {
    /// Ask the text-input server for this source. The machine never touches it.
    case select(sourceID: String, token: Int)
    /// Write the whole map, which now holds this pair.
    case save(key: String, sourceID: String)
    /// Write the whole map, which no longer holds this application.
    case forget(key: String)
}

struct InputSourceMemoryOutcome: Equatable {
    let events: [InputSourceMemoryEvent]
    let actions: [InputSourceMemoryAction]

    static let empty = InputSourceMemoryOutcome(events: [], actions: [])
}

/// The per-application input source machine.
///
/// Main-thread use, one instance, driven by the service. The machine holds the
/// remembered map, the frontmost application, the source it last saw, and at
/// most one restoration in flight.
struct InputSourceMemoryMachine {
    /// A restoration we asked for and have not seen land.
    struct Pending: Equatable {
        let key: String
        let sourceID: String
        let token: Int
        let requestedAt: TimeInterval
    }

    /// A restoration that was cancelled by the user moving on, kept long enough
    /// to recognise its notification when that notification arrives late.
    private struct Superseded: Equatable {
        let key: String
        let sourceID: String
        let expiresAt: TimeInterval
    }

    private(set) var preferences: InputSourcePreferenceMap
    private(set) var activeKey: String?
    private(set) var lastKnownSourceID: String?
    private(set) var pending: Pending?
    private(set) var token: Int = 0
    private var superseded: [Superseded] = []

    var restorationTimeout: TimeInterval = InputSourceMemorySupport.restorationTimeout
    var supersedeGrace: TimeInterval = InputSourceMemorySupport.supersedeGrace

    init(preferences: InputSourcePreferenceMap = InputSourcePreferenceMap()) {
        self.preferences = preferences
    }

    /// Whether a restoration is in flight, for the service's timer.
    var isWaitingForRestoration: Bool { pending != nil }

    /// The service reads the typing source back out of the system and reports it
    /// here when nothing is changing, so the machine's idea of the present is
    /// the system's, and an application's first contact is recorded against a
    /// source that really is typing.
    mutating func noteCurrentSource(_ sourceID: String?) {
        lastKnownSourceID = sourceID
    }

    /// The window server says an application is frontmost.
    mutating func applicationActivated(key: String?,
                                        currentSourceID: String?,
                                        isSourceInstalled: (String) -> Bool,
                                        at now: TimeInterval) -> InputSourceMemoryOutcome {
        pruneSuperseded(at: now)
        var events: [InputSourceMemoryEvent] = []
        var actions: [InputSourceMemoryAction] = []

        // The user moved on. Whatever we asked for on the way here is no longer
        // wanted, but it is remembered, because its notification is still
        // allowed to arrive.
        if let pending {
            superseded.append(Superseded(key: pending.key, sourceID: pending.sourceID,
                                         expiresAt: now + supersedeGrace))
            self.pending = nil
            events.append(.superseded(key: pending.key, sourceID: pending.sourceID))
        }

        activeKey = key
        lastKnownSourceID = currentSourceID
        guard let key else {
            events.append(.unidentifiedApplication)
            return InputSourceMemoryOutcome(events: events, actions: actions)
        }
        guard let currentSourceID else {
            events.append(.noCurrentSource)
            return InputSourceMemoryOutcome(events: events, actions: actions)
        }

        guard let remembered = preferences[key] else {
            // An application seen for the first time keeps what it is typing
            // with. Nothing is switched, and the user's next manual change is
            // recorded as it arrives.
            preferences.set(sourceID: currentSourceID, for: key)
            events.append(.firstContact(key: key, sourceID: currentSourceID))
            actions.append(.save(key: key, sourceID: currentSourceID))
            return InputSourceMemoryOutcome(events: events, actions: actions)
        }

        if remembered == currentSourceID {
            events.append(.alreadyCurrent(key: key, sourceID: remembered))
            return InputSourceMemoryOutcome(events: events, actions: actions)
        }

        guard isSourceInstalled(remembered) else {
            // The input source was removed, disabled, or uninstalled. Asking is
            // impossible and would repeat on every visit, so the application
            // adopts what is typing and the preference is rewritten to it.
            preferences.set(sourceID: currentSourceID, for: key)
            events.append(.rememberedSourceUnavailable(key: key, sourceID: remembered))
            actions.append(.save(key: key, sourceID: currentSourceID))
            return InputSourceMemoryOutcome(events: events, actions: actions)
        }

        token += 1
        pending = Pending(key: key, sourceID: remembered, token: token, requestedAt: now)
        events.append(.restoreRequested(key: key, sourceID: remembered, token: token))
        actions.append(.select(sourceID: remembered, token: token))
        return InputSourceMemoryOutcome(events: events, actions: actions)
    }

    /// The text-input server says the typing source is now this one.
    ///
    /// This is where a feedback loop would start, and where it is stopped: a
    /// change that answers a request of ours is never read as the user's choice,
    /// and a change that cannot be matched to an application is never written to
    /// one.
    mutating func inputSourceChanged(to sourceID: String,
                                      at now: TimeInterval) -> InputSourceMemoryOutcome {
        pruneSuperseded(at: now)
        guard InputSourceMemorySupport.isUsableSourceID(sourceID) else {
            return InputSourceMemoryOutcome(events: [.noCurrentSource], actions: [])
        }
        if sourceID == lastKnownSourceID {
            // The server notifies more than once for one change, and a repeat is
            // not a second event.
            return InputSourceMemoryOutcome(events: [], actions: [])
        }

        if let pending, pending.sourceID == sourceID {
            self.pending = nil
            lastKnownSourceID = sourceID
            // The map already holds this source for this application; touching
            // it keeps that application at the recent end of the list.
            preferences.set(sourceID: sourceID, for: pending.key)
            return InputSourceMemoryOutcome(
                events: [.restored(key: pending.key, sourceID: sourceID)],
                actions: [.save(key: pending.key, sourceID: sourceID)])
        }

        if let index = superseded.firstIndex(where: { $0.sourceID == sourceID }) {
            // Our own request landed late. It is not the frontmost
            // application's choice, so nothing is written for it.
            let match = superseded.remove(at: index)
            lastKnownSourceID = sourceID
            return InputSourceMemoryOutcome(
                events: [.lateAutomaticChange(key: match.key, sourceID: sourceID)], actions: [])
        }

        // No request of ours is behind this change, so it is the user's, and it
        // belongs to the application that is frontmost. When no application is
        // known, the change is left unwritten: an uncertain application must not
        // be given a preference.
        self.pending = nil
        lastKnownSourceID = sourceID
        var actions: [InputSourceMemoryAction] = []
        if let activeKey {
            preferences.set(sourceID: sourceID, for: activeKey)
            actions.append(.save(key: activeKey, sourceID: sourceID))
        }
        return InputSourceMemoryOutcome(events: [.manualChange(key: activeKey, sourceID: sourceID)],
                                        actions: actions)
    }

    /// The service's select call came back refused. The stored preference is
    /// left as it is, so the next visit to the application asks again.
    mutating func restorationFailed(token: Int, at now: TimeInterval) -> InputSourceMemoryOutcome {
        pruneSuperseded(at: now)
        guard let pending, pending.token == token else { return .empty }
        self.pending = nil
        return InputSourceMemoryOutcome(
            events: [.restorationFailed(key: pending.key, sourceID: pending.sourceID)], actions: [])
    }

    /// The clock says the request has waited long enough. A change that arrives
    /// afterwards is read as a late automatic change, because the request is
    /// remembered for longer than it is waited for.
    mutating func expirePending(at now: TimeInterval) -> InputSourceMemoryOutcome {
        pruneSuperseded(at: now)
        guard let pending, now - pending.requestedAt >= restorationTimeout else { return .empty }
        self.pending = nil
        superseded.append(Superseded(key: pending.key, sourceID: pending.sourceID,
                                     expiresAt: now + supersedeGrace))
        return InputSourceMemoryOutcome(
            events: [.restorationTimedOut(key: pending.key, sourceID: pending.sourceID)], actions: [])
    }

    private mutating func pruneSuperseded(at now: TimeInterval) {
        superseded.removeAll { $0.expiresAt <= now }
    }
}
