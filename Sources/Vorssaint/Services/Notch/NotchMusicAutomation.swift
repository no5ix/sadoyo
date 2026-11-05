// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices

/// Apple Events stay in this process so consent belongs to this app. Addressing
/// the running PID cannot fall through to the system's currently playing video.
enum NotchMusicAutomation {
    struct Target: Equatable {
        let pid: Int32
        let bundleIdentifier: String
        let bundleURL: URL
        /// Nil when Launch Services did not start the player, as for a process
        /// launchd spawned; the bundle checks still bind the process identity.
        let launched: Date?

        init?(_ playback: NotchPlayback) {
            guard let pid = playback.track.appPID, let bundle = playback.track.appBundleIdentifier,
                  let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
                  app.bundleIdentifier == bundle, let url = app.bundleURL else { return nil }
            self.pid = pid; bundleIdentifier = bundle; bundleURL = url; launched = app.launchDate
        }

        var isCurrent: Bool {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
            return app.bundleIdentifier == bundleIdentifier && app.bundleURL == bundleURL && app.launchDate == launched
        }
    }

    enum Access { case granted, consent, denied, unavailable }
    struct Availability {
        let target: Target
        let capabilities: NotchMusicAutomationCapabilities
        let access: Access
    }

    static func inspect(_ target: Target) -> Availability? {
        guard target.isCurrent, let capabilities = NotchMusicAutomationCapabilities.load(bundleURL: target.bundleURL) else { return nil }
        return Availability(target: target, capabilities: capabilities, access: access(to: target))
    }

