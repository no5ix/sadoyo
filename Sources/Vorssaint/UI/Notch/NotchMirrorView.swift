// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A display's own island.
///
/// Closed, it is what the island shows, drawn for this display - a capsule or a
/// notch - and it takes no clicks of its own: its window's own button, and its
/// own hover area, answer the pointer on this display and open the page here.
/// Open, it is the page: the island's one page, drawn by this window because
/// this display's island was the one opened. Nothing of the dashboard is
/// duplicated here - the same view, the same state, the page of one display at a
/// time - and the windows stay on the displays they were built for.
struct NotchMirrorView: View {
    @ObservedObject var service: NotchService
    @ObservedObject var mirror: NotchMirrorModel

    var body: some View {
        content
            .frame(width: mirror.size.width, height: mirror.size.height, alignment: .top)
            .foregroundStyle(.white)
            // A closed copy is a picture and a door: its clicks are the window's
            // button. An open page is a page: its cards, sliders and fields take
            // the clicks that are asked of them.
            .allowsHitTesting(mirror.expanded)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            .environment(\.notchPresentation, true)
            // This window is on one display and never moves: everything drawn in
            // it names this display for the pages it opens, so a page asked for
            // here - a strip, a card, a secondary-click menu - opens here.
            .environment(\.notchPageDisplay, mirror.displayID)
            .tint(.white)
            .accessibilityHidden(!mirror.expanded)
    }

    @ViewBuilder private var content: some View {
        if mirror.expanded {
            // The page, at the size this display's window presents it, with none
            // of the island's own rest, notice, capture controls, or fullscreen
            // state: this window draws the page, and only the page. It is drawn
            // for this display, and says so: the page's own actions open on this
            // display, and never on the island's own.
            NotchView(service: service, presentsPage: true, pageSurfaceSize: mirror.size,
                      hostDisplayID: mirror.displayID)
        } else {
            let geometry = mirror.geometry
            let size = mirror.size
            if let activity = mirror.activity {
                activityStrip(activity, geometry: geometry, size: size)
                    .modifier(NotchMascotActivityVisit(
                        service: service,
                        track: service.mascotOn
                            ? NotchMascotSupport.track(overActivity: geometry.floats ? geometry : mirror.strip,
                                                       size: size, side: service.mascotSide)
                            : nil))
            } else if geometry.floats {
                NotchCapsuleRestingView(service: service, size: size, displayGeometry: geometry)
            } else {
                NotchRestingStrip(service: service, displayGeometry: geometry)
            }
        }
    }

    @ViewBuilder private func activityStrip(_ activity: NotchCompactActivity, geometry: NotchGeometry,
                                            size: CGSize) -> some View {
        if geometry.floats {
            switch activity {
            case .timer: NotchCapsuleTimerStrip(service: service, size: size, displayGeometry: geometry)
            case .watch: NotchCapsuleWatchStrip(service: service, size: size, displayGeometry: geometry)
            case .downloads: NotchCapsuleDownloadStrip(service: service, size: size, displayGeometry: geometry)
            case .agents: NotchCapsuleAgentStrip(service: service, size: size, displayGeometry: geometry)
            case .calendar: NotchCapsuleCalendarStrip(service: service, size: size, displayGeometry: geometry)
            case .music: NotchCapsuleMusicStrip(service: service, size: size, displayGeometry: geometry)
            case .keepAwake: NotchCapsuleKeepAwakeStrip(service: service, size: size, displayGeometry: geometry)
            case .splash: NotchCapsuleSplashStrip(service: service, size: size, displayGeometry: geometry)
            }
        } else {
            switch activity {
            case .timer: NotchTimerStrip(service: service, displayGeometry: mirror.strip)
            case .watch: NotchWatchStrip(service: service, displayGeometry: mirror.strip)
            case .downloads: NotchDownloadStrip(service: service, displayGeometry: mirror.strip)
            case .agents: NotchAgentStrip(service: service, displayGeometry: mirror.strip)
            case .calendar: NotchCalendarStrip(service: service, displayGeometry: mirror.strip)
            case .music: NotchMusicStrip(service: service, displayGeometry: mirror.strip)
            case .keepAwake: NotchKeepAwakeStrip(service: service, displayGeometry: mirror.strip)
            case .splash: NotchSplashStrip(service: service, displayGeometry: mirror.strip)
            }
        }
    }
}
