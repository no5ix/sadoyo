// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The per-application input source machine, driven by hand.
///
/// Nothing here touches a real keyboard, a real application, or the text-input
/// server: the machine is given application keys, source ids, and times, and the
/// assertions are about what it decided and what it asked the service to do. That
/// is the whole of the part that can go wrong, and it is the part a Mac cannot be
/// asked to demonstrate on demand.
///
/// The two applications the scenarios use are the two a person would notice: a
/// browser typed in an input method, and an editor typed in a plain layout.
enum InputSourceMemoryContract {
    private static let chrome = "bundle:com.google.Chrome"
    private static let code = "bundle:com.microsoft.VSCode"
    private static let terminal = "bundle:com.apple.Terminal"
    private static let safari = "bundle:com.apple.Safari"
    private static let chinese = "com.apple.inputmethod.SCIM.ITABC"
    private static let english = "com.apple.keylayout.ABC"
    private static let allInstalled: (String) -> Bool = { _ in true }

    /// A machine that already knows the browser's input method and the editor's
    /// plain layout, which is the pair every scenario below starts from. The map
    /// is built as it would be after the two applications had been visited, and
    /// handed to the machine the way a restart hands it what was written.
    private static func machineKnowingPair() -> InputSourceMemoryMachine {
        var map = InputSourcePreferenceMap()
        map.set(sourceID: chinese, for: chrome)
        map.set(sourceID: english, for: code)
        return InputSourceMemoryMachine(preferences: map)
    }

    static func run(_ suite: TestSuite) {
        identityChecks(suite)
        switchingChecks(suite)
        attributionChecks(suite)
        unavailableSourceChecks(suite)
        persistenceChecks(suite)
        lifecycleChecks(suite)
        pageChecks(suite)
    }

    // MARK: - Who an application is

    private static func identityChecks(_ suite: TestSuite) {
        suite.expect(InputSourceMemorySupport.applicationKey(bundleIdentifier: "com.google.Chrome",
                                                             bundlePath: nil) == "bundle:com.google.Chrome",
                     "an application is keyed by its bundle identifier")
        suite.expect(InputSourceMemorySupport.applicationKey(bundleIdentifier: "com.google.Chrome",
                                                             bundlePath: "/Applications/Chrome.app")
                == "bundle:com.google.Chrome",
                     "the bundle identifier wins over the path, so moving an app does not rename it")
        suite.expect(InputSourceMemorySupport.applicationKey(bundleIdentifier: nil,
                                                             bundlePath: "/Applications/Tool.app")
                == "path:/Applications/Tool.app",
                     "an application with no bundle identifier is keyed by its bundle path")
        suite.expect(InputSourceMemorySupport.applicationKey(bundleIdentifier: "",
                                                             bundlePath: "  ") == nil,
                     "a blank identifier and a blank path name no application")
        suite.expect(InputSourceMemorySupport.applicationKey(bundleIdentifier: nil, bundlePath: nil) == nil,
                     "an application with nothing to name it is remembered as nothing, not as a shared bucket")
        suite.expect(InputSourceMemorySupport.applicationKey(bundleIdentifier: nil,
                                                             bundlePath: "Applications/Tool.app") == nil,
                     "a relative path is not an application's place on disk")
        suite.expect(InputSourceMemorySupport.applicationKey(bundleIdentifier: "path:evil",
                                                             bundlePath: nil) == "bundle:path:evil"
                && InputSourceMemorySupport.applicationKey(bundleIdentifier: nil,
                                                           bundlePath: "/evil") == "path:/evil",
                     "the two namespaces cannot be entered from the other side, so no path key can merge two apps")
        suite.expect(InputSourceMemorySupport.isBundleIdentifierKey("bundle:com.apple.Safari")
                && !InputSourceMemorySupport.isBundleIdentifierKey("path:/tmp/Safari.app"),
                     "a key says which namespace it is in")
        suite.expect(InputSourceMemorySupport.isUsableSourceID(english)
                && InputSourceMemorySupport.isUsableSourceID(chinese)
                && !InputSourceMemorySupport.isUsableSourceID("")
                && !InputSourceMemorySupport.isUsableSourceID("ABC\n")
                && !InputSourceMemorySupport.isUsableSourceID(" ABC"),
                     "a source id is stored exactly as it is compared, and never with a stray line in it")
        suite.expect(InputSourceMemorySupport.sourceID(
            fromNotificationUserInfo: ["selectedKeyboardInputSource": english]) == english
                && InputSourceMemorySupport.sourceID(
                    fromNotificationUserInfo: ["kTISPropertyInputSourceID": chinese]) == chinese,
                     "the notification's own source is read from the keys it is known to use")
        suite.expect(InputSourceMemorySupport.sourceID(fromNotificationUserInfo: nil) == nil
                && InputSourceMemorySupport.sourceID(fromNotificationUserInfo: ["other": english]) == nil,
                     "a notification naming no usable source yields no source, and the machine is fed the reading instead")
    }

