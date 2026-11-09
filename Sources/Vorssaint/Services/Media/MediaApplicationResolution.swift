// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin

// MARK: - What the rule is told

/// One bundle as the rule is told of it: the path, the identifier the system
/// answers for it, and whether it is really there to be launched. The live
/// side reads those from the disk, so the rule itself is decided apart from
/// the file system and is testable with a bundle named in a string.
struct ApplicationBundle: Equatable {
    let path: String
    let bundleIdentifier: String?
    /// The bundle exists, is a directory, and carries an Info.plist that names
    /// it. A path that is none of those is not a thing to launch.
    var isLaunchable = false
}

/// One process as the rule is told of it.
struct ApplicationProcess: Equatable {
    let pid: Int32
    let bundleIdentifier: String?
    /// The bundle the executable lives in: an `.app`, an `.xpc`, an `.appex`.
    let bundlePath: String?
    /// The executable's own path, which is what `libproc` reports.
    let executablePath: String?
    /// The person can switch to this process: a regular app. A helper answers
    /// to no window of its own and takes no activation, so bringing it forward
    /// shows nothing and launching it is what makes macOS complain.
    let isSwitchable: Bool
}

/// What a click on a player asks of the system.
enum MediaApplicationLaunch: Equatable {
    /// Open this application bundle. `pid` is the running instance to show
    /// first, when there is one; opening the bundle is what raises an app that
    /// is running and starts one that is not, in one ask.
    case open(path: String, pid: Int32?)
    /// Ask the process to come forward: a player that is not an app bundle at
    /// all, and has no bundle to open.
    case activate(pid: Int32)
    /// Nothing is asked. A click that does nothing is honest; a click that
    /// opens a helper service, or a dialog from the system, is not.
    case nothing
}

/// A player's application, as the rule found it, in the shape a card reads:
/// the bundle, the running instance, and the two things a card shows.
struct MediaApplication {
    let url: URL
    let running: NSRunningApplication?
    let name: String?
    let icon: NSImage?

    /// The name the bundle carries, for a player that is not running: the
    /// display name the Finder shows, and the bundle's own file name under it.
    static func bundleName(of url: URL) -> String? {
        let display = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let trimmed = display?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        let file = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return file.isEmpty ? nil : file
    }
}

// MARK: - The rule

/// Which application a media session belongs to, and what may be asked of it.
///
/// A media session names a process, and the process it names is not always
/// the application the person launched. Safari plays audio in WebKit's own
/// services, and the system reports the session as belonging to
/// `com.apple.WebKit.GPU`, whose bundle sits inside Safari's `XPCServices`
/// folder. A process number is handed out again when a process exits, so it
/// is not an identity either. Opening what the session names therefore opens a
/// helper service - and macOS answers with an error dialog - and raising what
/// the number names can raise a stranger.
///
/// The rule is general, not a list of players:
///
///   * an application bundle is the deepest thing a click may open, and a
///     bundle sitting in a helper directory is not one;
///   * the process named, and then the processes that own it, are asked in
///     turn for a bundle the person can switch to;
///   * a bundle identifier is believed only when the running process answers
///     to it, so a reused process number cannot raise a stranger;
///   * where nothing is believed, nothing is asked.
enum MediaApplicationIdentity {
    /// A bundle whose path runs through one of these folders is a helper of an
    /// application, not the application: XPC services, embedded apps, plug-ins,
    /// login items, frameworks, applets. Safari's WebKit services, Spotify's
    /// helpers, and an Electron app's helpers all live under these names.
    static let helperDirectories: [String] = [
        "XPCServices", "Helpers", "Helper", "PlugIns", "Plugins", "Extensions",
        "LoginItems", "Frameworks", "PrivateFrameworks", "Support",
        "applet_files", "Runtime", "Contents/Library/Services",
    ]

    /// WebKit's own processes own the media session of a web page, and macOS
    /// names them as its application. Their identifiers are named as well as
    /// their paths because a session reports the identifier and not the path,
    /// and it is the identifier that would be handed to LaunchServices.
    static let helperIdentifierPrefixes: [String] = ["com.apple.WebKit."]

