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
        static func removeMonitor(_ token: Any) { global[token as! Int] = nil; local[token as! Int] = nil }
        /// Report a move to the monitors of one copy, as AppKit reports the moves a
        /// window stops receiving. Only the global monitor answers, and once: it is
        /// the pointer's moves over the rest of the system that a copy needs, and a
        /// move answered twice would be a leaving and a second leaving, whose second
        /// answer takes the first's close back. The event is never read - production's
        /// handlers ask where the pointer is of the fixture's `mouseLocation`, and a
        /// real AppKit mouse event cannot be built for a process with no window.
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
        /// The moves this copy asks to follow while its hover keeps a page or a
        /// peek open.
        var exitMonitors: [Any] = []
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
            // Production's collapse ends the moves followed for every copy: the
            // page is closed everywhere, so no copy has a hover left to keep it.
            mirrors.values.forEach { mirror in
                mirror.exitMonitors.forEach(NSEvent.removeMonitor)
                mirror.exitMonitors.removeAll()
            }
        }
        func open() { opened += 1; expanded = true; expansion.asking(toOpen: displayID ?? 0) }
        func open(takeFocus: Bool, on display: CGDirectDisplayID?) {
            opened += 1
            expanded = true
            openedByHover = !takeFocus
            expansion.asking(toOpen: display ?? (displayID ?? 0))
        }
        func open(takeFocus: Bool, wholeDashboard: Bool, on display: CGDirectDisplayID?) {
            opened += 1
            expanded = true
            openedByHover = !takeFocus
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
        hoverLifecycleContracts(suite)
        pointerSweepChecks(suite)
        stripContentContracts(suite)
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
        suite.expect(copy!.exitMonitors.count == 2,
                     "a copy follows the pointer's moves from its own entry, before a leaving can be lost")
        copy?.runHoverWork()
        service.syncMirrors()
        suite.expect(service.expansion.owner == 2 && copy!.exitMonitors.count == 2,
                     "the copy keeps following the pointer's moves while the page its hover opened is open")
        copy?.over = false
        copy?.host.hoverHandler?(false)
        suite.expect(copy!.exitMonitors.count == 2 && copy!.hoverWork != nil,
                     "a leaving that can close a copy's page keeps that copy following the pointer's moves")
        copy?.runHoverWork()
        suite.expect(service.collapses == collapses + 2 && service.expansion.owner == nil,
                     "the page a copy's hover opened closes at the chosen pause after the pointer leaves")
        copy?.host.hoverHandler?(false)
        suite.expect(copy!.exitMonitors.isEmpty,
                     "a copy stops following the pointer's moves when it has nothing left to close")

        // A page this copy's click opened is a deliberate act: leaving it closes
        // nothing, and nothing is followed.
        copy?.over = true
        copy?.host.activate?()
        service.syncMirrors()
        suite.expect(service.expansion.owner == 2 && !service.openedByHover && copy?.model.expanded == true,
                     "a click on a copy opens the page there as a deliberate act")
        copy?.over = false
        copy?.host.hoverHandler?(false)
        suite.expect(copy?.hoverWork == nil && service.expansion.owner == 2 && copy!.exitMonitors.isEmpty,
                     "leaving a page a click opened closes nothing and follows nothing")

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
            suite.expect(copy.hoverWork != nil && copy.exitMonitors.count == 2,
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
            NSEvent.reportMove(to: copy.exitMonitors)
            suite.expect(copy.hoverWork == nil && service.expansion.owner == id
                         && service.collapses == restingClosures,
                         "the pointer moving over the open page of display \(id) is inside the whole island and closes nothing")
            // Out of the whole island: the close the island's own pointer gets.
            copy.over = false
            NSEvent.reportMove(to: copy.exitMonitors)
            suite.expect(copy.hoverWork != nil, "a move followed out of the whole island asks display \(id)'s close")
            copy.runHoverWork()
            service.syncMirrors()
            suite.expect(!service.expanded && service.expansion.owner == nil && !copy.model.expanded
                         && openPages(service) == 0 && copy.exitMonitors.isEmpty,
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
        NSEvent.reportMove(to: two.exitMonitors)
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
        NSEvent.reportMove(to: three.exitMonitors)
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
        suite.expect(three.hoverWork != nil && three.exitMonitors.count == 2, "precondition: display 3 is armed")
        three.over = false
        three.host.hoverHandler?(false)
        suite.expect(three.hoverWork == nil && !three.inside && three.exitMonitors.isEmpty
                         && service.expansion.owner == nil,
                     "a pointer that leaves before the delay opens nothing, schedules no close, and follows nothing")
        three.over = true
        three.host.hoverHandler?(true)
        three.runHoverWork()
        service.syncMirrors()
        suite.expect(service.expansion.owner == 3 && three.model.expanded && three.exitMonitors.count == 2,
                     "precondition: display 3 carries the page and follows its own pointer")
        NSScreen.screens = [builtIn, external]
        service.syncMirrors()
        suite.expect(service.mirrors[3] == nil && three.exitMonitors.isEmpty && !three.inside
                         && three.hoverWork == nil && !three.model.peeking,
                     "a display that goes away leaves no hover, no deadline, and no followed moves behind")
        service.retireExpansion()
        suite.expect(service.expansion.owner == nil && openPages(service) == 0,
                     "the page whose display has gone is closed, and never handed to another display")
        NSScreen.screens = [builtIn, external, third]
        service.syncMirrors()
        let back = service.mirrors[3]!
        suite.expect(back !== three && back.exitMonitors.isEmpty && !back.inside,
                     "a display that returns is a copy built anew, with no hover of its own to carry")
        back.over = true
        back.host.setHoverHandler { [weak service] entered in service?.mirrorHover(3, entered: entered) }
        back.host.hoverHandler?(true)
        suite.expect(back.hoverWork != nil && back.exitMonitors.count == 2,
                     "a copy that returns answers its pointer again, at once and by the same rule")
        back.over = false
        back.host.hoverHandler?(false)
        suite.expect(back.exitMonitors.isEmpty && back.hoverWork == nil, "a returning copy stops with its pointer")

        // A display with no copy of the island answers no pointer.
        service.showsOnAllDisplays = false
        service.syncMirrors()
        service.mirrorHover(2, entered: true)
        suite.expect(service.mirrors.isEmpty && service.expansion.owner == nil && !service.expanded,
                     "with the island on one display, no display answers a copy's pointer and none becomes a host")
        service.showsOnAllDisplays = true
    }

    /// The pointer, and not a window's report of an entering, is what every
    /// island is read from.
    ///
    /// These windows are borderless, non-activating and above every other window,
    /// and a copy sits on a display of its own: AppKit can report no entering and
    /// no leaving for it at all. The person sees one island on every display, so
    /// a move onto a copy is that copy's entry, a move off its whole island is its
    /// leaving, a move back takes the leaving's close back, and a pointer crossing
    /// from one display to the next closes the island it leaves and opens the
    /// island it arrives on - every one of these told by the moves alone, with no
    /// report of an entering or a leaving in the test at all.
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
        suite.expect(service.pointerWatchMonitors.count == 2,
                     "copies drawn on other displays have their pointer followed from the first, so no display's island waits on a report of an entering")

        // A pointer reaching a copy is that copy's entry: the chosen delay, the
        // moves followed from it, and the page not opened yet.
        let two = service.mirrors[2]!
        two.over = true
        moved(service)
        suite.expect(two.inside && two.hoverWork != nil && two.exitMonitors.count == 2
                         && !two.model.expanded && service.expansion.owner == nil,
                     "a pointer reaching a copy, told by no report of an entering, is answered as its own entry: the delay chosen, and no page yet")
        // Out again before the delay is out: nothing opened, nothing to close, and
        // no moves left to follow.
        two.over = false
        moved(service)
        suite.expect(!two.inside && two.hoverWork == nil && two.exitMonitors.isEmpty
                         && service.expansion.owner == nil && service.collapses == 0,
                     "a pointer that reaches a copy and leaves before the delay opens nothing, closes nothing, and is followed no more")

        // In, past the delay, and the page is this display's; out of the whole
        // island, and the page closes - the moves alone, which is what a copy on a
        // display of its own can rely on.
        two.over = true
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
                         && two.exitMonitors.isEmpty,
                     "a pointer that leaves a copy's whole island closes the page that copy carries, told by the moves alone")

        // The crossing: the display left is asked to close, the display arrived on
        // is asked to open, and the page stays one, on the display that was arrived on.
        let three = service.mirrors[3]!
        three.over = true
        moved(service)
        suite.expect(three.hoverWork != nil && !three.model.expanded,
                     "a pointer arriving on the next display is that copy's entry, with no report of an entering")
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

        // The following goes with the copies: no copies, no followed moves.
        service.showsOnAllDisplays = false
        service.syncMirrors()
        suite.expect(service.mirrors.isEmpty && service.pointerWatchMonitors.isEmpty,
                     "with the copies gone, no pointer is followed for them")
        service.showsOnAllDisplays = true
        service.syncMirrors()
        suite.expect(service.pointerWatchMonitors.count == 2,
                     "the copies return, and their pointer is followed again")
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
