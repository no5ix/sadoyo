// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

// MARK: - Settings

/// The section's own options on the Content tab: the switch, the server, the
/// port and the key.
///
/// The address is kept in the app's own settings, as every other section keeps
/// what it needs: this is a tool on a Mac that reads a server on the same Mac.
/// The settings start at the Splash server on this Mac, at the port that
/// server answers on, with the key that server hands out, so the dashboard
/// works before anyone has typed anything; a value written into the settings
/// takes the place of the one the app starts with, and nothing already written
/// is touched. The key is kept beside the address it belongs to and is never
/// written on the screen: the field starts empty, a key typed into it is kept
/// and the field is emptied again, and all the settings say about it is that a
/// key is in use.
struct NotchSplashSettingsControls: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchSplashEnabled) private var enabled = false
    @AppStorage(DefaultsKey.notchSplashHost) private var host = NotchSplashEndpoint.localHost
    @AppStorage(DefaultsKey.notchSplashPort) private var port = NotchSplashEndpoint.defaultPort
    @State private var portText = NotchSplashEndpoint.portText(NotchSplashEndpoint.defaultPort)
    /// A key typed, which is kept and then forgotten by the field.
    @State private var typedKey = ""
    @State private var keyIsSet = NotchSplashSupport.hasAPIKey()
    private var text: NotchSplashStrings { FeatureStrings.notchSplash(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switchRow
            if enabled { serverRows }
        }
        .onAppear {
            portText = NotchSplashEndpoint.portText(port)
            keyIsSet = NotchSplashSupport.hasAPIKey()
        }
        .onChange(of: portText) { _, typed in
            if let number = NotchSplashEndpoint.port(typed) { port = number }
        }
        .onChange(of: host) { _, typed in
            let trimmed = NotchSplashEndpoint.host(typed)
            if trimmed != typed { host = trimmed }
        }
        .onChange(of: enabled) { _, on in if on { Notifier.requestPermission() } }
        .onChange(of: host) { _, _ in NotchSplashService.shared.syncWithPreferences() }
        .onChange(of: port) { _, _ in NotchSplashService.shared.syncWithPreferences() }
        .onChange(of: enabled) { _, _ in NotchService.shared.syncWithPreferences() }
    }

    /// The switch, and why a person would want the dashboard at all.
    private var switchRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(text.title, isOn: $enabled)
                .disabled(!AppFeature.notchSplash.isAvailable)
            Text(text.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Where to read, and with what key. The address and the port are written
    /// as they are stored; the key is written once and never shown again.
    private var serverRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow(symbol: "network", title: text.host, caption: text.hostHint) {
                TextField("127.0.0.1", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(text.host)
            }
            SettingsRow(symbol: "point.topleft.down.curvedto.point.bottomright.up",
                        title: text.port, caption: nil) {
                TextField(NotchSplashEndpoint.portText(NotchSplashEndpoint.defaultPort), text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(text.port)
            }
            SettingsRow(symbol: "key", title: text.apiKey,
                        caption: keyIsSet ? text.apiKeySet : text.apiKeyHint) {
                HStack(spacing: 6) {
                    SecureField("sk-…", text: $typedKey) { commitKey() }
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel(text.apiKey)
                        .accessibilityIdentifier("notch.splash.key")
                    if NotchSplashSupport.hasWrittenAPIKey() {
                        Button(text.apiKeyClear) { clearKey() }
                            .accessibilityIdentifier("notch.splash.key.clear")
                    }
                }
            }
            // The end of a task is told by a macOS notice, which the system
            // gates behind its own permission: asking here is the app's own
            // permission flow, and says what the notice is for.
            Button(text.openSettings) { NotchService.shared.perform { Notifier.requestPermission() } }
        }
    }

    /// A key typed is kept and the field emptied: a key on the screen is a key
    /// for the room, and the field's job is to take a key in, not to show one
    /// out.
    private func commitKey() {
        let typed = typedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        UserDefaults.standard.set(typed, forKey: DefaultsKey.notchSplashAPIKey)
        typedKey = ""
        keyIsSet = true
        NotchSplashService.shared.syncWithPreferences()
    }

    /// Taking back a key written by hand, which leaves the key the app starts
    /// with in place. The key itself is not named.
    private func clearKey() {
        UserDefaults.standard.set("", forKey: DefaultsKey.notchSplashAPIKey)
        typedKey = ""
        keyIsSet = NotchSplashSupport.hasAPIKey()
        NotchSplashService.shared.syncWithPreferences()
    }
}