    /// The application a path lives in: the deepest `.app` on the path that is
    /// not a helper of another application. Walking out of WebKit's `.xpc`
    /// arrives at Safari, and walking out of an app's `Helpers` folder arrives
    /// at the app that owns the helper inside it, which is the one the person
    /// launched and can switch to. Nil when nothing on the path is an
    /// application, as a bare executable in `/usr/bin` is not.
    static func applicationBundlePath(from path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        var components = URL(fileURLWithPath: path).standardizedFileURL.path
            .split(separator: "/").map(String.init)
        while let last = components.last {
            let candidate = "/" + components.joined(separator: "/")
            if last.hasSuffix(".app"), !isHelperPath(candidate) { return candidate }
            components.removeLast()
        }
        return nil
    }

    /// A path that ends in `.app` and does not run through a helper folder.
    static func isApplicationBundlePath(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        guard path.hasSuffix(".app") else { return false }
        return !isHelperPath(path)
    }

    /// Whether the path runs through a helper folder of an application. The
    /// folders are compared as whole path components, so an app named
    /// “Plugins.app” is not refused.
    static func isHelperPath(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        let components = URL(fileURLWithPath: path).standardizedFileURL.path
            .split(separator: "/").map { $0.lowercased() }
        for folder in helperDirectories {
            let words = folder.lowercased().split(separator: "/").map(String.init)
            guard !words.isEmpty, let first = words.first,
                  let start = components.firstIndex(of: first) else { continue }
            if words.count == 1 { return true }
            if start + words.count <= components.count,
               Array(components[start..<start + words.count]) == words { return true }
        }
        return false
    }

    /// An identifier that names a service of an app, and so is never a thing
    /// to launch. Known by prefix: the WebKit services are the ones macOS
    /// reports for web playback, and the paths catch the rest.
    static func isHelperIdentifier(_ identifier: String?) -> Bool {
        guard let identifier, !identifier.isEmpty else { return false }
        return helperIdentifierPrefixes.contains { identifier.lowercased().hasPrefix($0.lowercased()) }
    }

    /// The application of a session, from what the system reported.
    ///
    /// `processes` is the session's own process first and then the processes
    /// that own it, each as the system answers for it now - which is what
    /// answers pid reuse, since a number read after the exit names a process
    /// that has nothing to do with the song. `installed` is LaunchServices:
    /// what the machine would open for an identifier that is not running.
    static func resolve(sessionPID: Int32?, reportedBundleIdentifier: String?,
                        processes: [ApplicationProcess],
                        installed: (String) -> ApplicationBundle?) -> MediaApplicationLaunch {
        let wanted = normalizedIdentifier(reportedBundleIdentifier)
        let rejectsIdentity = wanted != nil && (isHelperIdentifier(wanted) || !isSwitchableIdentifier(wanted))
        var runningSession: ApplicationProcess?
        if let sessionPID, sessionPID > 0 {
            runningSession = processes.first { $0.pid == sessionPID }
        }
        // The session's process and its owners, in the order they were found:
        // the one the person launched, nearest first.
        for process in processes {
            guard process.pid > 0, let path = applicationBundlePath(from: process.bundlePath ?? process.executablePath),
                  isApplicationBundlePath(path) else { continue }
            if process.isSwitchable {
                // A process number is handed out again. When the session named
                // an application, the process raised must answer to it, or the
                // click would raise a stranger while the player stayed behind.
                if let wanted, !rejectsIdentity {
                    guard let identifier = normalizedIdentifier(process.bundleIdentifier),
                          identifier.caseInsensitiveCompare(wanted) == .orderedSame else { continue }
                }
                return .open(path: path, pid: process.pid)
            }
            // A helper that answers to the application the session names, and
            // has no owner above it that is an app: there is nothing to raise,
            // and its bundle is never opened.
            if let wanted, !rejectsIdentity,
               let identifier = normalizedIdentifier(process.bundleIdentifier),
               identifier.caseInsensitiveCompare(wanted) == .orderedSame {
                break
            }
        }
        // Nothing running may be raised. What the machine would open for the
        // identifier the session reported is asked for next, and only when the
        // identifier names an application.
        if let wanted, !isHelperIdentifier(wanted) {
            if let bundle = installed(wanted), bundle.isLaunchable,
               isApplicationBundlePath(bundle.path) {
                return .open(path: bundle.path, pid: nil)
            }
            return .nothing
        }
        // A player that is not an app bundle at all - a command-line player,
        // say - is raised the only way it can be, and only when it is running
        // and can be switched to.
        if let runningSession, runningSession.isSwitchable,
           applicationBundlePath(from: runningSession.bundlePath ?? runningSession.executablePath) == nil {
            return .activate(pid: runningSession.pid)
        }
        return .nothing
    }

