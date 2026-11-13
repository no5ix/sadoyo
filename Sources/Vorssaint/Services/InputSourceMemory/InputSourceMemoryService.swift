// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

/// Remembers the input source each application was last seen typing with, and
/// restores it when that application comes back to the front.
///
/// The service owns the watching and the selecting; every decision is the pure
/// `InputSourceMemoryMachine`'s, so the part that can go wrong is tested without
/// a Mac being asked to change its keyboard.
///
/// Three streams arrive:
///
/// - `NSWorkspace.didActivateApplicationNotification`, which names the
///   application the user has moved to. The application's identity is taken from
///   the notification itself, and only its strings are kept: no application
///   object outlives the callback.
/// - `kTISNotifySelectedKeyboardInputSourceChanged`, from the distributed center,
///   which says that the typing source is now something else. It says nothing
///   about who asked, so the machine compares it against the request the service
///   has in flight and treats a change it cannot match as the user's.
/// - The user's own switching, which arrives through the same text-input
///   notification and is the ordinary case of the last bullet.
///
/// Selecting an input source is a public Text Input Source Service call, so this
/// feature needs no Accessibility, Input Monitoring, or Automation grant.
final class InputSourceMemoryService: ObservableObject {
    static let shared = InputSourceMemoryService()

    @Published private(set) var isRunning = false
    /// How many applications have a remembered source. The feature is silent, so
    /// the settings page says what it has to work with: zero explains a switch
    /// that appears to do nothing, and a number that grows says the remembering
    /// is happening. The applications are not listed, so the page keeps no table
    /// to tend.
    @Published private(set) var rememberedCount = 0