    // MARK: - Restoring on the way between applications

    private static func switchingChecks(_ suite: TestSuite) {
        var machine = InputSourceMemoryMachine()
        // The browser is found typing with the input method, and the editor with
        // the plain layout. Neither visit switches anything: the first contact
        // only records what the person is already doing.
        var outcome = machine.applicationActivated(key: chrome, currentSourceID: chinese,
                                                  isSourceInstalled: allInstalled, at: 0)
        suite.expect(outcome.events == [.firstContact(key: chrome, sourceID: chinese)]
                && outcome.actions == [.save(key: chrome, sourceID: chinese)],
                     "a new application records the source it is typing with and switches nothing")
        outcome = machine.applicationActivated(key: code, currentSourceID: english,
                                               isSourceInstalled: allInstalled, at: 1)
        suite.expect(outcome.events == [.firstContact(key: code, sourceID: english)]
                && machine.preferences[chrome] == chinese
                && machine.preferences[code] == english,
                     "the browser keeps its input method and the editor its plain layout, remembered apart")

        // Editor to browser: the browser's method is not typing, so it is asked for.
        outcome = machine.applicationActivated(key: chrome, currentSourceID: english,
                                               isSourceInstalled: allInstalled, at: 2)
        suite.expect(outcome.events == [.restoreRequested(key: chrome, sourceID: chinese, token: 1)]
                && outcome.actions == [.select(sourceID: chinese, token: 1)],
                     "the browser's remembered input method is asked for on the way in")

        // It lands. The change is ours, and the editor is not written to.
        outcome = machine.inputSourceChanged(to: chinese, at: 2.1)
        suite.expect(outcome.events == [.restored(key: chrome, sourceID: chinese)]
                && machine.preferences[code] == english,
                     "the restoration is attributed to the browser, and the editor's plain layout is left alone")

        // Back to the editor, and the plain layout comes back.
        outcome = machine.applicationActivated(key: code, currentSourceID: chinese,
                                               isSourceInstalled: allInstalled, at: 3)
        let requested = outcome.actions.contains { $0 == .select(sourceID: english, token: 2) }
        suite.expect(outcome.events.contains(.restoreRequested(key: code, sourceID: english, token: 2))
                && requested,
                     "the editor's plain layout is asked for on the way back")
        outcome = machine.inputSourceChanged(to: english, at: 3.1)
        suite.expect(outcome.events == [.restored(key: code, sourceID: english)]
                && machine.preferences[chrome] == chinese,
                     "the browser's input method survives the editor's restoration")

        // Visiting an application whose source is already typing asks for nothing.
        let visits = machine.applicationActivated(key: code, currentSourceID: english,
                                                  isSourceInstalled: allInstalled, at: 4)
        suite.expect(visits.events == [.alreadyCurrent(key: code, sourceID: english)] && visits.actions.isEmpty,
                     "an application that is already typing with its remembered source is never switched")
        let again = machine.applicationActivated(key: code, currentSourceID: english,
                                                 isSourceInstalled: allInstalled, at: 5)
        suite.expect(again.actions.isEmpty && !machine.isWaitingForRestoration,
                     "visiting the same application twice in a row causes no second switch")

        // A source the person chose in the terminal is remembered for the terminal.
        _ = machine.applicationActivated(key: terminal, currentSourceID: english,
                                         isSourceInstalled: allInstalled, at: 6)
        outcome = machine.inputSourceChanged(to: chinese, at: 7)
        suite.expect(outcome.events == [.manualChange(key: terminal, sourceID: chinese)]
                && outcome.actions == [.save(key: terminal, sourceID: chinese)]
                && machine.preferences[terminal] == chinese
                && machine.preferences[chrome] == chinese,
                     "a change with no request of ours behind it belongs to the frontmost application, and to it alone")
    }