    /// An identifier shaped like one, trimmed of what a session's reply can
    /// carry around it. A helper identifier is not shaped wrongly, so it is
    /// kept and answered for on its own.
    private static func normalizedIdentifier(_ identifier: String?) -> String? {
        let trimmed = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty, trimmed.count <= 255,
              !trimmed.contains(where: { $0.isNewline }) else { return nil }
        return trimmed
    }

    /// A name an application is known by: at least one dot, and no spaces.
    /// A session sometimes reports a display name, a path, or a number, and
    /// none of them is something to ask LaunchServices for.
    static func isSwitchableIdentifier(_ identifier: String?) -> Bool {
        guard let identifier, identifier.contains("."), !identifier.contains(" "),
              !identifier.hasPrefix("/") else { return false }
        return identifier.split(separator: ".").allSatisfy {
            !$0.isEmpty && $0.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-" || character == "_"
            }
        }
    }
}

// MARK: - The system, asked

/// The live side of the rule: the processes read from the system, LaunchServices
/// asked what it would open, and the application the click ends up raising.
enum MediaApplicationOpener {
    /// How far out of a helper the chain is walked. A WebKit service is two
    /// steps from its browser and a sandbox helper is one; the limit stops a
    /// chain that reaches `launchd` from going on, and stops a cycle.
    static let maximumGenerations = 6

    /// One process as the system answers for it now.
    static func process(_ pid: Int32) -> ApplicationProcess? {
        guard pid > 0 else { return nil }
        let running = NSRunningApplication(processIdentifier: pid_t(pid))
        let bundleURL = running?.bundleURL?.standardizedFileURL.path
        return ApplicationProcess(
            pid: pid,
            bundleIdentifier: running?.bundleIdentifier,
            bundlePath: bundleURL,
            executablePath: executablePath(of: pid) ?? running?.executableURL?.standardizedFileURL.path,
            isSwitchable: running?.activationPolicy == .regular)
    }

    /// The session's process, then the processes responsible for it, nearest
    /// first. The responsibility API is what groups a browser's audio helper
    /// with the browser; its answer is followed by the kernel's parent, so a
    /// helper that answers for itself is still walked out of.
    static func chain(from pid: Int32, limit: Int = maximumGenerations) -> [ApplicationProcess] {
        var chain: [ApplicationProcess] = []
        var seen: Set<Int32> = []
        var current: Int32? = pid
        while let step = current, chain.count < limit, !seen.contains(step) {
            seen.insert(step)
            if let process = self.process(step) { chain.append(process) }
            current = nextOwner(after: step, seen: seen)
        }
        return chain
    }

    /// The next process out: the responsible one, then the kernel's parent.
    private static func nextOwner(after pid: Int32, seen: Set<Int32>) -> Int32? {
        for candidate in [ResponsibleProcess.owner(of: pid_t(pid)), parent(of: pid)] {
            if candidate > 0, candidate != pid, !seen.contains(candidate) { return candidate }
        }
        return nil
    }

    private static func parent(of pid: Int32) -> Int32 {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid_t(pid), PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
        return Int32(bitPattern: info.pbi_ppid)
    }

