// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The clock keeps the right of the camera. The left shows the timer's mark,
/// or its explicitly chosen companion: a download, working agents, the next
/// event's clock or the music playing, each opening its own page. The wings
/// are as wide as the wider side needs, and both sit at the ends, where the
/// island shows.
///
/// Where the countdown is the mark of a pair - beside a reading it stands above
/// - its own mark is its remaining time, in the one unit the wing fits, and not
/// its icon: see `NotchTimerSupport.stripMarkText`.
struct NotchTimerStrip: View {
    /// The display whose island window draws this view. Every page opened
    /// from here names it, so the page opens on the island it was asked on.
    @Environment(\.notchPageDisplay) private var pageDisplay: CGDirectDisplayID?
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var timer = NotchTimerService.shared
    // The companion's label reads these.
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    private var companion: NotchCompactActivity? { service.compactCompanion }
    private var iconSize: CGFloat { NotchTimerSupport.stripIconSize(height: geometry.compactActivityContentHeight) }
    private var textSize: CGFloat { NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight) }
    private var iconInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        if let companion { return NotchCompanionMark.inset(companion, geometry: geometry) }
        return geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2)
    }
    private var textInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        // Digits carry no descenders, so their ink is about the cap height.
        return geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if companion == .calendar { service.openCountdownEvent(on: pageDisplay) }
                else { service.openActivity(companion?.module ?? .timer, on: pageDisplay) }
            } label: {
                Group {
                    if geometry.compactActivityWingWidth >= 28 {
                        if let companion {
                            NotchCompanionMark(companion: companion, geometry: geometry)
                        } else {
                            // Alone, the strip has its reading of the time on the
                            // trailing side already, so the leading side is free to
                            // say what the countdown *is* doing: the paused clock, the
                            // finished check, the count up. Beside another activity the
                            // countdown is the mark, and a resting countdown is never
                            // drawn beside one - the pair gives it the whole strip - so
                            // there its number stands in the mark's place.
                            Image(systemName: timer.session.completed ? "checkmark.circle"
                                  : timer.session.isPaused ? "pause.circle" : timer.session.countsUp ? "stopwatch" : "timer")
                                .font(.system(size: iconSize, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.leading, iconInset)
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                       alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(companion.map { NotchCompanionMark.label($0, language: l10n.language) }
                                ?? FeatureStrings.notchActivities(l10n.language).phase(timer.session.phase))
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            if timer.session.isRunning {
                TimelineView(.periodic(from: Date(timeIntervalSinceNow: NotchTimerSupport.tickScheduleOffset(
                    for: timer.session, at: timer.now)), by: 1)) { _ in reading }
            } else {
                reading
            }
        }
        .frame(height: geometry.compactActivityContentHeight)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .buttonStyle(.plain)
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    private var reading: some View {
        let now = timer.now
        let text = NotchTimerSupport.compactText(for: timer.session, at: now,
                                                 locale: Locale(identifier: l10n.language.rawValue))
        return Button { service.openActivity(.timer, on: pageDisplay) } label: {
            Group {
                if geometry.compactActivityWingWidth >= 42 {
                    Text(text)
                        .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.orange)
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .modifier(NotchRollingDigits(value: text, countsDown: !timer.session.countsUp, everySecond: false))
                        // A reading that gains or loses a character, like
                        // 10m becoming 9m, resizes the wings; the service
                        // measures the same reading.
                        .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                            DispatchQueue.main.async { service.refreshPresentation() }
                        }
                }
            }
            .padding(.trailing, textInset)
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                   alignment: .trailing)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(FeatureStrings.notchActivities(l10n.language).phase(timer.session.phase))
        .accessibilityValue(NotchTimerSupport.clockText(for: timer.session, at: now))
    }
}

/// What shares a strip with another activity, drawn at the strip's left end:
/// a countdown's remaining time, a download's progress, the working agents'
/// marks, the event's dot and clock, the playing track's cover, the decode
/// speed, the watch, or the Keep Awake cup. Every activity that is running is
/// drawn, in the order of its standing, and the mark is the activity's own -
/// what its strip leads with, or, for the countdown and the reading, the number
/// it is being watched for.
struct NotchCompanionMark: View {
    let companion: NotchCompactActivity
    let geometry: NotchGeometry
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var splash = NotchSplashService.shared
    @ObservedObject private var service = NotchService.shared
    @ObservedObject private var l10n = L10n.shared

    /// The speed as the strip writes it, in the reader's language: the same
    /// text the service measures the wings from.
    private var splashSpeedText: String {
        NotchSplashSupport.stripSpeedText(splash.stripDecodeSpeed, language: l10n.language)
            ?? NotchSplashSupport.placeholder
    }

    var body: some View {
        switch companion {
        case .downloads:
            downloadIndicator
        case .agents:
            let working = Self.working
            HStack(spacing: 1) {
                ForEach(working) { NotchAgentGlyph(provider: $0, size: Self.agentMarkSize(working.count, geometry)) }
            }
        case .calendar:
            if let countdown = calendar.countdown {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    NotchCalendarStrip.clockMark(countdown, remaining: NotchCalendarSupport.countdownText(
                        until: countdown.target, now: context.date))
                }
            }
        case .music:
            NotchMusicCover(artwork: music.artwork, side: geometry.compactMusicArtworkSide,
                            radius: geometry.compactMusicArtworkRadius, source: music.playback?.track)
        case .timer:
            // The countdown's own digits, in the place its icon used to hold:
            // the hours while there are hours, the minutes while there are
            // minutes, and the seconds, plain, through the last minute. The mark
            // says what the countdown has left, which is the one question the
            // island is being asked beside the reading it shares the strip with.
            timerMark
        case .splash:
            // The speed of a reading in hand, as the strip's own reading of it:
            // the countdown keeps its clock on the other side, and this is the
            // mark of the work the island is being asked about.
            Text(splashSpeedText)
                .font(.system(size: NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight),
                              weight: .medium)).monospacedDigit()
                .foregroundStyle(NotchSplashPalette.purple)
                .lineLimit(1).minimumScaleFactor(0.65)
                .fixedSize()
                // A reading that gains or loses a character resizes the wings;
                // the service measures the same reading.
                .onChange(of: NotchAgentSupport.readingShape(splashSpeedText)) { _, _ in
                    DispatchQueue.main.async { service.refreshPresentation() }
                }
        case .watch:
            // The watch's mark, as its own strip leads with it.
            Image(systemName: NotchModule.watch.symbol)
                .font(.system(size: Self.iconSize(geometry), weight: .medium))
        case .keepAwake:
            // The cup, as the Keep Awake strip leads with it: a session keeping
            // the Mac awake is worth a mark beside the work it is keeping awake.
            Image(systemName: NotchKeepAwakeSupport.symbol)
                .font(.system(size: Self.iconSize(geometry), weight: .medium))
                .foregroundStyle(.yellow)
        }
    }

    private static func iconSize(_ geometry: NotchGeometry) -> CGFloat {
        min(13, NotchTimerSupport.stripIconSize(height: geometry.compactActivityContentHeight))
    }

    private var downloadIndicator: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 13))
            if geometry.compactActivityWingWidth >= 80,
               let fraction = downloads.items.first(where: { $0.active && !$0.completed })?.fraction {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
            }
        }
        .lineLimit(1)
        .clipped()
    }

    private static var working: [AgentProvider] {
        let live = AgentUsageService.shared.snapshot.live
        return AgentProvider.allCases.filter { provider in live.contains { $0.provider == provider } }
    }

    private static func agentMarkSize(_ working: Int, _ geometry: NotchGeometry) -> CGFloat {
        NotchTimerSupport.stripAgentMarkSize(height: geometry.compactActivityContentHeight, working: working)
    }

    /// The mark's distance from the strip's end, as far from the curve as
    /// from the strip's top and bottom.
    static func inset(_ companion: NotchCompactActivity, geometry: NotchGeometry) -> CGFloat {
        switch companion {
        case .agents:
            let side = agentMarkSize(working.count, geometry)
            return geometry.compactActivityEdgeInset(boxHeight: side + 4, radius: (side + 4) / 2)
        case .music:
            return geometry.compactMusicArtworkInset
        case .calendar:
            return geometry.compactActivityEdgeInset(boxHeight: 9, radius: 0)
        case .splash:
            // The speed is text, so its ink is about the cap height, as a
            // strip's reading keeps it.
            let size = NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight)
            return geometry.compactActivityEdgeInset(boxHeight: size * 0.72, radius: 0)
        case .timer:
            // The mark is the countdown's digits, so its ink is about the cap
            // height, as a strip's reading and the decode speed's mark keep it.
            let size = NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight)
            return geometry.compactActivityEdgeInset(boxHeight: size * 0.72, radius: 0)
        case .downloads, .keepAwake, .watch:
            let side = min(13, NotchTimerSupport.stripIconSize(height: geometry.compactActivityContentHeight))
            return geometry.compactActivityEdgeInset(boxHeight: side, radius: side / 2)
        }
    }
    static func label(_ companion: NotchCompactActivity, language: AppLanguage) -> String {
        switch companion {
        case .downloads:
            return FeatureStrings.notchFiles(language).downloadsTitle
        case .agents:
            return working.map(\.displayName).joined(separator: ", ")
        case .calendar:
            let text = FeatureStrings.notchCalendar(language)
            guard let countdown = NotchCalendarService.shared.countdown else { return text.title }
            return "\(countdown.ongoing ? text.ongoing : text.next): "
                + NotchCalendarStrip.displayTitle(countdown.event, untitled: text.untitled)
        case .music:
            let playback = NotchMusicService.shared.playback
            let title = playback?.track.title ?? FeatureStrings.radialMenu(language).mediaNowPlaying
            return [title, playback?.track.artist].compactMap { $0 }.joined(separator: ", ")
        case .splash:
            let text = FeatureStrings.notchSplash(language)
            let speed = NotchSplashSupport.stripSpeedText(NotchSplashService.shared.stripDecodeSpeed,
                                                          language: language)
                ?? NotchSplashSupport.placeholder
            return "\(text.decode) \(speed)"
        case .timer:
            // The mark speaks the countdown's number, so the voice says it too.
            let clock = NotchTimerService.shared
            let text = NotchTimerSupport.stripMarkText(for: clock.session, at: clock.now,
                                                       locale: Locale(identifier: language.rawValue))
            return "\(companion.title(language)) \(text)"
        case .keepAwake, .watch:
            return companion.title(language)
        }
    }

    /// The countdown as the strip writes it beside another activity: the same
    /// reading, the same rounding, and the same ticking schedule the timer's own
    /// strip keeps, so the last minute counts off one second at a time here as
    /// it does there. A countdown at rest is not drawn beside another activity
    /// at all - the strip's pair gives a resting clock the whole strip - so the
    /// mark is drawn only while the clock runs.
    private var timerMark: some View {
        Group {
            if timer.session.isRunning {
                TimelineView(.periodic(from: Date(timeIntervalSinceNow: NotchTimerSupport.tickScheduleOffset(
                    for: timer.session, at: timer.now)), by: 1)) { _ in timerReading }
            } else {
                timerReading
            }
        }
    }

    private var timerReading: some View {
        let text = NotchTimerSupport.stripMarkText(for: timer.session, at: timer.now,
                                                   locale: Locale(identifier: l10n.language.rawValue))
        return Text(text)
            .font(.system(size: NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight),
                          weight: .medium)).monospacedDigit()
            .foregroundStyle(.orange)
            .lineLimit(1).minimumScaleFactor(0.65)
            // A mark that gains or loses a character, like 2h becoming 59m,
            // resizes the wings; the service measures the same reading.
            .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                DispatchQueue.main.async { service.refreshPresentation() }
            }
    }

    /// The countdown, for the mark of a timer that shares another activity's
    /// strip.
    @ObservedObject private var timer = NotchTimerService.shared
}