    // MARK: - Whose change is it

    private static func attributionChecks(_ suite: TestSuite) {
        var machine = machineKnowingPair()
        // The user leaves the browser for the editor; the plain layout is asked
        // for and never lands, because the user is already gone.
        _ = machine.applicationActivated(key: code, currentSourceID: chinese,
                                         isSourceInstalled: allInstalled, at: 0)
        // ... and the third application arrives before it does.
        var outcome = machine.applicationActivated(key: terminal, currentSourceID: chinese,
                                                  isSourceInstalled: allInstalled, at: 0.2)
        suite.expect(outcome.events.first == .superseded(key: code, sourceID: english),
                     "a request cancelled by the next application is reported as cancelled")
        suite.expect(!machine.isWaitingForRestoration,
                     "the cancelled request is no longer in flight")

        // The editor's plain layout lands late, while the terminal is frontmost.
        // It is our own tail, and the terminal is not given it.
        let rememberedTerminal = machine.preferences[terminal]
        outcome = machine.inputSourceChanged(to: english, at: 0.4)
        suite.expect(outcome.events == [.lateAutomaticChange(key: code, sourceID: english)]
                && outcome.actions.isEmpty
                && machine.preferences[terminal] == rememberedTerminal,
                     "a change that answers a cancelled request is not written to the application that is frontmost now")

        // The terminal's own choice is written, and only to the terminal.
        outcome = machine.inputSourceChanged(to: chinese, at: 0.6)
        suite.expect(outcome.events == [.manualChange(key: terminal, sourceID: chinese)],
                     "a change the machine did not ask for is the person's, for the frontmost application")

        // Rapid switching: the stale request must not act, and its notification
        // must not be read as the newest application's choice.
        machine = machineKnowingPair()
        _ = machine.applicationActivated(key: code, currentSourceID: chinese,
                                         isSourceInstalled: allInstalled, at: 10)
        outcome = machine.applicationActivated(key: safari, currentSourceID: english,
                                               isSourceInstalled: allInstalled, at: 10.02)
        suite.expect(outcome.events.contains(.firstContact(key: safari, sourceID: english))
                && machine.preferences[chrome] == chinese,
                     "the newest application is decided by its own visit, not by the request on its way out")
        outcome = machine.inputSourceChanged(to: english, at: 10.04)
        suite.expect(outcome.actions.isEmpty
                && machine.preferences[code] == english
                && machine.preferences[safari] == english,
                     "a landing request writes nothing new, and cannot rewrite the application it was not for")

        // A change with no application in front is left unwritten, because the
        // application it belongs to is not known.
        var blank = InputSourceMemoryMachine()
        outcome = blank.applicationActivated(key: nil, currentSourceID: english,
                                             isSourceInstalled: allInstalled, at: 0)
        suite.expect(outcome.events == [.unidentifiedApplication] && outcome.actions.isEmpty,
                     "an application that cannot be named is neither switched nor remembered")
        outcome = blank.inputSourceChanged(to: chinese, at: 1)
        suite.expect(outcome.events == [.manualChange(key: nil, sourceID: chinese)]
                && outcome.actions.isEmpty && blank.preferences.isEmpty,
                     "a change whose application is unknown is never written to an application by guesswork")
        suite.expect(blank.applicationActivated(key: chrome, currentSourceID: nil,
                                                isSourceInstalled: allInstalled, at: 2).events
            == [.noCurrentSource],
                     "a visit with nothing known to be typing decides nothing")

        // A request that is refused keeps the preference, so the next visit tries
        // again rather than recording a source nobody got.
        var refused = machineKnowingPair()
        _ = refused.applicationActivated(key: chrome, currentSourceID: english,
                                         isSourceInstalled: allInstalled, at: 0)
        outcome = refused.restorationFailed(token: 1, at: 0.1)
        suite.expect(outcome.events == [.restorationFailed(key: chrome, sourceID: chinese)]
                && refused.preferences[chrome] == chinese
                && !refused.isWaitingForRestoration,
                     "a refused select leaves the remembered source exactly where it was")
        let stale = refused.restorationFailed(token: 40, at: 0.2)
        suite.expect(stale.events.isEmpty && refused.preferences[chrome] == chinese,
                     "a report about a request that is no longer in flight changes nothing")

        // A restoration whose notification never arrives is given up on, and the
        // preference is kept for the next visit.
        var silent = machineKnowingPair()
        _ = silent.applicationActivated(key: code, currentSourceID: chinese,
                                        isSourceInstalled: allInstalled, at: 0)
        outcome = silent.expirePending(at: 0.5)
        suite.expect(outcome.events.isEmpty && silent.isWaitingForRestoration,
                     "a request is not given up on before its time has passed")
        outcome = silent.expirePending(at: 3)
        suite.expect(outcome.events == [.restorationTimedOut(key: code, sourceID: english)]
                && silent.preferences[code] == english && !silent.isWaitingForRestoration,
                     "a request whose notification never came is given up on, and its preference survives")
        outcome = silent.inputSourceChanged(to: english, at: 4)
        suite.expect(outcome.events == [.lateAutomaticChange(key: code, sourceID: english)]
                && outcome.actions.isEmpty,
                     "the timed out request landing late is still read as ours, not as the person's choice")

        // A repeated notification of the same source is one event, not two.
        var once = InputSourceMemoryMachine()
        _ = once.applicationActivated(key: chrome, currentSourceID: english,
                                      isSourceInstalled: allInstalled, at: 0)
        _ = once.inputSourceChanged(to: english, at: 0.1)
        let twice = once.inputSourceChanged(to: english, at: 0.2)
        suite.expect(twice.events.isEmpty && twice.actions.isEmpty,
                     "the same source reported twice is not a second change, so the observers cannot echo themselves")

        // A source id the machine will not store is refused at the door.
        let junk = once.inputSourceChanged(to: "Bad\nSource", at: 0.3)
        suite.expect(junk.actions.isEmpty, "a source id that cannot be stored is not stored")
    }

