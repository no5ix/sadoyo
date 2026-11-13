# 0007. Per-application input source memory is a pure machine over bundle identity

- Status: accepted
- Date: 2026-07-29
- Context: macOS keeps one keyboard input source for the whole system, and a
  person typing in two languages pays for that on every application switch. The
  system ships one related behaviour, "Automatically switch to a document's input
  source", which is per *document* and is the user's own setting. Nothing in
  macOS remembers a source per *application*, and the Text Input Source Service
  that can select one (`TISCopyCurrentKeyboardInputSource`,
  `TISCreateInputSourceList`, `TISSelectInputSource`) posts
  `kTISNotifySelectedKeyboardInputSourceChanged` when the source changes and says
  only *that* it changed, never *who asked*. A feature that switches sources on
  `NSWorkspace.didActivateApplicationNotification` therefore creates its own
  change notifications, and a naive implementation reads those back as the user's
  choices: switch into an editor and restore its plain layout, and the browser
  you left is rewritten with the editor's layout. A second hazard is that a
  notification for a request the user has already abandoned arrives while a third
  application is frontmost.
- Decision: Per-application input source memory is a pure decision machine, and
  the service is allowed to do nothing but watch, read, select, and store.
  - **Identity is the bundle identifier.** `InputSourceMemorySupport.applicationKey`
    returns `bundle:<id>`; a process with no bundle identifier is keyed
    `path:<bundle path>`, a prefix no bundle identifier can carry, so the two
    namespaces cannot merge applications. An application with neither is keyed
    `nil`, and the machine switches nothing and remembers nothing for it. Window
    titles, document names, and display names are never used and never stored.
  - **Sources are stored by their stable TIS ids**, never by the localized name
    the Input menu shows.
  - **One restoration in flight, with a token.** `InputSourceMemoryMachine` keeps
    `pending (key, sourceID, token, requestedAt)`. Activating another application
    cancels it and records it in `superseded` for a grace period longer than the
    timeout it was given.
  - **Attribution is conservative.** A change notification equal to the pending
    request's source is `restored` for the request's application, and the
    preference of no other application is touched. A change matching a
    *superseded* request is `lateAutomaticChange` and writes nothing. A change
    matching neither is `manualChange`, written to the frontmost application, and
    written nowhere when the frontmost application is not identifiable. An
    uncertain application is never given a preference.
  - **Nothing is repaired into a switch.** A remembered source that is no longer
    installed is replaced by the source that is typing, once, and not asked for
    again. A refused `TISSelectInputSource` and a restoration whose notification
    never arrives leave the stored preference alone, so the next visit tries
    again. A repeated notification of the same source is one event.
  - **The map is ordered and bounded.** `InputSourcePreferenceMap` keeps
    `(key, sourceID)` pairs in the order last remembered, capped at 300 with
    least-recently-used eviction. `InputSourcePreferenceCodec` writes an array of
    pairs (the order is stored, not inferred) under one `UserDefaults` key,
    dropping any pair whose key or source cannot be used. Writes are debounced, so
    a burst of application switches is one write.
  - **No permission is asked.** Selecting an input source is a public Text Input
    Source Service call and the two notifications are the workspace's and the text
    server's, so no Accessibility, Input Monitoring, Automation, or Screen
    Recording grant is requested. The feature is in the Features hub, ships
    uninstalled, and its enable key defaults to off, so no keyboard moves by
    surprise.
  - **The system's own per-document switching is named and never touched.** The
    settings page explains it; the feature neither reads nor changes that
    setting, and no macOS preference is written.
- Consequences:
  - The whole of the risky logic is testable with no GUI, no real keyboard, and no
    window server: `Tests/InputSourceMemoryTests.swift` drives the machine with
    application keys, source ids, and injected times, and asserts the events and
    the actions it was told to take.
  - What the machine cannot know stays a limitation, stated in the settings page
    and here. macOS gives no actor with a change notification, so a change that
    is not ours and not a superseded one is *assumed* the user's, for the
    frontmost application. Concretely: if macOS's per-document switching, another
    application, or a script changes the source while an application is frontmost,
    that application is credited with the choice. It is the one attribution the
    platform permits, and it never writes to an application that is not frontmost.
  - With both features on, macOS switches by document and Sadoyo restores by
    application; the source that ends up typing is the last one applied, which is
    Sadoyo's on an application switch. A person who wants the system's behaviour
    alone should leave this feature off; a person who wants predictable per-app
    behaviour should leave the system's option off. Sadoyo will not decide for
    them.
  - Input sources the user removes are adopted away, so a preference for a source
    that returns to the system is not remembered forever. An application moved
    on disk loses its `path:` key, which is the accepted cost of keying
    identifier-less processes by a stable path.
- Related code: `Sources/Vorssaint/Services/InputSourceMemory/InputSourceMemorySupport.swift`,
  `Sources/Vorssaint/Services/InputSourceMemory/InputSourceMemoryService.swift`,
  `Sources/Vorssaint/Core/InputSourceMemoryStrings.swift`,
  `Sources/Vorssaint/UI/Settings/InputSourceMemorySettings.swift`,
  `Sources/Vorssaint/Core/InputSourceSelection.swift`,
  `Tests/InputSourceMemoryTests.swift` (`./build.sh --test-suite=input-source`).
