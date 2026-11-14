// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

/// With the island on every display, each other display shows a copy of
/// what it shows closed. The copies' bodies come from production; displays,
/// windows, Spaces and preferences are controlled boundaries.
enum NotchMirrorContract {
    final class NSScreen: Equatable {
        static var screens: [NSScreen] = []
        static var screensHaveSeparateSpaces = true
        static var withMenuBar: NSScreen? { screens.first }
        let notchDisplayID: CGDirectDisplayID
        let frame: CGRect
        let notched: Bool
        init(_ id: CGDirectDisplayID, _ frame: CGRect, notched: Bool = false) {
            notchDisplayID = id
            self.frame = frame
            self.notched = notched
        }
        static func == (left: NSScreen, right: NSScreen) -> Bool { left === right }
    }
    /// AppKit reports the pointer's moves, and a copy's window reports the pointer
    /// entering and leaving. The test says where the pointer is, and catches the
    /// moves a copy asks to follow.
    final class NSEvent {
        typealias EventTypeMask = AppKit.NSEvent.EventTypeMask
        static var mouseLocation = CGPoint.zero
        static var global: [Int: (AppKit.NSEvent) -> Void] = [:]
        static var local: [Int: (AppKit.NSEvent) -> AppKit.NSEvent?] = [:]
        static var nextID = 0
        static func addGlobalMonitorForEvents(matching: EventTypeMask,
                                              handler: @escaping (AppKit.NSEvent) -> Void) -> Any? {
            nextID += 1; global[nextID] = handler; return nextID
        }
        static func addLocalMonitorForEvents(matching: EventTypeMask,
                                             handler: @escaping (AppKit.NSEvent) -> AppKit.NSEvent?) -> Any? {
            nextID += 1; local[nextID] = handler; return nextID
        }
        /// Report a pointer's move to every monitor registered for moves, as AppKit
        /// hands one move to every monitor that asked for that kind of event: the
        /// island's own pair, and the pair armed for the copies, all answer the same
        /// move. Order is registration order, which is the order the island's windows
        /// asked in.
        static func reportMoveToEveryMonitor() {
            reportMove(to: Array(global.keys))
        }
        static func removeMonitor(_ token: Any) { global[token as! Int] = nil; local[token as! Int] = nil }
        /// Report a pointer's move to the monitors asked to follow it, as AppKit
        /// reports the moves a window stops receiving. Only the global monitor
        /// answers: the pointer's moves over the rest of the system are what the
        /// islands are read from, and a move over one of the island's own windows
        /// is answered by the local monitor of the same pair. The event is never
        /// read - production's handlers ask where the pointer is of the fixture's
        /// `mouseLocation`, and a real AppKit mouse event cannot be built for a
        /// process with no window.
        static func reportMove(to monitors: [Any]) {
            let event = AppKit.NSEvent()
            for case let token as Int in monitors where global[token] != nil {
                global[token]?(event)
            }
        }
    }
    enum NotchContentTransition { case none, replace }
    final class Panel {
        var isVisible = false
        var sharingType = NSWindow.SharingType.readOnly
        var orders = 0
        var orderedBelow = 0
        var windowNumber = 1
        var acceptsKeyFocus = false
        func orderFrontRegardless() { isVisible = true; orders += 1 }
        func order(_ place: NSWindow.OrderingMode, relativeTo otherWindow: Int) {
            isVisible = true
            orders += 1
            if place == .below { orderedBelow += 1 }
        }
    }
    final class Host {
        let panel = Panel()
        var presented: [(size: CGSize, geometry: NotchGeometry, animated: Bool, transition: NotchContentTransition)] = []
        var hides = 0, closes = 0
        var outline: (enabled: Bool, color: NSColor)?
        var activationRect = CGRect.zero
        var activationTitle = ""
        var activate: (() -> Void)?
        var willPress: (() -> Void)?
        var settling = false
        var settled: [() -> Void] = []
        /// The copy's own hover area, and the handler that answers its pointer.
        var hoverArea: CGRect?
        var hoverHandler: ((Bool) -> Void)?
        func setHoverArea(_ area: CGRect?) { hoverArea = area }
        func setHoverHandler(_ handler: @escaping (Bool) -> Void) { hoverHandler = handler }
        func present(size: CGSize, geometry: NotchGeometry, animated: Bool, transitionContent: NotchContentTransition) {
            presented.append((size, geometry, animated, transitionContent))
        }
        func hide(animated: Bool) { hides += 1; panel.isVisible = false }
        func close() { closes += 1; panel.isVisible = false }
        func setOutline(enabled: Bool, color: NSColor) { outline = (enabled, color) }
        func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void, activate: @escaping () -> Void) {
            activationRect = rect
            activationTitle = title
            self.willPress = willPress
            self.activate = activate
        }
        func whenSettled(_ action: @escaping () -> Void) {
            if settling { settled.append(action) } else { action() }
        }
    }
    /// A display's own island, as the service keeps its copies: the window built
    /// for that display, the pointer's place on that display, the opening its
    /// pointer asked for, and whether it draws the island's page. The test says
    /// where the pointer is, and runs the deadline for itself.
    final class Mirror {
        let id: CGDirectDisplayID
        let host: Host
        let model: NotchMirrorModel
        var inside = false
        var hover = NotchHoverState()
        var hoverWork: DispatchWorkItem?
        var lastSize: CGSize?
        var over = false
        init(id: CGDirectDisplayID, host: Host, model: NotchMirrorModel) {
            self.id = id
            self.host = host
            self.model = model
        }
        func cancelHoverWork() { hoverWork?.cancel(); hoverWork = nil }
        /// The pointer's deadline for this display, run when the test says it is up.
        func runHoverWork() { hoverWork?.perform(); hoverWork = nil }
    }
    enum SpaceWindowBridge {
        static var fullscreen: Set<CGDirectDisplayID> = []
        struct Topology {
            func isFullscreen(on id: CGDirectDisplayID, separateSpaces: Bool) -> Bool { SpaceWindowBridge.fullscreen.contains(id) }
        }
        static func topology() -> Topology? { Topology() }
    }
    enum NotchAppFullscreen {
        static var covered: Set<CGDirectDisplayID> = []
        static func coveredDisplays() -> Set<CGDirectDisplayID> { covered }
    }

    class State {
        var showsOnAllDisplays = true, running = true, suspended = false
        var windowHost: Host? = Host()
        var mirrorHeldForArrival: CGDirectDisplayID?
        var displayID: CGDirectDisplayID? = 1
        var mirrors: [CGDirectDisplayID: Mirror] = [:]
        /// The moves followed for all the island's windows at once, as the service
        /// arms them: the test reports a move by handing the token's handler its own.
        var pointerWatchMonitors: [Any] = []
        var fullscreenDisplays: Set<CGDirectDisplayID> = []
        var compactActivity: NotchCompactActivity?
        var compactCompanion: NotchCompactActivity?
        var idleContent = NotchIdleContent.none
        var mascotVisible = false
        func mascotShows(on geometry: NotchGeometry) -> Bool {
            mascotVisible && (geometry.floats || geometry.restingWingWidth > 0)
        }
        var expanded = false, peeking = false, canFollowPointer = true
        var hidesUntilHover = false, hiddenShowsActivity = false, coversMenus = true, showsInCaptures = true
        var outlineEnabled = false, hidesInFullscreen = false
        let openTitle = "Open"
        var opened = 0, collapses = 0, countdownOpenings = 0
        var moves: [CGDirectDisplayID] = []
        var made: [Host] = []

        /// A built-in display with a camera housing, or an external one with a capsule.
        func baseGeometry(for screen: NSScreen) -> NotchGeometry {
            NotchGeometry(screen: screen.frame, safeAreaTop: screen.notched ? 32 : 0,
                          cameraWidth: screen.notched ? 185 : 0, menuBarHeight: screen.notched ? 32 : 24,
                          silhouette: .capsule)
        }
        /// Each activity's capsule a fixed width wider than the bare one, so sizes are traceable.
        func capsuleStripSize(for activity: NotchCompactActivity, companion: NotchCompactActivity?,
                              geometry: NotchGeometry?) -> CGSize {
            let geometry = geometry!
            return CGSize(width: geometry.restingSize(showsContent: false).width + 40, height: geometry.stripHeight)
        }
        func compactGeometry(for activity: NotchCompactActivity?, companion: NotchCompactActivity?,
                             base: NotchGeometry?) -> NotchGeometry {
            base!.compactTimerGeometry(showsDownloads: false, wing: 60)
        }
        func makeMirror(id: CGDirectDisplayID, geometry: NotchGeometry, size: CGSize) -> Mirror {
            let host = Host()
            made.append(host)
            return Mirror(id: id, host: host, model: NotchMirrorModel(displayID: id, geometry: geometry, size: size))
        }
        /// Which display draws the island's page, as production keeps it: one
        /// display at a time, and no window that moves.
        var expansion = NotchDisplayExpansion()
        var expandedGeometry: NotchGeometry {
            let screen = NSScreen.screens.first { $0.notchDisplayID == expansion.owner } ?? NSScreen.screens[0]
            return baseGeometry(for: screen)
        }
        var expandedSize: CGSize { expandedGeometry.expanded }
        /// A copy's pointer's place, as the test says it is.
        func pointerOverMirror(_ mirror: Mirror) -> Bool { mirror.over }
        var hoverOpeningEnabled = true
        var hoverOpensThroughNotice = true
        /// What a hover asks for, as the person chose it: the whole dashboard, or
        /// the page's name. The copy answers the same choice.
        var hoverExpands = true
        /// The pause a copy's pointer leaves before its page closes.
        var mirrorCloseDelay: TimeInterval = 0.4
        /// What the island's close asks about, answered for the test.
        var pinned = false, heldDrag = false, keepsWorkingSurface = false, captureControlsActive = false
        var assistiveKeyboardHoldsPointer = false
        /// Whether the open page was asked for by a pointer, and so closes when
        /// that pointer leaves.
        var openedByHover = false
        var hiddenUntilHover = false
        var notice: NotchNotice?
        func provideHapticFeedback() {}
        var collapseTitle = "Collapse"
        func collapse() {
            collapses += 1; expanded = false; peeking = false; expansion.closed()
            // Production's collapse ends the pointer's claim on the page: the page
            // is closed, so no navigation from it can carry that claim anywhere.
            openedByHover = false
            // Production's collapse asks for the pointer's moves no more: the page
            // is closed everywhere, so no copy has a hover left to keep it.
            pointerWatchMonitors.forEach(NSEvent.removeMonitor)
            pointerWatchMonitors.removeAll()
        }
        func open() { opened += 1; expanded = true; expansion.asking(toOpen: displayID ?? 0) }
        func open(takeFocus: Bool, on display: CGDirectDisplayID?) {
            opened += 1
            // The production rule, asked once at the opening: the act that opened
            // the island owns the page, and a page reached from inside an island
            // the pointer opened keeps the pointer's claim, whatever the page is.
            openedByHover = NotchSupport.openedByHover(opening: !expanded,
                                                       wasOpenedByHover: openedByHover,
                                                       takeFocus: takeFocus)
            expanded = true
            expansion.asking(toOpen: display ?? (displayID ?? 0))
        }
        func open(takeFocus: Bool, wholeDashboard: Bool, on display: CGDirectDisplayID?) {
            opened += 1
            openedByHover = NotchSupport.openedByHover(opening: !expanded,
                                                       wasOpenedByHover: openedByHover,
                                                       takeFocus: takeFocus)
            expanded = true
            wholeDashboardAsked = wholeDashboard
            expansion.asking(toOpen: display ?? (displayID ?? 0))
        }
        var wholeDashboardAsked = false
        func openCountdownEvent(on display: CGDirectDisplayID? = nil) {
            countdownOpenings += 1
            expanded = true
            expansion.asking(toOpen: display ?? (displayID ?? 0))
        }
        func move(to screen: NSScreen) { displayID = screen.notchDisplayID; moves.append(screen.notchDisplayID) }
    }

    static func run(_ suite: TestSuite) {
        defer {
            NSScreen.screens = []
            NSScreen.screensHaveSeparateSpaces = true
            SpaceWindowBridge.fullscreen = []
            NotchAppFullscreen.covered = []
        }
        let builtIn = NSScreen(1, CGRect(x: 0, y: 0, width: 1470, height: 956), notched: true)
        let external = NSScreen(2, CGRect(x: 1470, y: -86, width: 1920, height: 1080))
        NSScreen.screens = [builtIn, external]
        NSScreen.screensHaveSeparateSpaces = false

        let service = Service()
        service.syncMirrors()
        let capsule = service.mirrors[2]
        suite.expect(service.mirrors.count == 1 && service.mirrors[1] == nil && capsule?.model.shown == true
                     && capsule?.host.presented.count == 1 && capsule?.host.presented.first?.animated == false
                     && capsule?.host.panel.isVisible == true && capsule?.model.activity == nil,
                     "every display but the island's own shows a copy, at once")
        let external2 = service.baseGeometry(for: external)
        suite.expect(capsule?.model.geometry.floats == true && capsule?.model.geometry.screen == external.frame
                     && capsule?.model.size == external2.restingSize(showsContent: false)
                     && capsule?.host.activationRect == CGRect(origin: .zero, size: capsule?.model.size ?? .zero),
                     "a copy draws its own display's island, a capsule at rest there, and all of it takes a click")
        service.syncMirrors()
        suite.expect(capsule?.host.presented.count == 1 && service.made.count == 1,
                     "an island that changes nothing a copy shows leaves the copy as it is")

        service.outlineEnabled = true
        service.compactActivity = .timer
        service.syncMirrors()
        suite.expect(capsule?.host.presented.count == 2 && capsule?.host.presented.last?.transition == .replace
                     && capsule?.host.presented.last?.animated == true
                     && capsule?.model.size.width == external2.restingSize(showsContent: false).width + 40
                     && capsule?.host.outline?.enabled == true && capsule?.host.outline?.color == .systemOrange,
                     "a timer starting reshapes each copy as the island does, in the timer's outline")

        let trading = Service()
        trading.syncMirrors()
        let kept = trading.mirrors[2]
        trading.windowHost?.panel.isVisible = true
        trading.mirrorHeldForArrival = 2
        trading.displayID = 2
        trading.syncMirrors()
        let underneath = trading.mirrors[1]
        suite.expect(kept?.model.shown == true && kept?.host.hides == 0
                     && underneath?.model.shown == true && underneath?.host.panel.orderedBelow == 1,
                     "while the island moves, the copy it is joining stays up and the one it leaves sits underneath")
        trading.mirrorHeldForArrival = nil
        trading.syncMirrors()
        suite.expect(kept?.model.shown == false && kept?.host.hides == 1 && underneath?.model.shown == true,
                     "the copy steps aside once the island has arrived on its display")
        arrivalVisibilityContracts(suite)

        // The island follows the pointer to the external display.
        service.displayID = 2
        service.syncMirrors()
        let notch = service.mirrors[1]
        var builtInBase = service.baseGeometry(for: builtIn)
        builtInBase.compactSideRoom = NotchMenuBarLayout.sideRoom(screen: builtInBase.screen, cameraWidth: builtInBase.cameraWidth,
                                                                  barHeight: builtInBase.menuBarHeight, occupied: [])
        let strip = service.compactGeometry(for: .timer, companion: nil, base: builtInBase)
        suite.expect(capsule?.model.shown == false && capsule?.host.hides == 1 && capsule?.host.panel.isVisible == false
                     && notch?.model.shown == true && notch?.model.geometry.isNotched == true
                     && notch?.model.strip == strip && notch?.model.size == strip.compactActivitySize
                     && notch?.host.presented.last?.animated == false,
                     "the copy steps aside where the island arrives and one appears where it left, drawn for the camera")
        suite.expect(notch?.model.geometry.compactSideRoom == builtInBase.compactSideRoom,
                     "an island that may cover menus gives its copy the room of an empty bar")

        service.hidesUntilHover = true
        service.syncMirrors()
        suite.expect(notch?.model.shown == false && notch?.host.hides == 1,
                     "an island hidden until the pointer reaches it hides its copies too")
        service.hidesUntilHover = false
        service.syncMirrors()
        suite.expect(notch?.model.shown == true, "a copy returns with the island at rest")

        service.hidesInFullscreen = true
        SpaceWindowBridge.fullscreen = [1]
        service.updateFullscreenDisplays()
        service.syncMirrors()
        suite.expect(service.fullscreenDisplays == [1] && notch?.model.shown == false && notch?.host.hides == 2,
                     "a copy leaves a display in full screen when the island hides there")
        service.hidesInFullscreen = false
        service.updateFullscreenDisplays()
        suite.expect(service.fullscreenDisplays.isEmpty, "only the choice to hide in full screen reads Spaces")
        service.syncMirrors()
        suite.expect(notch?.model.shown == true && notch?.host.presented.last?.animated == false,
                     "leaving full screen shows the copy again at once")

        // Set to show activity, a hidden island's copies draw the activity it
        // shows, and go with it once nothing runs.
        service.hidesUntilHover = true
        service.syncMirrors()
        service.hiddenShowsActivity = true
        service.syncMirrors()
        suite.expect(notch?.model.shown == true && notch?.model.activity == .timer && notch?.host.panel.isVisible == true,
                     "copies of a hidden island set to show activity draw the activity it shows")
        service.compactActivity = nil
        service.syncMirrors()
        suite.expect(notch?.model.shown == false, "the copies of a hidden island go once its activity ends")
        service.compactActivity = .timer
        service.hiddenShowsActivity = false
        service.hidesUntilHover = false
        service.syncMirrors()

        // Displays with their own menu bars and menus the island must not cover.
        NSScreen.screensHaveSeparateSpaces = true
        service.coversMenus = false
        service.displayID = 1
        service.syncMirrors()
        suite.expect(service.mirrors[2]?.model.shown == false,
                     "a capsule never covers menus it cannot measure on another display")
        service.displayID = 2
        service.syncMirrors()
        suite.expect(service.mirrors[1]?.model.shown == true && service.mirrors[1]?.model.geometry.compactSideRoom == nil,
                     "a copy on a camera keeps the camera covered without wings")
        service.coversMenus = true
        NSScreen.screensHaveSeparateSpaces = false

        // The companion rests in each copy too, beside that display's camera.
        service.displayID = 2
        service.compactActivity = nil
        service.mascotVisible = true
        service.syncMirrors()
        suite.expect(service.mirrors[1]?.model.size == service.mirrors[1]?.model.geometry.collapsed
                     && (service.mirrors[1]?.model.size.width ?? 0) > builtInBase.cameraWidth,
                     "a copy beside a camera opens its wings for the resting companion")
        service.mascotVisible = false
        service.syncMirrors()

        // A click on a copy opens the page on that copy's display, and the page
        // leaves the display that carried it. No window moves, and no island
        // changes the display it was built for.
        // Production's syncMirrors wires a copy's hover to that copy; the fixture's
        // makeMirror builds the window, so the same production answer is wired here.
        for (id, copy) in service.mirrors {
            copy.host.setHoverHandler { [weak service] entered in service?.mirrorHover(id, entered: entered) }
        }
        service.displayID = 2
        service.expansion.asking(toOpen: 2)
        service.expanded = true
        service.syncMirrors()
        let closedBefore = service.collapses
        service.mirrors[1]?.over = true
        service.mirrors[1]?.host.activate?()
        service.syncMirrors()
        suite.expect(service.expanded && service.expansion.owner == 1 && service.displayID == 2,
                     "clicking a copy opens the page there, and the island keeps its own display")
        suite.expect(service.mirrors[1]?.model.expanded == true
                     && service.mirrors[1]?.model.geometry.screen == builtIn.frame,
                     "the copy that was opened draws the page, measured for its own display")
        suite.expect(service.mirrors[1]?.host.activationTitle == service.collapseTitle,
                     "its header is the one that closes the page")
        // The page's own copy closes at a second click, as the island's header does.
        service.mirrors[1]?.host.activate?()
        suite.expect(service.collapses == closedBefore + 1 && !service.expanded && service.expansion.owner == nil,
                     "a click on the display that carries the page closes it")
        service.syncMirrors()
        // A deliberate hover opens the copy's display at the chosen delay, and a
        // pointer that has not stayed there opens nothing.
        service.mirrors[1]?.over = true
        service.mirrors[1]?.host.hoverHandler?(true)
        suite.expect(service.mirrors[1]?.hoverWork != nil && !service.expanded,
                     "a hover on a copy waits out the chosen delay")
        service.mirrors[1]?.runHoverWork()
        suite.expect(service.expanded && service.expansion.owner == 1, "a hover past the delay opens that display")
        service.collapse()
        service.syncMirrors()
        service.mirrors[1]?.over = false
        service.mirrors[1]?.host.hoverHandler?(true)
        suite.expect(service.mirrors[1]?.hoverWork == nil && service.expansion.owner == nil,
                     "a pointer no longer over the copy opens nothing")
        let opened = service.opened
        service.compactActivity = .calendar
        service.mirrors[1]?.host.activate?()
        service.compactActivity = nil
        suite.expect(service.countdownOpenings == 1 && service.opened == opened
                     && service.expansion.owner == 1,
                     "clicking a copy of an event countdown opens its event on that display")
        service.collapse()
        service.syncMirrors()

        // Unplugging a display closes its copy; leaving the choice closes them all.
        service.displayID = 1
        service.syncMirrors()
        let unplugged = service.mirrors[2]?.host
        NSScreen.screens = [builtIn]
        service.syncMirrors()
        suite.expect(service.mirrors[2] == nil && unplugged?.closes == 1, "a display that goes away takes its copy along")
        NSScreen.screens = [builtIn, external]
        service.syncMirrors()
        let hosts = service.mirrors.values.map(\.host)
        service.showsOnAllDisplays = false
        service.syncMirrors()
        suite.expect(service.mirrors.isEmpty && !hosts.isEmpty && hosts.allSatisfy { $0.closes == 1 },
                     "choosing one display closes every copy")
        service.showsOnAllDisplays = true
        service.showsInCaptures = false
        service.syncMirrors()
        suite.expect(!service.mirrors.isEmpty && service.mirrors.values.allSatisfy { $0.host.panel.sharingType == .none },
                     "copies stay out of screenshots with the island")
        service.running = false
        service.syncMirrors()
        suite.expect(service.mirrors.isEmpty, "a stopped island leaves no copies")

        let model = NotchMirrorModel(displayID: external.notchDisplayID, geometry: external2, size: CGSize(width: 100, height: 24))
        suite.expect(!model.update(geometry: external2, strip: external2, size: CGSize(width: 100, height: 24),
                                   activity: nil, expanded: false)
                     && model.update(geometry: external2, strip: external2, size: CGSize(width: 120, height: 24),
                                     activity: nil, expanded: false)
                     && model.update(geometry: external2, strip: external2, size: CGSize(width: 120, height: 24),
                                     activity: .music, expanded: false)
                     && model.activity == .music
                     && model.update(geometry: external2, strip: external2, size: CGSize(width: 120, height: 24),
                                     activity: .music, expanded: true)
                     && model.expanded
                     && !model.update(geometry: external2, strip: external2, size: CGSize(width: 120, height: 24),
                                      activity: .music, expanded: true),
                     "a copy is only redrawn when what it shows changes, and the page it draws is such a change")
        ownershipContracts(suite)
        pointerExitContracts(suite)
        hoverCollapseChecks(suite)
        hoverLifecycleContracts(suite)
        pointerSweepChecks(suite)
        levelNoticeContracts(suite)
        stripContentContracts(suite)
    }

    /// Volume and brightness feedback is visible on every island except the one
    /// whose expanded page already presents the same reading in its header.
    private static func levelNoticeContracts(_ suite: TestSuite) {
        for event in [NotchEvent.volume, .brightness] {
            suite.expect(NotchLevelHUDRouting.shows(event, on: 1, expandedDisplayID: nil)
                         && NotchLevelHUDRouting.shows(event, on: 2, expandedDisplayID: nil)
                         && NotchLevelHUDRouting.shows(event, on: 3, expandedDisplayID: nil),
                         "\(event.rawValue) feedback reaches every display while the island is collapsed")
            suite.expect(!NotchLevelHUDRouting.shows(event, on: 2, expandedDisplayID: 2)
                         && NotchLevelHUDRouting.shows(event, on: 1, expandedDisplayID: 2)
                         && NotchLevelHUDRouting.shows(event, on: 3, expandedDisplayID: 2),
                         "\(event.rawValue) feedback is suppressed only on the expanded owner, not on its neighbours")
            suite.expect(!NotchLevelHUDRouting.shows(event, on: 1, expandedDisplayID: 1)
                         && NotchLevelHUDRouting.shows(event, on: 2, expandedDisplayID: 1)
                         && NotchLevelHUDRouting.shows(event, on: 3, expandedDisplayID: 1),
                         "\(event.rawValue) feedback follows the owner when the primary display expands")
        }
        suite.expect(!NotchLevelHUDRouting.shows(.battery, on: 2, expandedDisplayID: 1)
                     && !NotchLevelHUDRouting.shows(.keyboardLight, on: 2, expandedDisplayID: nil),
                     "level mirroring is limited to volume and display brightness notices")

        let geometry = NotchGeometry(screen: CGRect(x: 100, y: 0, width: 1280, height: 800),
                                     safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 24, silhouette: .capsule)
        let mirror = NotchMirrorModel(displayID: 2, geometry: geometry,
                                      size: geometry.restingSize(showsContent: false))
        let notice = NotchNotice(event: .volume, title: "Volume", detail: "54%",
                                 symbol: "speaker.wave.2.fill", level: 0.54)
        mirror.setLevelNotice(notice)
        suite.expect(mirror.levelNotice == notice,
                     "a display mirror publishes its local volume feedback")
        mirror.setLevelNotice(nil)
        suite.expect(mirror.levelNotice == nil,
                     "a display mirror removes level feedback when the reading expires")

        func source(_ path: String) -> String {
            (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        }
        let mirrorView = source("Sources/Vorssaint/UI/Notch/NotchMirrorView.swift")
        let service = source("Sources/Vorssaint/Services/Notch/NotchService.swift")
        suite.expect(mirrorView.contains("if let notice = mirror.levelNotice")
                     && mirrorView.contains("NotchCapsuleNoticeView(notice: notice")
                     && mirrorView.contains("NotchNoticeView(notice: notice"),
                     "mirrors render the same level notice in both capsule and camera-notch geometry")
        suite.expect(service.contains("NotchLevelHUDRouting.shows(notice.event, on: displayID")
                     && service.contains("mirror.model.setLevelNotice(levelNotice)"),
                     "the service routes one shared reading to all non-owner mirrors")
    }

    /// A page cannot outlive the window that drew it, and a display with no copy of
    /// the island is no island. The page is asked for the display whose island was
    /// opened, and the island's own display never takes a page because it is the
    /// island's own: not when a display is unplugged, not when the choice is
    /// switched off, and not when a display returns.
    private static func ownershipContracts(_ suite: TestSuite) {
        let builtIn = NSScreen(1, CGRect(x: 0, y: 0, width: 1470, height: 956), notched: true)
        let external = NSScreen(2, CGRect(x: 1470, y: -86, width: 1920, height: 1080))
        let third = NSScreen(3, CGRect(x: 3390, y: -86, width: 1920, height: 1080))
        NSScreen.screens = [builtIn, external, third]
        NSScreen.screensHaveSeparateSpaces = false
        defer {
            NSScreen.screens = []
            NSScreen.screensHaveSeparateSpaces = true
        }

        let service = Service()
        service.syncMirrors()
        suite.expect(service.mirrors.count == 2 && service.mirrors[2]?.model.displayID == 2
                         && service.mirrors[3]?.model.displayID == 3,
                     "each copy knows the display its own window was built for")

        service.expand(on: 2)
        suite.expect(service.expanded && service.expansion.owner == 2 && service.presentsExpansion(on: 2)
                         && !service.presentsExpansion(on: 1),
                     "a page opened on a copy is drawn by that copy, and by no other window")

        // That display is unplugged. The island refreshes its presentation, which
        // retires the page with the window that drew it; the island's own display
        // is not the page's new home, and the third display takes nothing.
        NSScreen.screens = [builtIn, third]
        service.syncMirrors()
        service.retireExpansion()
        suite.expect(service.mirrors[2] == nil && service.expansion.owner == nil && !service.expanded
                         && !service.presentsExpansion(on: 1) && !service.presentsExpansion(on: 3),
                     "a display that goes away takes the page with it, and no other display is handed it")

        // The display returns. Its copy is a closed island, with nothing kept for
        // it from before, and the island as a whole holds no stale ownership.
        NSScreen.screens = [builtIn, external, third]
        service.syncMirrors()
        suite.expect(service.mirrors[2]?.model.expanded == false && service.mirrors[3]?.model.expanded == false
                         && service.expansion.owner == nil && !service.expanded,
                     "a display that returns brings a closed island and no page restored to it")

        // A display switched off the island is no island: it opens nothing, and it
        // answers no pointer of its own.
        service.showsOnAllDisplays = false
        service.syncMirrors()
        let opened = service.opened
        service.expand(on: 2)
        service.mirrors[2]?.over = true
        service.mirrors[2]?.host.hoverHandler?(true)
        suite.expect(service.mirrors.isEmpty && service.opened == opened && service.expansion.owner == nil
                         && !service.expanded,
                     "with the island on its own display only, a secondary display opens nothing and answers no pointer")

        // One page in the whole system: opening a second copy closes the first, and
        // every copy draws only a page of its own, at its own display's measure.
        service.showsOnAllDisplays = true
        service.syncMirrors()
        service.expand(on: 2)
        service.expand(on: 3)
        // The island refreshes after opening, and that is what tells each copy
        // whether this display draws the page.
        service.syncMirrors()
        let drawing = [CGDirectDisplayID](service.mirrors.keys).sorted().filter { service.presentsExpansion(on: $0) }
        suite.expect(service.expansion.owner == 3 && drawing == [3] && !service.presentsExpansion(on: 2)
                         && !service.presentsExpansion(on: 1)
                         && service.mirrors[2]?.model.expanded == false
                         && service.mirrors[3]?.model.expanded == true,
                     "a page opened on a second copy closes the first, and no two copies draw a page")
    }

    /// A copy's pointer, and what its leaving closes: the page its hover opened,
    /// and the peek it asked for. A page its click opened is a deliberate act and
    /// stays, as it stays on the island's own strip, and a page another display
    /// carries is not this copy's to close.
    private static func pointerExitContracts(_ suite: TestSuite) {
        let builtIn = NSScreen(1, CGRect(x: 0, y: 0, width: 1470, height: 956), notched: true)
        let external = NSScreen(2, CGRect(x: 1470, y: -86, width: 1920, height: 1080))
        NSScreen.screens = [builtIn, external]

        func wired() -> Service {
            let service = Service()
            service.displayID = 1
            service.syncMirrors()
            // Production's syncMirrors wires a copy's hover to that copy; the
            // fixture's makeMirror builds the window, so the same answer is wired
            // here, for every copy.
            for (id, copy) in service.mirrors {
                copy.host.setHoverHandler { [weak service] entered in service?.mirrorHover(id, entered: entered) }
            }
            return service
        }

        let service = wired()
        let copy = service.mirrors[2]
        suite.expect(copy != nil, "an external display has a copy to answer its pointer")

        // A hover past the chosen delay opens the page there, and records that a
        // pointer asked for it: the one fact that lets that pointer's leaving
        // close it. The whole dashboard is opened, as the island's own hover
        // opens it, and no focus is taken.
        copy?.over = true
        copy?.host.hoverHandler?(true)
        copy?.runHoverWork()
        suite.expect(service.expanded && service.expansion.owner == 2 && service.openedByHover
                         && service.wholeDashboardAsked,
                     "a copy's hover opens the page on its own display as a pointer's act, not a click's")
        service.syncMirrors()
        suite.expect(copy?.model.expanded == true && copy?.host.panel.acceptsKeyFocus == true,
                     "the copy whose display carries the page draws the page, and is the window that takes focus")

        // Out of it: the close is asked for at the pause the person chose, and the
        // page goes - the island's own answer, given on this display.
        let collapses = service.collapses
        copy?.over = false
        copy?.host.hoverHandler?(false)
        suite.expect(copy?.hoverWork != nil, "leaving a copy asks for its close, at the chosen pause")
        copy?.runHoverWork()
        // The island's refresh, which production's collapse runs: every window of
        // the island goes back to its own closed strip, on its own display.
        service.syncMirrors()
        suite.expect(service.collapses == collapses + 1 && !service.expanded && service.expansion.owner == nil
                         && copy?.model.expanded == false,
                     "the page a copy's hover opened closes when that copy's pointer leaves, and the copy is a closed island again")

        // The following starts at the copy's own entry, where no report of a
        // leaving is needed to start it: the opening that entry waits out grows
        // the copy's window under a pointer that has not moved, and a tracking
        // area replaced under a stationary pointer reports no leaving at all.
        // That is the exit the island's own window has its monitors for, and the
        // one a copy on a display of its own loses most often - which is why a
        // copy may not wait for the report to start following.
        copy?.over = true
        copy?.host.hoverHandler?(true)
        suite.expect(service.pointerWatchMonitors.count == 2,
                     "a copy follows the pointer's moves from its own entry, before a leaving can be lost")
        copy?.runHoverWork()
        service.syncMirrors()
        suite.expect(service.expansion.owner == 2 && service.pointerWatchMonitors.count == 2,
                     "the copy keeps following the pointer's moves while the page its hover opened is open")
        copy?.over = false
        copy?.host.hoverHandler?(false)
        suite.expect(service.pointerWatchMonitors.count == 2 && copy!.hoverWork != nil,
                     "a leaving that can close a copy's page keeps the pointer's moves followed")
        copy?.runHoverWork()
        suite.expect(service.collapses == collapses + 2 && service.expansion.owner == nil,
                     "the page a copy's hover opened closes at the chosen pause after the pointer leaves")
        copy?.host.hoverHandler?(false)
        suite.expect(service.pointerWatchMonitors.isEmpty,
                     "the pointer's moves are followed no more when no copy has anything left to close")

        // A page this copy's click opened is a deliberate act: leaving it closes
        // nothing, and nothing is followed.
        copy?.over = true
        copy?.host.activate?()
        service.syncMirrors()
        suite.expect(service.expansion.owner == 2 && !service.openedByHover && copy?.model.expanded == true,
                     "a click on a copy opens the page there as a deliberate act")
        copy?.over = false
        copy?.host.hoverHandler?(false)
        suite.expect(copy?.hoverWork == nil && service.expansion.owner == 2 && service.pointerWatchMonitors.isEmpty,
                     "leaving a page a click opened closes nothing and follows nothing")

        // A card inside the page this copy's *hover* opened: the page grows, the
        // keyboard moves to it, and the pointer's claim on this display's page is
        // kept - so this copy's own leaving closes it at the pause the person chose,
        // and the pointer's moves are followed for it. A card is not a second
        // opening, and a card is not the pin: the external display lives the same
        // lifecycle the island's own display does.
        let carded = wired()
        let itsCopy = carded.mirrors[2]
        itsCopy?.over = true
        itsCopy?.host.hoverHandler?(true)
        itsCopy?.runHoverWork()
        carded.syncMirrors()
        suite.expect(carded.expansion.owner == 2 && carded.openedByHover && itsCopy?.model.expanded == true,
                     "precondition: the copy's hover owns the page on its own display")
        carded.open(takeFocus: true, on: 2)
        suite.expect(carded.openedByHover && carded.expansion.owner == 2 && itsCopy?.model.expanded == true
                         && carded.mirrors.values.filter { $0.model.expanded }.count == 1,
                     "a card inside a copy's page keeps the pointer's claim, that display, and one page in the whole system")
        suite.expect(carded.pointerWatchMonitors.count == 2,
                     "the copy keeps following the pointer's moves for a page a card opened, as for a page its hover opened")
        itsCopy?.over = false
        itsCopy?.host.hoverHandler?(false)
        suite.expect(itsCopy?.hoverWork != nil, "leaving the page a card opened asks this copy for its close")
        itsCopy?.runHoverWork()
        carded.syncMirrors()
        suite.expect(carded.expansion.owner == nil && itsCopy?.model.expanded == false,
                     "the page a card opened closes with this copy's page at the chosen pause, and the copy is a closed island again")

        // The pin is the Keep Open the person chose, and it outlasts the leaving of
        // the copy that carries the page; a card's click never reaches it.
        let pinned = wired()
        let held = pinned.mirrors[2]
        held?.over = true
        held?.host.hoverHandler?(true)
        held?.runHoverWork()
        pinned.syncMirrors()
        pinned.pinned = true
        pinned.open(takeFocus: true, on: 2)
        suite.expect(pinned.pinned && pinned.expansion.owner == 2 && pinned.openedByHover,
                     "a card inside a pinned page keeps the page and the pin, and answers no click of its own")
        // The copy follows no pointer once the page is pinned, and the close its
        // own leaving asks for declines to fire: the pin is checked when the pause
        // is up, as the island's own close checks it.
        let kept = pinned.collapses
        held?.over = false
        held?.host.hoverHandler?(false)
        suite.expect(pinned.pointerWatchMonitors.isEmpty,
                     "a pinned page stops following the copy's pointer at its leaving")
        held?.runHoverWork()
        suite.expect(pinned.expansion.owner == 2 && pinned.collapses == kept,
                     "a pinned page answers no copy's leaving: the close it asks for declines to fire")

        // A page another display carries is not this copy's to close.
        service.expansion.asking(toOpen: 1)
        service.syncMirrors()
        copy?.over = true
        copy?.host.hoverHandler?(true)
        copy?.over = false
        copy?.host.hoverHandler?(false)
        suite.expect(copy?.hoverWork == nil && service.expansion.owner == 1,
                     "a page another display carries is not this copy's to close")

        // The choice the person made against the whole dashboard: a copy's hover
        // names the page at this display's measure, opens nothing, keeps the
        // peek's header row as its door - the island's own rule, measured for that
        // display - and takes the name back when the pointer leaves.
        let peeker = wired()
        peeker.displayID = 2
        peeker.hoverExpands = false
        peeker.syncMirrors()
        for (id, copy) in peeker.mirrors {
            copy.host.setHoverHandler { [weak peeker] entered in peeker?.mirrorHover(id, entered: entered) }
        }
        let two = peeker.mirrors[1]
        let notch = peeker.baseGeometry(for: builtIn)
        two?.over = true
        two?.host.hoverHandler?(true)
        suite.expect(two?.hoverWork != nil && two?.model.peeking == false,
                     "a copy's peek waits out the chosen delay, as its opening does")
        two?.runHoverWork()
        suite.expect(two?.model.peeking == true && !peeker.expanded && peeker.expansion.owner == nil
                         && two?.model.size == notch.peek,
                     "a copy peeks for its own pointer, at its own display's measure, and opens no page")
        suite.expect(two?.host.activationRect == CGRect(x: 0, y: 0, width: notch.peek.width,
                                                         height: notch.safeContentTop),
                     "a peeking copy's door is the peek's header row, measured for that display, as the island's is")
        two?.over = false
        two?.host.hoverHandler?(false)
        suite.expect(two?.hoverWork != nil, "leaving a peeking copy asks for its close")
        two?.runHoverWork()
        suite.expect(two?.model.peeking == false && peeker.expansion.owner == nil,
                     "the pointer's leaving takes the copy's peek back")

        // One page in the whole system: a page opened on another display takes a
        // copy's peek back, because a copy naming a page another window draws is a
        // name over a page that has gone.
        two?.over = true
        two?.host.hoverHandler?(true)
        two?.runHoverWork()
        suite.expect(two?.model.peeking == true, "precondition: the copy is peeking")
        peeker.expansion.asking(toOpen: 1)
        peeker.syncMirrors()
        suite.expect(two?.model.peeking == false,
                     "a page opened on another display takes a copy's peek back")

        // A surface that grew under a pointer that has not moved is answered by the
        // same choice a pointer that arrives is given (`rearmMirrorHoverOpen` reads
        // `mirrorHoverExpands`), so a resting pointer never opens a dashboard the
        // person asked not to have. Growing a copy's surface needs a real display
        // mode change: no unit fixture draws a copy at a measure that grows on a
        // resting pointer, and the real app on two displays is where this is seen.
    }

    /// A pending arrival may retain an eligible copy, but cannot overrule the
    /// same visibility policy that ordinarily removes that display's island.
    private static func arrivalVisibilityContracts(_ suite: TestSuite) {
        let separateSpaces = NSScreen.screensHaveSeparateSpaces
        defer {
            NSScreen.screensHaveSeparateSpaces = separateSpaces
            SpaceWindowBridge.fullscreen = []
            NotchAppFullscreen.covered = []
        }
        func arriving(activity: NotchCompactActivity? = nil) -> Service {
            let service = Service()
            service.compactActivity = activity
            service.syncMirrors()
            service.displayID = 2
            service.mirrorHeldForArrival = 2
            return service
        }

        let allowed = arriving()
        let allowedCopy = allowed.mirrors[2]!
        allowed.syncMirrors()
        suite.expect(allowedCopy.model.shown && allowedCopy.host.panel.isVisible
                     && allowedCopy.host.presented.count == 1 && allowedCopy.host.hides == 0,
                     "holding an eligible arrival leaves its already drawn copy untouched")

        for appFullscreen in [false, true] {
            let fullscreen = arriving()
            let copy = fullscreen.mirrors[2]!
            fullscreen.hidesInFullscreen = true
            if appFullscreen { NotchAppFullscreen.covered = [2] }
            else { SpaceWindowBridge.fullscreen = [2] }
            fullscreen.updateFullscreenDisplays()
            fullscreen.syncMirrors()
            suite.expect(fullscreen.fullscreenDisplays.contains(2) && !copy.model.shown
                         && !copy.host.panel.isVisible && copy.host.hides == 1,
                         "a held arrival still hides for \(appFullscreen ? "an application's" : "a Space's") full screen")
            SpaceWindowBridge.fullscreen = []
            NotchAppFullscreen.covered = []
        }

        let hidden = arriving()
        let hiddenCopy = hidden.mirrors[2]!
        hidden.hidesUntilHover = true
        hidden.syncMirrors()
        suite.expect(!hiddenCopy.model.shown && !hiddenCopy.host.panel.isVisible && hiddenCopy.host.hides == 1,
                     "hide-until-hover removes a held copy when it has no activity to keep visible")

        let active = arriving(activity: .music)
        let activeCopy = active.mirrors[2]!
        active.hidesUntilHover = true
        active.hiddenShowsActivity = true
        active.syncMirrors()
        suite.expect(activeCopy.model.shown && activeCopy.host.panel.isVisible && activeCopy.host.hides == 0,
                     "hide-until-hover still permits a held copy of an activity configured to remain visible")
        active.compactActivity = nil
        active.syncMirrors()
        suite.expect(!activeCopy.model.shown && activeCopy.host.hides == 1,
                     "an activity ending removes its held copy even before the live island arrives")

        let noRoom = arriving()
        let coveredMenus = noRoom.mirrors[2]!
        NSScreen.screensHaveSeparateSpaces = true
        noRoom.coversMenus = false
        noRoom.syncMirrors()
        suite.expect(!coveredMenus.model.shown && !coveredMenus.host.panel.isVisible && coveredMenus.host.hides == 1,
                     "a held capsule gives way when its display gains menus the island cannot cover")

        let camera = Service()
        camera.displayID = 2
        camera.coversMenus = false
        camera.syncMirrors()
        let cameraCopy = camera.mirrors[1]!
        camera.displayID = 1
        camera.mirrorHeldForArrival = 1
        camera.syncMirrors()
        suite.expect(cameraCopy.model.shown && cameraCopy.model.geometry.compactSideRoom == nil
                     && cameraCopy.host.hides == 0,
                     "a held physical camera remains covered even when the menus leave no room for wings")
    }

    /// The one hover lifecycle, answered by every window of the island.
    ///
    /// The island's own window and each copy's window are the same island at a
    /// different place on the desk. The pointer's entry starts the delay the
    /// person chose, the delay opens the page on that display, the open page's
    /// surface is part of the region the pointer is inside, and the pointer's
    /// leaving closes what its hover opened. `NotchIslandHover` is the rule both
    /// answer, so the island's questions and a copy's questions take one answer,
    /// and a copy on a display of its own needs the pointer-following from its
    /// own entry: the opening that entry waits out grows the copy's window under
    /// a pointer that has not moved, and that leaving is the one AppKit is most
    /// likely to report never at all.
    private static func hoverLifecycleContracts(_ suite: TestSuite) {
        func facts(inside: Bool, deadline: Bool, page: Bool = false, peek: Bool = false,
                   suppressed: Bool = false, openedByPointer: Bool = true) -> NotchIslandHover {
            NotchIslandHover(inside: inside, showsPage: page, peeking: peek, deadlinePending: deadline,
                             suppressed: suppressed,
                             closesOnExit: page && NotchSupport.closesOnPointerExit(
                                 expanded: true, peeking: peek, openedByHover: openedByPointer)
                                 || peek && NotchSupport.closesOnPointerExit(
                                     expanded: false, peeking: true, openedByHover: openedByPointer))
        }

        suite.expect(facts(inside: true, deadline: true).followsPointer
                     && !facts(inside: true, deadline: true).showsPage,
                     "a pointer that has just arrived is followed: its opening grows the island under it, and that leaving is the one AppKit drops")
        suite.expect(!facts(inside: true, deadline: false).followsPointer,
                     "a pointer resting on a closed island, with nothing waited out, follows nothing")
        suite.expect(facts(inside: true, deadline: false, page: true).followsPointer,
                     "an open page is followed while the pointer rests inside the whole island")
        suite.expect(!facts(inside: false, deadline: false).followsPointer,
                     "a pointer that has gone, with nothing left open, is followed no more")
        suite.expect(facts(inside: true, deadline: false, suppressed: true).followsPointer,
                     "a press's suppression ends at a leaving that may go unreported, so it is followed")
        suite.expect(!facts(inside: false, deadline: false, page: true, openedByPointer: false).followsPointer,
                     "a page a click opened keeps itself against the pointer's leaving, and follows nothing")
        suite.expect(facts(inside: true, deadline: false, peek: true).followsPointer,
                     "a page's name is kept by the pointer's staying, on every display alike")

        let builtIn = NSScreen(1, CGRect(x: 0, y: 0, width: 1470, height: 956), notched: true)
        let external = NSScreen(2, CGRect(x: 1470, y: -86, width: 1920, height: 1080))
        let third = NSScreen(3, CGRect(x: 3390, y: -86, width: 1920, height: 1080))
        NSScreen.screens = [builtIn, external, third]
        NSScreen.screensHaveSeparateSpaces = false
        defer {
            NSScreen.screens = []
            NSScreen.screensHaveSeparateSpaces = true
        }

        func openPages(_ service: Service) -> Int {
            service.mirrors.values.filter { $0.model.expanded }.count
                + (service.displayID.map { service.expansion.presents(on: $0) } == true ? 1 : 0)
        }
        func wired() -> Service {
            let service = Service()
            service.displayID = 1
            service.syncMirrors()
            for (id, copy) in service.mirrors {
                copy.host.setHoverHandler { [weak service] entered in service?.mirrorHover(id, entered: entered) }
            }
            return service
        }

        let service = wired()
        suite.expect(service.mirrors.count == 2 && service.mirrors[2] != nil && service.mirrors[3] != nil,
                     "with the island on every display, each external display has a copy to answer its pointer")

        // Every display answers its own pointer through the same lifecycle: the
        // entry, the delay, the page there, the panel that is part of the island,
        // and the leaving that closes it.
        for id: CGDirectDisplayID in [2, 3] {
            let copy = service.mirrors[id]!
            copy.over = true
            copy.host.hoverHandler?(true)
            suite.expect(copy.hoverWork != nil && service.pointerWatchMonitors.count == 2,
                         "display \(id) answers its entry as the island answers its own: the chosen delay, and the moves followed from the entry")
            copy.runHoverWork()
            service.syncMirrors()
            suite.expect(service.expanded && service.expansion.owner == id && copy.model.expanded
                         && openPages(service) == 1,
                         "display \(id) draws the page its own pointer opened, and it is the one page")
            // Down into the page, and along it: the panel is the island's own
            // interactive surface, so a move inside it is no leaving.
            copy.over = true
            let restingClosures = service.collapses
            NSEvent.reportMove(to: service.pointerWatchMonitors)
            suite.expect(copy.hoverWork == nil && service.expansion.owner == id
                         && service.collapses == restingClosures,
                         "the pointer moving over the open page of display \(id) is inside the whole island and closes nothing")
            // Out of the whole island: the close the island's own pointer gets.
            copy.over = false
            NSEvent.reportMove(to: service.pointerWatchMonitors)
            suite.expect(copy.hoverWork != nil, "a move followed out of the whole island asks display \(id)'s close")
            copy.runHoverWork()
            service.syncMirrors()
            suite.expect(!service.expanded && service.expansion.owner == nil && !copy.model.expanded
                         && openPages(service) == 0 && service.pointerWatchMonitors.isEmpty,
                         "display \(id) collapses on its own leaving, with no report of a leaving needed, and follows nothing after")
        }

        // The pointer crossing from one display to the next moves the page, and
        // leaves no second page behind: the island's single-expanded-page rule.
        let two = service.mirrors[2]!, three = service.mirrors[3]!
        two.over = true
        two.host.hoverHandler?(true)
        two.runHoverWork()
        service.syncMirrors()
        suite.expect(service.expansion.owner == 2 && two.model.expanded, "precondition: display 2 carries the page")
        two.over = false
        three.over = true
        three.host.hoverHandler?(true)
        NSEvent.reportMove(to: service.pointerWatchMonitors)
        suite.expect(two.hoverWork != nil && service.expansion.owner == 2,
                     "a pointer crossing to another display asks the display it leaves to close")
        three.runHoverWork()
        service.syncMirrors()
        suite.expect(service.expansion.owner == 3 && three.model.expanded && !two.model.expanded
                         && openPages(service) == 1,
                     "the display the pointer reaches draws the page, the one page, and the display it left is closed")
        let collapses = service.collapses
        two.runHoverWork()
        service.syncMirrors()
        suite.expect(service.collapses == collapses && service.expansion.owner == 3,
                     "a close that finds the page on another display closes nothing: never two, and never none by accident")
        three.over = false
        NSEvent.reportMove(to: service.pointerWatchMonitors)
        three.runHoverWork()
        service.syncMirrors()
        suite.expect(service.collapses == collapses + 1 && service.expansion.owner == nil && openPages(service) == 0,
                     "the last display's leaving closes the last page")

        // A pointer that passes through quickly leaves no state behind, and a
        // display that goes away takes its hover, its deadline, its followed
        // moves and its page with it, so the display that comes back starts from
        // nothing and no island is held open by a display no longer there.
        three.over = true
        three.host.hoverHandler?(true)
        suite.expect(three.hoverWork != nil && service.pointerWatchMonitors.count == 2,
                     "precondition: display 3 is armed, and the display that carries the page has its pointer followed")
        three.over = false
        three.host.hoverHandler?(false)
        suite.expect(three.hoverWork == nil && !three.inside
                         && service.expansion.owner == nil,
                     "a pointer that leaves before the delay opens nothing, schedules no close, and carries no page")
        three.over = true
        three.host.hoverHandler?(true)
        three.runHoverWork()
        service.syncMirrors()
        suite.expect(service.expansion.owner == 3 && three.model.expanded && service.pointerWatchMonitors.count == 2,
                     "precondition: display 3 carries the page and the pointer's moves are followed for it")
        NSScreen.screens = [builtIn, external]
        service.syncMirrors()
        suite.expect(service.mirrors[3] == nil && service.pointerWatchMonitors.isEmpty && !three.inside
                         && three.hoverWork == nil && !three.model.peeking,
                     "a display that goes away leaves no hover, no deadline, and no followed moves behind")
        service.retireExpansion()
        suite.expect(service.expansion.owner == nil && openPages(service) == 0,
                     "the page whose display has gone is closed, and never handed to another display")
        NSScreen.screens = [builtIn, external, third]
        service.syncMirrors()
        let back = service.mirrors[3]!
        suite.expect(back !== three && service.pointerWatchMonitors.isEmpty && !back.inside,
                     "a display that returns is a copy built anew, with no hover of its own to carry")
        back.over = true
        back.host.setHoverHandler { [weak service] entered in service?.mirrorHover(3, entered: entered) }
        back.host.hoverHandler?(true)
        suite.expect(back.hoverWork != nil && service.pointerWatchMonitors.count == 2,
                     "a copy that returns answers its pointer again, at once and by the same rule")
        back.over = false
        back.host.hoverHandler?(false)
        suite.expect(service.pointerWatchMonitors.isEmpty && back.hoverWork == nil, "a returning copy stops with its pointer")

        // A display with no copy of the island answers no pointer.
        service.showsOnAllDisplays = false
        service.syncMirrors()
        service.mirrorHover(2, entered: true)
        suite.expect(service.mirrors.isEmpty && service.expansion.owner == nil && !service.expanded,
                     "with the island on one display, no display answers a copy's pointer and none becomes a host")
        service.showsOnAllDisplays = true
    }

    /// The pointer's moves, read of every island window at once.
    ///
    /// A copy's window answers the pointer by its tracking area, and AppKit can
    /// drop that report: the moves a window receives stop when the pointer crosses
    /// the transparent margin, passes into another display, is taken by the page
    /// that grew under it, or is handed to a tracking area replaced under a resting
    /// pointer. The person sees one island on every display, so while a copy has
    /// something for the pointer to settle, a move onto a copy is that copy's entry,
    /// a move off its whole island is its leaving, a move back takes the leaving's
    /// close back, and a crossing from one display to the next closes the island it
    /// leaves and opens the island it arrives on - each of these told by the moves
    /// alone, with no report of a leaving awaited.
    private static func pointerSweepChecks(_ suite: TestSuite) {
        let builtIn = NSScreen(1, CGRect(x: 0, y: 0, width: 1470, height: 956), notched: true)
        let external = NSScreen(2, CGRect(x: 1470, y: -86, width: 1920, height: 1080))
        let third = NSScreen(3, CGRect(x: 3390, y: -86, width: 1920, height: 1080))
        NSScreen.screens = [builtIn, external, third]
        NSScreen.screensHaveSeparateSpaces = false
        defer {
            NSScreen.screens = []
            NSScreen.screensHaveSeparateSpaces = true
        }

        func openPages(_ service: Service) -> Int {
            service.mirrors.values.filter { $0.model.expanded }.count
                + (service.displayID.map { service.expansion.presents(on: $0) } == true ? 1 : 0)
        }
        func wired() -> Service {
            let service = Service()
            service.displayID = 1
            service.syncMirrors()
            for (id, copy) in service.mirrors {
                copy.host.setHoverHandler { [weak service] entered in service?.mirrorHover(id, entered: entered) }
            }
            return service
        }
        /// The pointer's move, as the followed monitors hear it. Nothing else is
        /// reported: no entering, no leaving.
        func moved(_ service: Service) { NSEvent.reportMove(to: service.pointerWatchMonitors) }

        let service = wired()
        // A pointer resting on no island of its own starts no watching: the island's
        // own window has its own monitors, and a page the island carries is no
        // copy's to close. The copies' pointer is followed from the moment one of
        // them has something for it to settle.
        suite.expect(service.pointerWatchMonitors.isEmpty,
                     "with the copies drawn and the pointer resting on none of them, no move is followed")

        // A copy's own report of an entering arms the following for every island at
        // once, and from there the pointer's moves alone are enough: no display's
        // island waits on a report of a leaving.
        let two = service.mirrors[2]!
        two.over = true
        two.host.hoverHandler?(true)
        suite.expect(two.inside && two.hoverWork != nil && service.pointerWatchMonitors.count == 2,
                     "a copy's own entering arms the pointer's moves, for every island, before a leaving can be lost")
        // Out again before the delay is out: nothing opened, nothing to close, and
        // no moves left to follow.
        two.over = false
        moved(service)
        suite.expect(!two.inside && two.hoverWork == nil && service.pointerWatchMonitors.isEmpty
                         && service.expansion.owner == nil && service.collapses == 0,
                     "a pointer that reaches a copy and leaves before the delay opens nothing, closes nothing, and is followed no more")

        // In, past the delay, and the page is this display's; out of the whole
        // island, and the page closes. The copy's own entering arms the following -
        // as it does on the island's own window, whose entry is the one report that
        // always arrives - and from there the pointer's moves tell the rest.
        two.over = true
        two.host.hoverHandler?(true)
        moved(service)
        two.runHoverWork()
        service.syncMirrors()
        suite.expect(service.expansion.owner == 2 && two.model.expanded && openPages(service) == 1,
                     "precondition: the pointer's arrival opened display 2's page")
        two.over = false
        moved(service)
        suite.expect(two.hoverWork != nil && service.expansion.owner == 2,
                     "a pointer leaving a copy's whole island asks for its close, with no report of a leaving to wait for")
        // Back onto the island while that close waits: the close is taken back, as
        // the island's own return takes its close back.
        two.over = true
        moved(service)
        suite.expect(two.hoverWork == nil && two.inside && service.expansion.owner == 2 && two.model.expanded,
                     "a pointer that comes back takes the leaving's close back, so the page the display carries stays open under it")
        two.over = false
        moved(service)
        two.runHoverWork()
        service.syncMirrors()
        suite.expect(service.expansion.owner == nil && !two.model.expanded && openPages(service) == 0
                         && service.pointerWatchMonitors.isEmpty,
                     "a pointer that leaves a copy's whole island closes the page that copy carries, told by the moves alone")

        // The crossing: the display left is asked to close, the display arrived on
        // is asked to open, and the page stays one, on the display that was arrived on.
        // The display arrived on answers its own entering, and from then the moves
        // alone carry the crossing, the close of the display left, and the one page.
        let three = service.mirrors[3]!
        three.over = true
        three.host.hoverHandler?(true)
        suite.expect(three.hoverWork != nil && !three.model.expanded,
                     "a pointer arriving on the next display is answered as that copy's own entry, at the chosen delay")
        three.runHoverWork()
        service.syncMirrors()
        suite.expect(service.expansion.owner == 3 && three.model.expanded && !two.model.expanded
                         && openPages(service) == 1,
                     "the page moved to the display the pointer is on, and it is still the one page")
        two.over = true
        three.over = false
        moved(service)
        suite.expect(two.hoverWork != nil && three.hoverWork != nil,
                     "a pointer crossing asks the display it leaves to close and the display it arrives on to open, by the moves alone")
        two.runHoverWork()
        three.runHoverWork()
        service.syncMirrors()
        suite.expect(service.expansion.owner == 2 && two.model.expanded && !three.model.expanded
                         && openPages(service) == 1,
                     "the crossing leaves its page on the display the pointer reached, and never two pages")

        // The following goes with the copies: no copies, no followed moves; and a
        // copy rebuilt is a copy with no hover of its own. Production's presentation
        // refresh retires a page whose window has gone, so the copies switching off
        // closes the page they were drawing.
        service.showsOnAllDisplays = false
        service.syncMirrors()
        service.retireExpansion()
        suite.expect(service.mirrors.isEmpty && service.pointerWatchMonitors.isEmpty
                         && service.expansion.owner == nil,
                     "with the copies gone, no pointer is followed for them and no page is left to them")
        service.showsOnAllDisplays = true
        service.syncMirrors()
        let again = service.mirrors[2]!
        suite.expect(again !== two && !again.inside && again.hoverWork == nil,
                     "the copies return as copies built anew, with no hover to carry")
        again.over = true
        again.host.setHoverHandler { [weak service] entered in service?.mirrorHover(2, entered: entered) }
        again.host.hoverHandler?(true)
        suite.expect(again.hoverWork != nil && service.pointerWatchMonitors.count == 2,
                     "the copies return, and a copy's own pointer is followed again")
        again.over = false
        again.host.hoverHandler?(false)
        suite.expect(service.pointerWatchMonitors.isEmpty, "and it is followed no more when nothing is left to settle")
    }

    /// The rule that made the island's own window open and close, asked of every
    /// copy on every display: a deadline is kept until the pointer crosses the
    /// boundary.
    ///
    /// A copy's window answers the pointer by its tracking area, and the pointer's
    /// moves are followed for every island at once, so the same leaving is told
    /// more than once - the area's report, then the moves that carry the pointer
    /// away. Cancelling a copy's waiting work whenever a report finds the pointer
    /// outside takes the close that leaving asked for back before the pause the
    /// person chose is out, and the page that copy carries then never closes: the
    /// island's own window, which keeps its deadline, closes on every display, and
    /// a copy that cancels on each report grows and stays grown. These are the
    /// reports of one leaving, told in the order AppKit tells them, on three
    /// displays.
    private static func hoverCollapseChecks(_ suite: TestSuite) {
        let builtIn = NSScreen(1, CGRect(x: 0, y: 0, width: 1728, height: 1117), notched: true)
        let upper = NSScreen(5, CGRect(x: 1728, y: 568, width: 1920, height: 1080))
        let lower = NSScreen(11, CGRect(x: 1728, y: -512, width: 1920, height: 1080))
        NSScreen.screens = [builtIn, upper, lower]
        NSScreen.screensHaveSeparateSpaces = false
        defer {
            NSScreen.screens = []
            NSScreen.screensHaveSeparateSpaces = true
        }

        func openPages(_ service: Service) -> Int {
            service.mirrors.values.filter { $0.model.expanded }.count
                + (service.displayID.map { service.expansion.presents(on: $0) } == true ? 1 : 0)
        }
        /// The island of a display whose window is not the island's own, wired as
        /// production wires it: the window's report of its pointer goes to that
        /// copy's hover.
        func wired() -> Service {
            let service = Service()
            service.displayID = 1
            service.syncMirrors()
            for (id, copy) in service.mirrors {
                copy.host.setHoverHandler { [weak service] entered in service?.mirrorHover(id, entered: entered) }
            }
            return service
        }
        /// Every move, as the island's windows hear it: the pair of monitors armed
        /// for the copies answers for all of them at once.
        func moved(_ service: Service) { NSEvent.reportMove(to: service.pointerWatchMonitors) }

        // Where the pointer is, asked in the one coordinate system AppKit uses -
        // the screen's own frame, as `NSEvent.mouseLocation` gives it. A point on
        // one display is inside that display's island and outside every other's,
        // closed and open alike, so a copy is never read for another's pointer.
        let island = builtIn, far = upper, low = lower
        let onIsland = CGPoint(x: island.frame.midX, y: island.frame.maxY - 8)
        let onFar = CGPoint(x: far.frame.midX, y: far.frame.maxY - 8)
        let onLow = CGPoint(x: low.frame.midX, y: low.frame.maxY - 8)
        let closed = CGSize(width: 253, height: 32)
        let islandGeometry = NotchGeometry(screen: island.frame, safeAreaTop: 32, cameraWidth: 185,
                                           menuBarHeight: 32, silhouette: .capsule)
        let farGeometry = NotchGeometry(screen: far.frame, safeAreaTop: 0, cameraWidth: 0,
                                        menuBarHeight: 24, silhouette: .capsule)
        let lowGeometry = NotchGeometry(screen: low.frame, safeAreaTop: 0, cameraWidth: 0,
                                        menuBarHeight: 24, silhouette: .capsule)
        suite.expect(islandGeometry.contains(onIsland, in: closed) && farGeometry.contains(onFar, in: closed)
                         && lowGeometry.contains(onLow, in: closed),
                     "a pointer resting at the top of each display is inside that display's island")
        suite.expect(!farGeometry.contains(onIsland, in: closed) && !lowGeometry.contains(onFar, in: closed)
                         && !farGeometry.contains(onLow, in: closed),
                     "a pointer on one display is outside the island of every other, whose frame sits elsewhere")
        // Down from the closed strip into the page: the whole island is the panel's
        // size, so a point in the panel is inside that island - and inside no other
        // display's island, whose page sits on its own screen's frame.
        let page = CGSize(width: 560, height: 449)
        let islandPage = islandGeometry.frame(for: page)
        let farPage = farGeometry.frame(for: page)
        let farStrip = farGeometry.frame(for: closed)
        let intoFarPage = CGPoint(x: farPage.midX, y: farPage.midY)
        let intoIslandPage = CGPoint(x: islandPage.midX, y: islandPage.midY)
        suite.expect(farGeometry.contains(intoFarPage, in: page) && !farGeometry.contains(intoFarPage, in: closed),
                     "the panel an island grows to is part of that island: a point below the closed strip is inside the island at the panel's size, and outside it at the closed one")
        suite.expect(intoFarPage.y < farStrip.minY && intoFarPage.y > farPage.minY,
                     "the panel's area lies below the closed strip on its own display, which is where the pointer travels into it")
        suite.expect(islandGeometry.contains(intoIslandPage, in: page) && farGeometry.contains(intoFarPage, in: page),
                     "each display's page is read in its own screen's frame, as the pointer's place is given in it")
        suite.expect(!farGeometry.contains(intoIslandPage, in: page) && !islandGeometry.contains(intoFarPage, in: page),
                     "a point inside one display's open panel is outside the open panel of every other display")

        // Every display answers its own pointer, and every display's leaving
        // closes: the entry, the reports of one leaving, the close, the collapse.
        for id: CGDirectDisplayID in [5, 11] {
            let service = wired()
            let copy = service.mirrors[id]!
            copy.over = true
            copy.host.hoverHandler?(true)
            suite.expect(copy.hoverWork != nil && service.pointerWatchMonitors.count == 2,
                         "display \(id) waits out the chosen delay at its own entry, and the pointer's moves are followed")
            copy.runHoverWork()
            service.syncMirrors()
            suite.expect(service.expansion.owner == id && copy.model.expanded && openPages(service) == 1
                         && service.openedByHover,
                         "display \(id) draws the one page its own pointer opened")

            // Down into the panel: the panel is the island's interactive area, so
            // the pointer moving in it is no leaving and closes nothing.
            let closures = service.collapses
            moved(service)
            suite.expect(copy.hoverWork == nil && copy.inside && service.expansion.owner == id
                         && service.collapses == closures,
                         "the pointer inside display \(id)'s panel closes nothing")

            // One leaving, told as AppKit tells it: the window's own report of the
            // pointer going, then the moves that carry it away, then more moves
            // while the pause runs. The close the first report asked for is kept
            // through the rest, and the page goes at the pause the person chose.
            copy.over = false
            copy.host.hoverHandler?(false)
            suite.expect(copy.hoverWork != nil && service.collapses == closures,
                         "display \(id)'s leaving asks for its close at the chosen pause")
            // The same leaving told again. Overlapping tracking areas report the same
            // presence more than once - the island's own window has its hover area and
            // its quick-access rects, and an area reports through a drag - so a copy
            // is asked about a pointer it is already outside, and the close already
            // waiting is kept, as the island's own window keeps its close.
            copy.host.hoverHandler?(false)
            moved(service)
            copy.host.hoverHandler?(false)
            moved(service)
            suite.expect(copy.hoverWork != nil && service.collapses == closures,
                         "the reports that follow display \(id)'s leaving keep the close that leaving asked for, so the pause the person chose is out before anything is decided")
            copy.runHoverWork()
            service.syncMirrors()
            suite.expect(service.collapses == closures + 1 && service.expansion.owner == nil
                         && !copy.model.expanded && !copy.inside && openPages(service) == 0,
                         "display \(id) collapses when its pointer leaves the whole island, as the island's own window does")
            suite.expect(service.pointerWatchMonitors.isEmpty,
                         "with nothing left to settle on display \(id), no move is followed for it")
        }

        // Back before the pause is out: the close is taken back, as the island's
        // own return takes its close back.
        let service = wired()
        let two = service.mirrors[5]!
        two.over = true
        two.host.hoverHandler?(true)
        two.runHoverWork()
        service.syncMirrors()
        suite.expect(service.expansion.owner == 5 && two.model.expanded, "precondition: display 5 carries the page")
        two.over = false
        two.host.hoverHandler?(false)
        moved(service)
        suite.expect(two.hoverWork != nil, "precondition: display 5's close is waiting")
        two.over = true
        moved(service)
        suite.expect(two.hoverWork == nil && two.inside && service.expansion.owner == 5 && two.model.expanded,
                     "a pointer that comes back to display 5 before its pause is out takes the close back, and the page stays")
        // A pointer that leaves and returns repeatedly keeps the page it is on, and
        // leaves no deadline behind on the way.
        for _ in 0..<3 {
            two.over = false
            moved(service)
            two.over = true
            moved(service)
        }
        suite.expect(two.hoverWork == nil && service.expansion.owner == 5 && openPages(service) == 1,
                     "a pointer that leaves and returns more than once leaves no close waiting and no second page")

        // Crossing from one copy to the next: the display left closes, the display
        // reached opens, and the page is one, where the pointer arrived. The
        // following was armed by the first display's entry, so the crossing is told
        // by the pointer's moves alone.
        let three = service.mirrors[11]!
        two.over = false
        three.over = true
        moved(service)
        suite.expect(two.hoverWork != nil && three.hoverWork != nil && service.expansion.owner == 5
                         && openPages(service) == 1,
                     "a pointer crossing asks the display it leaves to close and the display it reaches to open, by its moves alone")
        two.runHoverWork()
        three.runHoverWork()
        service.syncMirrors()
        suite.expect(service.expansion.owner == 11 && three.model.expanded && !two.model.expanded
                         && openPages(service) == 1 && !two.inside && two.hoverWork == nil,
                     "the page is the display the pointer reached, it is one page, and the display it left keeps no hover of its own")

        // On to the island's own display: the page moves to the window the island
        // stands on, and the copy that carried it answers no pointer for it.
        service.expand(on: 11)
        service.syncMirrors()
        suite.expect(service.expansion.owner == 11 && three.model.expanded, "precondition: display 11 carries the page")
        service.open(takeFocus: true, on: 1)
        service.syncMirrors()
        suite.expect(service.expansion.owner == 1 && service.expansion.presents(on: 1)
                         && !three.model.expanded && openPages(service) == 1,
                     "the page asked for on the island's own display moves there, and the copy that carried it is a closed island again")
        three.over = false
        moved(service)
        suite.expect(three.hoverWork == nil && service.expansion.owner == 1,
                     "a copy whose page has gone closes nothing the pointer's moves tell it")

        // A display unplugged mid-hover takes its hover, its deadline and the moves
        // followed for it with it, and the neighbour keeps the page it carries. The
        // page whose own window has gone is closed, and never handed over.
        two.over = true
        two.host.hoverHandler?(true)
        two.runHoverWork()
        service.syncMirrors()
        suite.expect(service.expansion.owner == 5 && two.model.expanded, "precondition: display 5 carries the page")
        three.over = true
        three.host.hoverHandler?(true)
        NSScreen.screens = [builtIn, upper]
        service.syncMirrors()
        suite.expect(service.mirrors[11] == nil && !three.inside && three.hoverWork == nil
                         && service.expansion.owner == 5 && two.model.expanded && openPages(service) == 1
                         && service.pointerWatchMonitors.count == 2,
                     "a display that goes mid-hover leaves no hover and no deadline behind, and the neighbour keeps the page and the pointer's moves")
        NSScreen.screens = [builtIn, upper, lower]
        service.syncMirrors()
        NSScreen.screens = [builtIn, lower]
        service.syncMirrors()
        suite.expect(service.mirrors[5] == nil && !two.inside && two.hoverWork == nil
                         && service.pointerWatchMonitors.isEmpty && openPages(service) == 0,
                     "the display whose window drew the page goes with it: no window of the island draws a page any more")
        service.retireExpansion()
        suite.expect(service.expansion.owner == nil && openPages(service) == 0,
                     "the page whose display has gone is closed, and never handed to another display")
        NSScreen.screens = [builtIn, upper, lower]
        service.syncMirrors()
        let back = service.mirrors[11]!
        suite.expect(back !== three && !back.inside && back.hoverWork == nil && !back.model.expanded,
                     "a display that returns is a copy built anew, with no hover to carry")
        back.over = true
        back.host.setHoverHandler { [weak service] entered in service?.mirrorHover(11, entered: entered) }
        back.host.hoverHandler?(true)
        suite.expect(back.hoverWork != nil && service.pointerWatchMonitors.count == 2,
                     "a copy that returns answers its pointer again, at once and by the same rule")
    }

    /// The closed island's content is one answer for every window of the island.
    ///
    /// A copy is the island on another display, and not a second island that
    /// picked its own arrangement: the pair the strip shows, and the one layout
    /// question the pair leaves over, are answered once, from the island's own
    /// surface. The screen, the window's frame, the strip's measure, the
    /// pointer's place, and which window holds the one open page stay each
    /// display's own.
    private static func stripContentContracts(_ suite: TestSuite) {
        func source(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }

        let speedAndSong = NotchStripContent.stripPair(NotchStripPair(reading: .music, mark: .splash))
        suite.expect(speedAndSong.activity == .music && speedAndSong.companion == .splash
                     && !speedAndSong.namesSongInGap,
                     "the speed keeps its mark at the leading end and the song its cover at the trailing, and the words stay away")
        suite.expect(speedAndSong == NotchStripContent.stripPair(NotchStripPair(reading: .music, mark: .splash)),
                     "the same pair asked of any display's window is the same content")
        let songAlone = NotchStripContent.stripPair(NotchStripPair(reading: .music), namesSongInGap: true)
        suite.expect(songAlone.activity == .music && songAlone.companion == nil && songAlone.namesSongInGap,
                     "a song alone is named where the island's own surface has room for the words")
        suite.expect(speedAndSong != songAlone,
                     "a display that has room for the words where the island has none is not allowed to name the song the island does not name")

        // The pair and the name come from the shared content, and never from a
        // window's answer to the pointer: a strip that fell back to the song's
        // solo layout would draw a different island on the other displays.
        let notch = source("Sources/Vorssaint/UI/Notch/NotchMusicStrip.swift")
        let capsule = source("Sources/Vorssaint/UI/Notch/NotchCapsuleViews.swift")
        suite.expect(notch.contains("private var content: NotchStripContent { service.stripContent }")
                     && notch.contains("snapshot == nil ? content.companion : nil")
                     && notch.contains("snapshot == nil ? content.namesSongInGap : Layout.fillsCameraGap(geometry)"),
                     "the notch's music strip takes its pair, and the song's name, from the island's shared content")
        suite.expect(!notch.contains("live ? service.compactCompanion") && !capsule.contains("live ? service.compactCompanion"),
                     "neither music strip picks its pair out of a window's answer to the pointer")
        suite.expect(capsule.contains("snapshot == nil ? service.stripContent.companion : nil"),
                     "the capsule's music strip reads the same shared content on every display")

        // A copy draws the island's own strips, and its own resting island: one
        // rendering rule, and no simplified music layout kept beside it.
        let mirror = source("Sources/Vorssaint/UI/Notch/NotchMirrorView.swift")
        let island = source("Sources/Vorssaint/UI/Notch/NotchView.swift")
        for strip in ["NotchTimerStrip", "NotchWatchStrip", "NotchDownloadStrip", "NotchAgentStrip",
                      "NotchCalendarStrip", "NotchMusicStrip", "NotchKeepAwakeStrip", "NotchSplashStrip"] {
            suite.expect(mirror.contains("\(strip)(service: service, displayGeometry: mirror.strip)")
                         && island.contains("\(strip)(service: service, displayGeometry: geometry"),
                         "the \(strip) a copy draws is the strip the island draws, in the island's shared content")
        }
        for (activity, capsuleStrip) in [("timer", "NotchCapsuleTimerStrip"), ("watch", "NotchCapsuleWatchStrip"),
                                         ("downloads", "NotchCapsuleDownloadStrip"), ("agents", "NotchCapsuleAgentStrip"),
                                         ("calendar", "NotchCapsuleCalendarStrip"), ("music", "NotchCapsuleMusicStrip"),
                                         ("keepAwake", "NotchCapsuleKeepAwakeStrip"),
                                         ("splash", "NotchCapsuleSplashStrip")] {
            suite.expect(mirror.contains("case .\(activity): \(capsuleStrip)(service: service, size: size, displayGeometry: geometry)")
                         && island.contains("case .\(activity): \(capsuleStrip)(service: service, size: size"),
                         "the \(capsuleStrip) a copy draws is the capsule the island draws")
        }
        suite.expect(mirror.contains("NotchRestingStrip(service: service, displayGeometry: geometry)")
                     && island.contains("NotchRestingStrip(service: service)"),
                     "a copy at rest draws the island's own resting strip, and no resting strip of its own")
        suite.expect(mirror.contains("NotchCapsuleRestingView(service: service, size: size, displayGeometry: geometry)")
                     && island.contains("NotchCapsuleRestingView(service: service, size: service.surfaceSize)"),
                     "a copy's resting capsule is the island's own capsule view")
    }
}