    // MARK: - A remembered source that is gone

    private static func unavailableSourceChecks(_ suite: TestSuite) {
        var machine = machineKnowingPair()
        // The input method has been removed from the system. Asking is impossible,
        // so the application adopts what is typing, once.
        var outcome = machine.applicationActivated(key: chrome, currentSourceID: english,
                                                  isSourceInstalled: { $0 == english }, at: 0)
        suite.expect(outcome.events == [.rememberedSourceUnavailable(key: chrome, sourceID: chinese)]
                && outcome.actions == [.save(key: chrome, sourceID: english)]
                && machine.preferences[chrome] == english,
                     "a removed input source is replaced by what is typing, and not asked for again")
        outcome = machine.applicationActivated(key: chrome, currentSourceID: english,
                                               isSourceInstalled: { $0 == english }, at: 1)
        suite.expect(outcome.events == [.alreadyCurrent(key: chrome, sourceID: english)]
                && outcome.actions.isEmpty,
                     "the second visit asks for nothing, so a removed source is not chased on every switch")
        // The other application's source is untouched by the first one's loss.
        suite.expect(machine.preferences[code] == english,
                     "one application's removed source does not disturb another's preference")
    }

    // MARK: - What is written, and what survives

    private static func persistenceChecks(_ suite: TestSuite) {
        var map = InputSourcePreferenceMap()
        map.set(sourceID: chinese, for: chrome)
        map.set(sourceID: english, for: code)
        guard let data = InputSourcePreferenceCodec.encode(map) else {
            suite.expect(false, "the remembered applications can be encoded")
            return
        }
        // A service recreated after a restart, and a Mac restarted, read the same
        // map and restore from it.
        var rebuilt = InputSourceMemoryMachine(preferences: InputSourcePreferenceCodec.decode(data))
        let outcome = rebuilt.applicationActivated(key: chrome, currentSourceID: english,
                                                   isSourceInstalled: allInstalled, at: 0)
        suite.expect(outcome.events.contains(.restoreRequested(key: chrome, sourceID: chinese, token: 1)),
                     "a service built from what was written restores the browser's input method, as the one that wrote it did")

        let round = InputSourcePreferenceCodec.decode(InputSourcePreferenceCodec.encode(map))
        suite.expect(round.keys == [chrome, code] && round[chrome] == chinese && round[code] == english,
                     "the order the applications were remembered in, and their sources, survive the round trip")

        // An application used again moves to the recent end, and the limit drops
        // the far end rather than the application in hand.
        var bounded = InputSourcePreferenceMap(limit: 3)
        for id in ["a", "b", "c"] { bounded.set(sourceID: english, for: "bundle:\(id)") }
        bounded.set(sourceID: english, for: "bundle:a")
        suite.expect(bounded.keys == ["bundle:b", "bundle:c", "bundle:a"],
                     "touching an application keeps it off the eviction list")
        bounded.set(sourceID: english, for: "bundle:d")
        suite.expect(bounded.count == 3 && bounded["bundle:b"] == nil && bounded["bundle:d"] == english,
                     "the limit drops the least recently used application, so a map cannot grow without bound")

        // What the reader cannot account for is dropped, never invented.
        let garbage = InputSourcePreferenceCodec.decode(Data("not json at all".utf8))
        suite.expect(garbage.isEmpty, "a value that is not the map yields an empty map, not a guess")
        let hostile = InputSourcePreferenceCodec.decode(
            Data(#"[{"app":"bundle:a","source":"ok"},{"app":"bundle:bad\nkey","source":"ok"},{"app":"bundle:c","source":""}]"#.utf8))
        suite.expect(hostile.keys == ["bundle:a"],
                     "a stored key or source that cannot be used is dropped on the way in")
        suite.expect(InputSourcePreferenceCodec.decode(nil).isEmpty
                && InputSourcePreferenceCodec.decode(Data()).isEmpty,
                     "no map at all is an empty map")
        let selfNamed = InputSourcePreferenceMap(entries: [
            InputSourcePreferenceMap.Entry(key: chrome, sourceID: chinese),
            InputSourcePreferenceMap.Entry(key: chrome, sourceID: english),
        ])
        suite.expect(selfNamed.count == 1 && selfNamed[chrome] == english,
                     "one application is stored once, with the source remembered last")
        suite.expect(InputSourceMemorySupport.shouldRun(featureInstalled: true, enabled: true,
                                                        sessionIsActive: true)
                && !InputSourceMemorySupport.shouldRun(featureInstalled: true, enabled: false,
                                                       sessionIsActive: true)
                && !InputSourceMemorySupport.shouldRun(featureInstalled: false, enabled: true,
                                                       sessionIsActive: true)
                && !InputSourceMemorySupport.shouldRun(featureInstalled: true, enabled: true,
                                                       sessionIsActive: false),
                     "the feature watches only when it is installed, switched on, and in a live session")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.inputSourceMemoryEnabled] as? Bool == false,
                     "per-application input source memory ships switched off, so nobody's keyboard moves by surprise")
    }