    private var machine = InputSourceMemoryMachine()
    private var activationObserver: NSObjectProtocol?
    private var inputSourceObserver: NSObjectProtocol?
    private var expiryTimer: Timer?
    private var pendingWrite: DispatchWorkItem?
    private let selfBundleIdentifier = Bundle.main.bundleIdentifier

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    /// Start watching when the feature is installed and switched on, and stop
    /// when either is taken away. The remembered applications survive a switch
    /// off, so switching the feature back on restores what the user built up.
    func syncWithPreferences() {
        let wanted = InputSourceMemorySupport.shouldRun(
            featureInstalled: AppFeature.inputSourceMemory.isAvailable,
            enabled: UserDefaults.standard.bool(forKey: DefaultsKey.inputSourceMemoryEnabled),
            sessionIsActive: SessionActivity.shared.isActive)
        if wanted {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard !isRunning else { return }
        machine = InputSourceMemoryMachine(
            preferences: InputSourcePreferenceCodec.decode(
                UserDefaults.standard.data(forKey: DefaultsKey.inputSourceMemoryPreferences)))
        machine.noteCurrentSource(InputSourceSelection.currentSourceID())
        rememberedCount = machine.preferences.count

        let workspace = NSWorkspace.shared.notificationCenter
        guard activationObserver == nil else { return }
        activationObserver = workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            self?.applicationActivated(bundleIdentifier: app.bundleIdentifier,
                                       bundlePath: app.bundleURL?.path)
        }
        guard inputSourceObserver == nil else { return }
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            // The notification names a source under a key, and that key has been
            // spelled more than one way across macOS versions, so the machine is
            // given the reading back out of the text-input server: that is the
            // fact, where the notification is a hint. A reader that wants the hint
            // has `InputSourceMemorySupport.sourceID(fromNotificationUserInfo:)`.
            self?.inputSourceChanged(InputSourceSelection.currentSourceID())
        }
        isRunning = true
        scheduleExpiry()
    }

    func stop() {
        flushWrite()
        expiryTimer?.invalidate()
        expiryTimer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if let inputSourceObserver {
            DistributedNotificationCenter.default().removeObserver(inputSourceObserver)
            self.inputSourceObserver = nil
        }
        isRunning = false
    }

    // MARK: - Streams

    private func applicationActivated(bundleIdentifier: String?, bundlePath: String?) {
        guard isRunning else { return }
        // Sadoyo's own panels come to the front while the user is typing
        // somewhere else, and the panels never type. Keying them as nothing keeps
        // them out of the map, and keeps a manual change made while a panel is
        // frontmost from being attributed to it.
        let isSelf = bundleIdentifier != nil && bundleIdentifier == selfBundleIdentifier
        let key = isSelf ? nil
            : InputSourceMemorySupport.applicationKey(bundleIdentifier: bundleIdentifier,
                                                      bundlePath: bundlePath)
        let current = InputSourceSelection.currentSourceID()
        let installed = installedSourceIDs()
        let outcome = machine.applicationActivated(key: key,
                                                  currentSourceID: current,
                                                  isSourceInstalled: { installed.contains($0) },
                                                  at: ProcessInfo.processInfo.systemUptime)
        apply(outcome)
    }

    private func inputSourceChanged(_ sourceID: String?) {
        guard isRunning, let sourceID else { return }
        let outcome = machine.inputSourceChanged(to: sourceID,
                                                 at: ProcessInfo.processInfo.systemUptime)
        apply(outcome)
    }

    // MARK: - Doing what the machine decided

    private func apply(_ outcome: InputSourceMemoryOutcome) {
        rememberedCount = machine.preferences.count
        var selection: (sourceID: String, token: Int)?
        var writes = false
        for action in outcome.actions {
            switch action {
            case let .select(sourceID, token):
                selection = (sourceID, token)
            case .save, .forget:
                writes = true
            }
        }
        if writes { scheduleWrite() }
        if let selection {
            // The system's answer is the only evidence that a request landed. A
            // refused select leaves the stored preference alone, so the next
            // visit asks again rather than recording a source the user never got.
            if !InputSourceSelection.select(sourceID: selection.sourceID) {
                apply(machine.restorationFailed(token: selection.token,
                                                at: ProcessInfo.processInfo.systemUptime))
            }
        }
        scheduleExpiry()
    }

    /// The input sources the system will select, as ids. Read once per
    /// activation, because a source the user has just removed must be recognised
    /// before it is asked for.
    private func installedSourceIDs() -> Set<String> {
        Set(InputSourceSelection.selectableInputSources().compactMap {
            InputSourceSelection.inputSourceString($0, property: kTISPropertyInputSourceID)
        })
    }

    /// A restoration that never got its notification is given up on, so the
    /// machine is never left waiting behind a change that will not come.
    private func scheduleExpiry() {
        if !machine.isWaitingForRestoration {
            expiryTimer?.invalidate()
            expiryTimer = nil
            return
        }
        guard expiryTimer == nil else { return }
        let timer = Timer(timeInterval: InputSourceMemorySupport.timeoutPoll, repeats: true) { [weak self] _ in
            guard let self, self.machine.isWaitingForRestoration else {
                self?.expiryTimer?.invalidate()
                self?.expiryTimer = nil
                return
            }
            let outcome = self.machine.expirePending(at: ProcessInfo.processInfo.systemUptime)
            if !outcome.events.isEmpty { self.apply(outcome) }
        }
        timer.tolerance = InputSourceMemorySupport.timeoutPoll / 4
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    // MARK: - Persistence

    /// One write per burst of switching. A whole map of short strings is written
    /// under one key, and an application switch is not a reason to touch the
    /// disk each time.
    private func scheduleWrite() {
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeNow() }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func writeNow() {
        pendingWrite = nil
        guard let data = InputSourcePreferenceCodec.encode(machine.preferences) else { return }
        UserDefaults.standard.set(data, forKey: DefaultsKey.inputSourceMemoryPreferences)
    }

    private func flushWrite() {
        guard let pendingWrite else { return }
        pendingWrite.cancel()
        writeNow()
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let inputSourceObserver {
            DistributedNotificationCenter.default().removeObserver(inputSourceObserver)
        }
    }
}