    /// Consent for a running application by itself, for the players a card
    /// reads that are not the system's own session. Addressing the process, and
    /// checking its bundle, keeps the answer about that process.
    static func access(pid: Int32, bundleIdentifier: String) -> Access {
        guard pid > 0, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.bundleIdentifier == bundleIdentifier else { return .unavailable }
        let address = NSAppleEventDescriptor(processIdentifier: pid)
        switch AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, false) {
        case noErr: return .granted
        case OSStatus(errAEEventWouldRequireUserConsent): return .consent
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .unavailable
        }
    }

    static func access(to target: Target) -> Access {
        guard target.isCurrent else { return .unavailable }
        let address = NSAppleEventDescriptor(processIdentifier: target.pid)
        switch AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, false) {
        case noErr: return .granted
        case OSStatus(errAEEventWouldRequireUserConsent): return .consent
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .unavailable
        }
    }

    static func event(_ command: NotchPlaybackCommand, playback: NotchPlayback,
                      capabilities: NotchMusicAutomationCapabilities, pid: Int32) -> NSAppleEventDescriptor? {
        guard pid > 0 else { return nil }
        let address = NSAppleEventDescriptor(processIdentifier: pid)
        if case .seek(let seconds) = command {
            guard seconds.isFinite, (0...604_800).contains(seconds), let position = capabilities.position,
                  let event = propertyEvent(kAESetData, code: position.code, address: address) else { return nil }
            event.setParam(position.integer ? NSAppleEventDescriptor(int32: Int32(seconds.rounded()))
                           : NSAppleEventDescriptor(double: seconds), forKeyword: keyAEData)
            return event
        }
        guard let code = capabilities.event(for: command, isPlaying: playback.isPlaying) else { return nil }
        return NSAppleEventDescriptor(eventClass: code.eventClass, eventID: code.eventID, targetDescriptor: address,
                                      returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    }

    /// Reads the player's shuffle switch with nil, or sets it. Like seeking,
    /// only the property the player's dictionary declares is addressed.
    static func shuffleEvent(_ enabled: Bool?, capabilities: NotchMusicAutomationCapabilities,
                             pid: Int32) -> NSAppleEventDescriptor? {
        guard pid > 0, let shuffle = capabilities.shuffle,
              let event = propertyEvent(enabled == nil ? kAEGetData : kAESetData, code: shuffle,
                                        address: NSAppleEventDescriptor(processIdentifier: pid)) else { return nil }
        if let enabled { event.setParam(NSAppleEventDescriptor(boolean: enabled), forKeyword: keyAEData) }
        return event
    }

    static func shuffleAllowedEvent(capabilities: NotchMusicAutomationCapabilities, pid: Int32) -> NSAppleEventDescriptor? {
        guard pid > 0, let allowed = capabilities.shuffleAllowed else { return nil }
        return propertyEvent(kAEGetData, code: allowed, address: NSAppleEventDescriptor(processIdentifier: pid))
    }

    /// Only a Boolean answer is a state; anything else leaves it unknown.
    static func shuffleState(in reply: NSAppleEventDescriptor) -> Bool? {
        guard let value = reply.paramDescriptor(forKeyword: keyDirectObject),
              [typeTrue, typeFalse, typeBoolean].contains(value.descriptorType) else { return nil }
        return value.booleanValue
    }

    /// Nil when the player cannot be asked or does not answer with a state.
    static func shuffle(of availability: Availability) -> Bool? {
        read(shuffleEvent(nil, capabilities: availability.capabilities, pid: availability.target.pid), from: availability)
    }

    /// False only when the player says the songs playing cannot be shuffled,
    /// as some do for a radio. A player that does not say, or cannot be
    /// asked before consent, keeps the button that asks for it.
    static func shuffleAllowed(by availability: Availability) -> Bool {
        guard availability.capabilities.shuffleAllowed != nil else { return true }
        return read(shuffleAllowedEvent(capabilities: availability.capabilities, pid: availability.target.pid),
                    from: availability) != false
    }

    private static func read(_ event: NSAppleEventDescriptor?, from availability: Availability) -> Bool? {
        guard availability.target.isCurrent, access(to: availability.target) == .granted, let event,
              let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 1),
              (reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0) == 0 else { return nil }
        return shuffleState(in: reply)
    }

    static func setShuffle(_ enabled: Bool, availability: Availability) -> Bool {
        guard availability.target.isCurrent, access(to: availability.target) == .granted,
              let event = shuffleEvent(enabled, capabilities: availability.capabilities, pid: availability.target.pid),
              let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 1) else { return false }
        return (reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0) == 0
    }

    /// Reads one property of the application as text, as a player's song name
    /// answers. Only text is an answer; anything else leaves it unread.
    static func textProperty(_ code: UInt32, pid: Int32) -> String? {
        guard let reply = propertyReply(code, pid: pid) else { return nil }
        return text(in: reply.paramDescriptor(forKeyword: keyDirectObject))
    }

    /// Reads one property as a number, as a player's position and length
    /// answer. A player that answers a length with a clock ("4:01") is read by
    /// the same rule as its text.
    static func numberProperty(_ code: UInt32, pid: Int32) -> Double? {
        guard let reply = propertyReply(code, pid: pid) else { return nil }
        let value = reply.paramDescriptor(forKeyword: keyDirectObject)
        if let number = value?.doubleValue, number.isFinite, number >= 0 { return number }
        return text(in: value).flatMap(PlaybackSessionsSupport.seconds(from:))
    }

    /// A player's answer to a property: text, and a list of characters joined.
    private static func text(in descriptor: NSAppleEventDescriptor?) -> String? {
        guard let descriptor else { return nil }
        if let value = descriptor.stringValue, !value.isEmpty { return value }
        guard descriptor.numberOfItems > 0, descriptor.numberOfItems <= 4096 else { return nil }
        var text = ""
        for index in 1...max(1, descriptor.numberOfItems) {
            guard let piece = descriptor.atIndex(index)?.stringValue, piece.utf8.count <= 1024 else { return nil }
            text += piece
        }
        return text.isEmpty ? nil : text
    }

    /// One read of one property, addressed at the process that owns it. A reply
    /// carrying an error number is no answer at all.
    private static func propertyReply(_ code: UInt32, pid: Int32) -> NSAppleEventDescriptor? {
        guard pid > 0, let event = propertyEvent(kAEGetData, code: code,
                                                 address: NSAppleEventDescriptor(processIdentifier: pid)),
              let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 1),
              (reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0) == 0 else { return nil }
        return reply
    }

    /// Sends one command to one process, for a card that is not the system's
    /// own session. What the player's dictionary declares is what is sent.
    static func sendToPlayer(_ command: NotchPlaybackCommand, isPlaying: Bool,
                             capabilities: NotchMusicAutomationCapabilities, pid: Int32) -> Bool {
        guard pid > 0, let event = event(command, isPlaying: isPlaying, capabilities: capabilities, pid: pid),
              let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 1)
        else { return false }
        // A timeout may occur after delivery. Never retry a playback action.
        return (reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0) == 0
    }

    /// The same command, addressed at a process by itself. The system's own
    /// session spells its play/pause state in its playback; a card of its own
    /// knows the state it read.
    static func event(_ command: NotchPlaybackCommand, isPlaying: Bool,
                      capabilities: NotchMusicAutomationCapabilities, pid: Int32) -> NSAppleEventDescriptor? {
        guard pid > 0, let code = capabilities.event(for: command, isPlaying: isPlaying) else { return nil }
        return NSAppleEventDescriptor(eventClass: code.eventClass, eventID: code.eventID,
                                      targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                                      returnID: AEReturnID(kAutoGenerateReturnID),
                                      transactionID: AETransactionID(kAnyTransactionID))
    }

    /// Gets or sets one property of the application itself.
    static func propertyEvent(_ eventID: AEEventID, code: UInt32,
                                      address: NSAppleEventDescriptor) -> NSAppleEventDescriptor? {
        let specifier = NSAppleEventDescriptor.record()
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: typeProperty), forKeyword: AEKeyword(keyAEDesiredClass))
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: code), forKeyword: AEKeyword(keyAEKeyData))
        specifier.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: AEKeyword(keyAEContainer))
        guard let property = specifier.coerce(toDescriptorType: typeObjectSpecifier) else { return nil }
        let event = NSAppleEventDescriptor(eventClass: kAECoreSuite, eventID: eventID, targetDescriptor: address,
                                           returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(property, forKeyword: keyDirectObject)
        return event
    }

    static func send(_ command: NotchPlaybackCommand, playback: NotchPlayback, availability: Availability,
                     cancellation: DispatchWorkItem, validatedAt: TimeInterval) -> Bool {
        guard !cancellation.isCancelled, availability.target.isCurrent,
              access(to: availability.target) == .granted,
              let event = event(command, playback: playback, capabilities: availability.capabilities, pid: availability.target.pid),
              !cancellation.isCancelled, availability.target.isCurrent,
              ProcessInfo.processInfo.systemUptime - validatedAt < 0.5 else { return false }
        // A timeout may occur after delivery. Never retry a playback action.
        guard let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 1) else { return false }
        return (reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0) == 0
    }
}