    // MARK: - The service's own obligations

    /// The service is AppKit, so its obligations are read where they are written:
    /// one observer per stream, removed on the way out, and no selection while
    /// the feature is off.
    private static func lifecycleChecks(_ suite: TestSuite) {
        func source(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
        let service = source("Sources/Vorssaint/Services/InputSourceMemory/InputSourceMemoryService.swift")
        suite.expect(!service.isEmpty, "the input source service's source can be read")
        suite.expect(service.contains("guard activationObserver == nil else { return }")
                && service.contains("guard inputSourceObserver == nil else { return }"),
                     "a stream is observed once, so a start cannot leave two observers behind")
        let stops = service.range(of: "func stop()").map { String(service[$0.lowerBound...]) } ?? ""
        suite.expect(stops.contains("removeObserver(activationObserver)")
                && stops.contains("removeObserver(inputSourceObserver)")
                && stops.contains("self.activationObserver = nil")
                && stops.contains("self.inputSourceObserver = nil"),
                     "stopping removes both observers and forgets them, so a restart cannot double them")
        suite.expect(service.contains("kTISNotifySelectedKeyboardInputSourceChanged")
                && service.contains("NSWorkspace.didActivateApplicationNotification"),
                     "the two streams the feature reads are the workspace's activation and the text server's change")
        suite.expect(service.contains("func stop()")
                && service.contains("syncWithPreferences") && service.contains("InputSourceMemorySupport.shouldRun"),
                     "the service starts and stops from the feature's own gate")
        suite.expect(service.contains("func stop()") && !service.contains("removeAll(forKey:"),
                     "switching the feature off never deletes what was remembered")
        suite.expect(service.contains("DispatchQueue.main.asyncAfter") && service.contains("func writeNow()"),
                     "the map is written once per burst of switching, not once per switch")
        suite.expect(service.contains("applicationActivated(bundleIdentifier: app.bundleIdentifier")
                && service.contains("bundlePath: app.bundleURL?.path"),
                     "the application's identity is taken from the activation notification, and only its strings are kept")
        suite.expect(service.contains("Bundle.main.bundleIdentifier") && service.contains("isSelf"),
                     "the app's own panels are not typed in, and are not given a preference")
        suite.expect(service.contains("InputSourceSelection.currentSourceID()")
                && service.contains("InputSourceSelection.select(sourceID:"),
                     "reading and selecting are the Text Input Source Service's, shared with the rest of the app")
        suite.expect(!service.contains("Process(") && !service.contains("/usr/bin/")
                && !service.contains("osascript"),
                     "no shell, no script, and no command-line tool is asked to move a keyboard")
        let settings = source("Sources/Vorssaint/UI/Settings/InputSourceMemorySettings.swift")
        suite.expect(settings.contains("DefaultsKey.inputSourceMemoryEnabled")
                && settings.contains("InputSourceMemoryService.shared.syncWithPreferences()"),
                     "the settings switch drives the feature's own start and stop")
        suite.expect(settings.contains("text.systemSwitchingNote"),
                     "the settings page names the system's own document switching, and does not touch it")
        let support = source("Sources/Vorssaint/Services/InputSourceMemory/InputSourceMemorySupport.swift")
        suite.expect(!support.contains("import AppKit") && !support.contains("import Carbon"),
                     "the machine is pure, so it is tested with no GUI, no keyboard, and no window server")
    }

    /// The words of the page, in every language the app speaks.
    private static func pageChecks(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.inputSourceMemory(language)
            suite.expect(!strings.name.isEmpty && !strings.caption.isEmpty
                    && !strings.watchingNow.isEmpty && !strings.nothingRemembered.isEmpty
                    && !strings.systemSwitchingNote.isEmpty,
                         "the page is worded in \(language.rawValue)")
            suite.expect(strings.applicationsRememberedFormat.contains("%d"),
                         "the count keeps its number in \(language.rawValue)")
            let visible = strings.name + strings.caption + strings.watchingNow
                + strings.nothingRemembered + strings.systemSwitchingNote
            suite.expect(!visible.contains("\u{2014}"),
                         "no em-dash in the visible words (\(language.rawValue))")
        }
        let feature = AppFeature.inputSourceMemory
        suite.expect(feature.group == .mouseKeyboard && feature.permissions.isEmpty
                && feature.enabledKeys == [DefaultsKey.inputSourceMemoryEnabled]
                && !feature.installedByDefault,
                     "the feature is in the keyboard group, asks nothing of macOS, is switched by one key, and ships off")
        suite.expect(FeaturePreset.allCases.allSatisfy { !$0.features.contains(feature) },
                     "no preset installs a feature that moves a person's keyboard by itself")
    }
}