    private static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid_t(pid), &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : path
    }

    /// What LaunchServices would open for an identifier, as the rule asks: the
    /// path, the identifier, and whether the bundle is there to be opened.
    static func installed(_ identifier: String) -> ApplicationBundle? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return nil }
        return bundle(at: url)
    }

    /// A bundle as the rule reads the disk: a directory with an Info.plist
    /// that names it. An XPC service answers that shape too, which is why the
    /// rule reads its path as well.
    static func bundle(at url: URL) -> ApplicationBundle {
        let path = url.standardizedFileURL.path
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        let bundle = Bundle(url: url.standardizedFileURL)
        return ApplicationBundle(path: path,
                                 bundleIdentifier: bundle?.bundleIdentifier,
                                 isLaunchable: exists && isDirectory.boolValue
                                     && bundle?.bundleIdentifier != nil)
    }

    /// The click's work, done: the application the song belongs to comes to
    /// the front, running or not.
    ///
    /// The island is a panel that never becomes the active app, and a running
    /// app is not reliably raised by asking it directly from the background -
    /// the request is honoured when the system feels like it, which is the
    /// click that works on Tuesday and not on Wednesday. Opening the app's own
    /// bundle through the workspace is the way that works from the background,
    /// and it raises an app already running and starts one that is not, in one
    /// ask. Where the rule refuses - a helper service, a stale process, a
    /// player no one can name - the click is quiet and the song keeps playing.
    static func open(pid: Int, bundleIdentifier: String) {
        let sessionPID = pid > 0 ? Int32(pid) : nil
        let chain = sessionPID.flatMap { chain(from: $0) } ?? []
        switch MediaApplicationIdentity.resolve(sessionPID: sessionPID,
                                                reportedBundleIdentifier: bundleIdentifier,
                                                processes: chain,
                                                installed: installed) {
        case .open(let path, let runningPID):
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let running = runningPID.flatMap { NSRunningApplication(processIdentifier: pid_t($0)) }
            // A running app is raised, not relaunched: the request goes to the
            // instance the person already has, whose windows and queue stay.
            if let running, running.activationPolicy == .regular {
                bringForward(running, bundle: url)
            } else {
                launch(url)
            }
        case .activate(let pid):
            if let running = NSRunningApplication(processIdentifier: pid_t(pid)) {
                bringForward(running)
            }
        case .nothing:
            break
        }
    }

    /// The application of a session, as the rule finds it: the running one
    /// where the session belongs to it, the installed one where it has quit,
    /// and nothing where no application is believed. The name and the icon a
    /// card shows are read from this, so a card never offers the name of a
    /// helper service as the app that plays.
    static func application(pid: Int?, bundleIdentifier: String?) -> (running: NSRunningApplication?, url: URL)? {
        let sessionPID = pid.flatMap { $0 > 0 ? Int32($0) : nil }
        let chain = sessionPID.flatMap { chain(from: $0) } ?? []
        guard case .open(let path, let runningPID) = MediaApplicationIdentity.resolve(
            sessionPID: sessionPID, reportedBundleIdentifier: bundleIdentifier,
            processes: chain, installed: installed) else { return nil }
        let url = URL(fileURLWithPath: path)
        let running = runningPID.flatMap { NSRunningApplication(processIdentifier: pid_t($0)) }
            ?? runningInstance(of: url)
        return (running, url)
    }

    /// The running instance of a bundle, for a card's name and icon, where the
    /// bundle is the one the rule chose.
    private static func runningInstance(of url: URL) -> NSRunningApplication? {
        let bundle = Bundle(url: url)
        guard let identifier = bundle?.bundleIdentifier, !MediaApplicationIdentity.isHelperIdentifier(identifier)
        else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { !$0.isTerminated })
    }

    /// An app the person can switch to, brought forward: shown when it is
    /// hidden, given what activation Vorssaint holds, and asked for all its
    /// windows. A player that keeps playing with its window closed gets one
    /// shown again, the way a Dock click does; activation alone leaves nothing
    /// to see. A bundle that is not an application is never opened.
    private static func bringForward(_ application: NSRunningApplication, bundle: URL?) {
        let url = bundle ?? application.bundleURL
        // Read before the unhide below: a hidden player's windows come back with it.
        let showsNoWindow = !application.isHidden
            && application.activationPolicy == .regular
            && !hasWindowOnScreen(pid: Int32(application.processIdentifier))
        if application.isHidden { application.unhide() }
        ActivationHandoff.yield(to: application)
        if !application.activate(from: NSRunningApplication.current, options: [.activateAllWindows]) {
            application.activate(options: [.activateAllWindows])
        }
        if showsNoWindow, let url, MediaApplicationIdentity.isApplicationBundlePath(url.standardizedFileURL.path) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            configuration.promptsUserIfNeeded = false
            NSWorkspace.shared.openApplication(at: url.standardizedFileURL, configuration: configuration)
        }
    }

    /// Whether the player has a window on the current Space. One on another
    /// Space reads as none, and the reopen that follows is harmless there.
    static func hasWindowOnScreen(pid: Int32) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                 kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid_t(pid)
                && ($0[kCGWindowLayer as String] as? Int) == 0
        }
    }

    /// A player that is running, answers to no application bundle of its own,
    /// and can be switched to: raised the only way it can be - asked to come
    /// forward, and shown if it was hidden.
    private static func bringForward(_ application: NSRunningApplication) {
        application.unhide()
        application.activate()
    }

    /// The last gate, beside the rule's own: a bundle that is not an
    /// application is never handed to the workspace. Opening an XPC service is
    /// what made macOS answer a card click with an error dialog.
    private static func launch(_ url: URL) {
        guard MediaApplicationIdentity.isApplicationBundlePath(url.standardizedFileURL.path) else { return }
        guard MediaApplicationIdentity.isApplicationBundlePath(url.standardizedFileURL.path) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }
}