// MARK: - The card

/// The dashboard: one line of status over four readings in one row.
///
/// The page and the dashboard's Live Activities section draw this one view, so
/// the same numbers, the same words, the same thresholds and the same colours
/// answer in both places. Nothing in the view reads a server: it is given a
/// reading, and it says what it can from what the reading carries.
struct NotchSplashDashboardCard: View {
    let snapshot: NotchSplashSnapshot?
    let phase: NotchSplashTaskTracker.Phase
    /// The clock's value at the moment the card is drawn.
    var elapsed: TimeInterval = 0
    var isMonitoring = false
    var isSpilling = false
    /// Why the reading stopped answering, while it is being watched.
    var failure: NotchSplashFailure?
    /// The server being read, named when it does not answer.
    var address: String = NotchSplashSupport.placeholder
    /// The way out of the session, offered in the header as the reference draws it.
    var onStop: (() -> Void)?
    var compact = false

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: NotchSplashStrings { FeatureStrings.notchSplash(l10n.language) }
    private var status: NotchSplashStatus? { snapshot?.status }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchSplashLayout.headerSpacing) {
            header
            metrics
        }
        .padding(NotchSplashLayout.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(NotchControlSurface(cornerRadius: NotchSplashLayout.cornerRadius,
                                      interactive: false, fillOpacity: NotchDashboardLayout.fillOpacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.title)
        .accessibilityIdentifier("notch.splash.card")
    }

    // MARK: The header, on one line

    /// The name of the dashboard on the left, and everything the server is
    /// doing on the same line: the tokens in and out, the cache and the
    /// memory, the task's clock, and the way out.
    ///
    /// The line is offered in widths, most wanted first. While a reading is
    /// not coming, the reason for that outranks the cumulative tokens: a
    /// person reading the card needs to know what the page is doing before
    /// they need the totals. A narrow surface gives up the memory group, then
    /// the tokens, before it gives up the line itself, so the card never
    /// clips and never stacks.
    private var header: some View {
        let clock = NotchSplashSupport.taskClock(elapsed)
        return HStack(spacing: 6) {
            HStack(spacing: 4) {
                // The dashboard's own mark, the one its tile in the Explorer
                // wears, so the card and the section are the same thing.
                Image(systemName: NotchModule.splash.symbol)
                    .font(.system(size: compact ? NotchSplashLayout.titleIconSize - 1
                                                : NotchSplashLayout.titleIconSize,
                                  weight: .semibold))
                    .foregroundStyle(NotchSplashPalette.beige.opacity(0.85))
                    .accessibilityHidden(true)
                Text(text.title)
                    .font(.system(size: compact ? NotchSplashLayout.headerSize - 1 : NotchSplashLayout.headerSize,
                                  weight: .bold))
                    .foregroundStyle(NotchSplashPalette.beige)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            if failure != nil {
                reasonLine(clock)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { readings; tokens; memory; clockMark(clock) }
                    HStack(spacing: 8) { tokens; memory; clockMark(clock) }
                    HStack(spacing: 8) { tokens; clockMark(clock) }
                    clockMark(clock)
                }
            }
            stopMark
        }
        .frame(height: NotchSplashLayout.headerHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.title)
    }

    /// The widths a line with a reason for a stopped reading comes in: the
    /// reason first, and only as a last resort no reason at all.
    private func reasonLine(_ clock: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { readings; tokens; memory; clockMark(clock) }
            HStack(spacing: 8) { readings; memory; clockMark(clock) }
            HStack(spacing: 8) { readings; clockMark(clock) }
            HStack(spacing: 8) { tokens; clockMark(clock) }
            clockMark(clock)
        }
    }

    /// The reading's own state, said once: what the polling is doing now.
    @ViewBuilder private var readings: some View {
        if let failure {
            Text(failureText(failure))
                .font(.system(size: NotchSplashLayout.readingSize))
                .foregroundStyle(NotchSplashPalette.amber)
                .lineLimit(1)
                .help(failureText(failure))
        } else if isMonitoring {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .semibold))
                Text(text.monitoring)
                    .font(.system(size: NotchSplashLayout.readingSize, weight: .medium))
            }
            .foregroundStyle(NotchSplashPalette.green)
            .lineLimit(1)
            .accessibilityLabel(text.monitoring)
        }
    }

    /// Tokens in and out, as the reference writes them: an up arrow and a
    /// down arrow, in blue and in green.
    @ViewBuilder private var tokens: some View {
        if let status {
            HStack(spacing: 5) {
                tokenMark("arrow.up", NotchSplashSupport.tokensText(status.metrics.prefillInputTokens),
                          NotchSplashPalette.blue, text.inputTokens)
                tokenMark("arrow.down", NotchSplashSupport.tokensText(status.metrics.decodeOutputTokens),
                          NotchSplashPalette.green, text.outputTokens)
            }
        }
    }

    private func tokenMark(_ symbol: String, _ value: String, _ color: Color, _ label: String) -> some View {
        HStack(spacing: 1) {
            Image(systemName: symbol).font(.system(size: 8, weight: .heavy))
            Text(value).font(.system(size: NotchSplashLayout.readingSize, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    /// The cache's own bytes, the memory in use, and the governor's limit:
    /// three numbers, and the unit on the last, as the reference writes them.
    ///
    /// The first two are written in purple and the limit in orange, and each
    /// carries its own warning colour: the cache when its pages run short,
    /// the charge when the governor is nearly spent.
    @ViewBuilder private var memory: some View {
        if let status, let memory = NotchSplashHeaderMemory(status: status) {
            HStack(spacing: 3) {
                Text(memory.active)
                    .foregroundStyle(NotchSplashPalette.tone(
                        NotchSplashSupport.kvTone(pagesFree: status.kv.pagesFree,
                                                  pagesTotal: status.kv.pagesTotal,
                                                  spilling: isSpilling,
                                                  reservationFailures: status.kv.reservationFailures)))
                Text("/").foregroundStyle(.white.opacity(0.4))
                Text(memory.used)
                    .foregroundStyle(NotchSplashPalette.tone(
                        NotchSplashSupport.governorUtilizationTone(
                            NotchSplashSupport.governorUtilization(chargedBytes: status.governor.chargedBytes,
                                                                   limitBytes: status.governor.limitBytes))))
                Text("/").foregroundStyle(.white.opacity(0.4))
                Text(memory.limit)
                    .foregroundStyle(NotchSplashPalette.tone(headroomTone(status),
                                                             reference: NotchSplashPalette.orange))
                if let unit = memory.unit {
                    Text(unit).foregroundStyle(NotchSplashPalette.tone(headroomTone(status),
                                                                       reference: NotchSplashPalette.orange))
                }
            }
            .font(.system(size: NotchSplashLayout.readingSize, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([text.kvCache, text.memoryUsed, text.governorLimit]
                .joined(separator: " / "))
            .accessibilityValue(memory.spoken)
            .help("\(text.kvCache) \(memory.active) / \(text.memoryUsed) \(memory.used) / \(text.governorLimit) \(memory.limit)")
        }
    }

    /// How close the governor's charge sits to its limit, told by the colour
    /// of the limit itself: orange while there is room, amber and red as the
    /// room goes.
    private func headroomTone(_ status: NotchSplashStatus) -> NotchSplashTone {
        NotchSplashSupport.memoryPressureTone(headroomPercent: NotchSplashSupport.governorHeadroom(
            chargedBytes: status.governor.chargedBytes, limitBytes: status.governor.limitBytes))
    }

    /// The task's clock. It belongs to the task: nothing at all before a
    /// request is seen, running while it is, frozen at its length after.
    private func clockMark(_ value: String) -> some View {
        Group {
            if case .running(_, let startedAt) = phase, isMonitoring {
                TimelineView(.periodic(from: Date(timeIntervalSinceNow: 1), by: 1)) { _ in
                    clockText(NotchSplashSupport.taskClock(max(0, Date().timeIntervalSince(startedAt))))
                }
            } else {
                clockText(value)
            }
        }
    }

    private func clockText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: NotchSplashLayout.readingSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(NotchSplashPalette.beige)
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: value)
            .accessibilityLabel(text.taskTime)
            .accessibilityValue(value)
    }

    /// The mark that ends the session. It stops the reading and asks nothing
    /// of Splash: a generation already running there keeps running.
    @ViewBuilder private var stopMark: some View {
        if let onStop, isMonitoring {
            // The same round plate the Explorer's controls and the timer card
            // wear: a lit circle under the mark, the circle lighting further
            // under the pointer. The mark's job is unchanged - the way out of
            // the reading, and nothing else.
            NotchCircularIconButton(symbol: "xmark", title: text.stop,
                                    side: NotchDashboardLayout.transportMarkSide - 4, filled: true,
                                    tint: NotchSplashPalette.beige, action: onStop)
                .accessibilityIdentifier("notch.splash.stop")
        }
    }

    // MARK: The four readings, in one row

    private var metrics: some View {
        HStack(spacing: NotchSplashLayout.metricSpacing) {
            NotchSplashMetricCard(
                label: text.decode,
                value: NotchSplashSupport.speedText(status?.metrics.decodeTokensPerSecond),
                unit: text.tokensPerSecond,
                tone: NotchSplashSupport.decodeTone(status?.metrics.decodeTokensPerSecond))
            NotchSplashMetricCard(
                label: text.prefill,
                value: NotchSplashSupport.speedText(status?.metrics.prefillTokensPerSecond),
                unit: text.tokensPerSecond,
                tone: NotchSplashSupport.prefillTone(status?.metrics.prefillTokensPerSecond))
            NotchSplashMetricCard(
                label: text.ttft,
                value: NotchSplashSupport.ttftText(
                    NotchSplashSupport.ttftSeconds(milliseconds: status?.metrics.ttftMilliseconds)),
                unit: text.timeToFirstToken,
                tone: NotchSplashSupport.ttftTone(
                    NotchSplashSupport.ttftSeconds(milliseconds: status?.metrics.ttftMilliseconds)))
            NotchSplashMetricCard(
                label: text.cacheHitRate,
                value: NotchSplashSupport.percentText(
                    NotchSplashSupport.cacheHitPercent(hits: status?.cache.hits,
                                                       requests: status?.cache.requests,
                                                       reportedRate: status?.cache.reportedRate)),
                tone: NotchSplashSupport.cacheTone(
                    NotchSplashSupport.cacheHitPercent(hits: status?.cache.hits,
                                                       requests: status?.cache.requests,
                                                       reportedRate: status?.cache.reportedRate))) {
                counts
            }
        }
        .frame(height: NotchSplashLayout.metricCardHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.title)
    }

    /// The cache's counters under its rate: the hits and the requests, both
    /// named, both counted, neither invented.
    @ViewBuilder private var counts: some View {
        if let status, let hits = status.cache.hits, let requests = status.cache.requests {
            (Text("\(hits)").foregroundStyle(NotchSplashPalette.green)
             + Text(" / ").foregroundStyle(.white.opacity(0.45))
             + Text("\(requests)").foregroundStyle(NotchSplashPalette.blue))
                .lineLimit(1)
                .accessibilityLabel(text.hitsAndRequests(hits, requests))
        } else {
            Text(text.hitsAndRequests(0, 0))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
    }

    private func failureText(_ failure: NotchSplashFailure) -> String {
        switch failure {
        case .notConfigured: return text.noAddress
        case .unreachable: return text.noAnswer(address)
        case .status(let code): return text.serverAnswered(code)
        case .unreadable: return text.unreadable
        case .stale: return text.staleAnswer
        }
    }
}

/// The three memory numbers of the header, in one unit where they share one.
private struct NotchSplashHeaderMemory: Equatable {
    let active: String
    let used: String
    let limit: String
    let unit: String?
    let spoken: String

    init?(status: NotchSplashStatus) {
        let bytes: [Int64?] = [status.kv.activeBytes, status.memoryActual.currentBytes, status.governor.limitBytes]
        guard bytes.contains(where: { $0 != nil }) else { return nil }
        let readings = bytes.map { NotchSplashSupport.bytesText($0) }
        // One unit for all three when they agree, so the line reads as the
        // reference draws it; each of its own when they do not.
        let units = Set(readings.compactMap { $0?.unit })
        let shared = units.count == 1 ? units.first : nil
        let values = readings.map { $0?.value ?? NotchSplashSupport.placeholder }
        active = values[0]
        used = values[1]
        limit = values[2]
        unit = shared
        self.spoken = [values[0], values[1], values[2]].joined(separator: " / ")
    }
}

/// One reading: its name, its figure in the colour its threshold chose, and a
/// line under it.
struct NotchSplashMetricCard<Footer: View>: View {
    let label: String
    let value: String
    var unit: String?
    var tone: NotchSplashTone
    @ViewBuilder var footer: () -> Footer

    init(label: String, value: String, unit: String? = nil, tone: NotchSplashTone,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.label = label
        self.value = value
        self.unit = unit
        self.tone = tone
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: NotchSplashLayout.labelSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(value)
                .font(.system(size: NotchSplashLayout.valueSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NotchSplashPalette.tone(tone))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Group {
                if let unit {
                    Text(unit)
                        .font(.system(size: NotchSplashLayout.footerSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    footer()
                        .font(.system(size: NotchSplashLayout.footerSize))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(NotchSplashLayout.padding - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: NotchSplashLayout.metricCardHeight)
        .modifier(NotchControlSurface(cornerRadius: NotchSplashLayout.metricCornerRadius,
                                      interactive: false, fillOpacity: 0.075))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

extension NotchSplashMetricCard where Footer == EmptyView {
    init(label: String, value: String, unit: String? = nil, tone: NotchSplashTone) {
        self.init(label: label, value: value, unit: unit, tone: tone) { EmptyView() }
    }
}

// MARK: - The page

/// The dedicated page: the interval to read at, and the dashboard.
///
/// The page is reached from Explore and from the dashboard's card, and it
/// opens the way every section page opens: the island's row leads with the way
/// back and the page's name, and ends with Start. Reading begins there and
/// goes on while the page is away, so the way back is the dashboard with a new
/// card in it and the same numbers in that card.
struct NotchSplashView: View {
    let size: CGSize
    @ObservedObject private var service = NotchSplashService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchSplashEnabled) private var enabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: NotchSplashStrings { FeatureStrings.notchSplash(l10n.language) }

    private var interval: Binding<Int> {
        Binding(get: { service.intervalSeconds },
                set: { value in withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
                    service.setInterval(value)
                } })
    }

    var body: some View {
        Group {
            if enabled, service.showsDashboard {
                dashboard
            } else {
                setup
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tint(.mint)
        // The island's row leads with the way back and the page's name, as
        // every page's does, and ends with the one action of the moment.
        .notchBand(trailing: {
            if service.isMonitoring {
                NotchIconButton(symbol: "xmark", title: text.stop) { service.stop() }
            } else {
                startButton
            }
        })
    }

    /// The reading and the interval it is read at. The interval stays on the
    /// page while the reading runs: it is the page's own choice, and the
    /// running session takes a new value at once.
    private var dashboard: some View {
        VStack(alignment: .leading, spacing: NotchLayout.rowSpacing) {
            intervalRow
            NotchSplashDashboardCard(
                snapshot: service.snapshot,
                phase: service.phase,
                elapsed: service.elapsed(),
                isMonitoring: service.isMonitoring,
                isSpilling: service.isSpilling,
                failure: service.failure,
                address: service.endpointDescription,
                onStop: service.isMonitoring ? { service.stop() } : nil)
            statusLine
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.title)
    }

    /// The interval, before anything is read, above what to do.
    private var setup: some View {
        VStack(alignment: .leading, spacing: NotchLayout.rowSpacing) {
            intervalRow
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: NotchModule.splash.symbol)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.mint.opacity(0.75))
                Text(text.setupHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                if !NotchSplashSupport.isEnabled() {
                    NotchPillButton(title: text.openSettings, prominent: true) {
                        NotchService.shared.openSettings(showing: .splash)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The ruler, at the island's own scale for whole seconds, beside the
    /// value it rests on. The same control as the timer's: the same dragging,
    /// the same wheel, the same tick through the trackpad.
    private var intervalRow: some View {
        HStack(spacing: 12) {
            NotchValueRuler(value: interval, scale: .seconds, label: text.interval, tint: .systemMint,
                            valueText: { text.intervalLabel($0) },
                            labelText: { NotchSplashSupport.tickIntervalText($0) })
                .frame(maxWidth: .infinity)
                .frame(height: rulerHeight)
            Text(NotchSplashSupport.intervalText(service.intervalSeconds))
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.mint)
                .lineLimit(1)
                .frame(minWidth: 46, alignment: .trailing)
                .accessibilityLabel(text.interval)
                .accessibilityValue(text.intervalLabel(service.intervalSeconds))
        }
        .frame(height: rulerHeight)
        .accessibilityHint(text.intervalHint)
    }

    private var rulerHeight: CGFloat {
        NotchLayout.timerRulerHeight(mode: .timer, height: size.height)
    }

    /// A small capsule in the island's top row, in the page's own colour.
    private var startButton: some View {
        Button { service.start() } label: {
            Text(text.start)
                .font(.system(size: NotchTimerSupport.StartButton.labelSize, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, NotchTimerSupport.StartButton.padding)
                .frame(height: NotchLayout.timerStartHeight)
                .foregroundStyle(.mint)
                .background(.mint.opacity(0.18), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: NotchLayout.timerStartHeight / 2))
        .disabled(!NotchSplashSupport.isEnabled() || NotchSplashSupport.endpoint() == nil)
        .help(text.setupHint)
        .accessibilityIdentifier("notch.splash.start")
    }

    /// The address being read, and any word about why it is not answering.
    @ViewBuilder private var statusLine: some View {
        HStack(spacing: 8) {
            Text(service.endpointDescription)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let outcome = service.taskOutcome {
                Text(outcomeTitle(outcome))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(outcome == .completed ? NotchSplashPalette.green : NotchSplashPalette.amber)
                    .lineLimit(1)
            }
            Text(text.intervalLabel(service.intervalSeconds))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func outcomeTitle(_ outcome: NotchSplashTaskTracker.Outcome) -> String {
        switch outcome {
        case .completed: return text.notifyCompletedTitle
        case .failed: return text.notifyFailedTitle
        case .cancelled: return text.notifyCancelledTitle
        // A task the reading cannot account for: no news about it is claimed.
        case .lost: return text.staleAnswer
        }
    }
}
