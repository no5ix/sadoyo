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

/// The dashboard's card, of the reference's four parts in the reference's
/// order: the header, four metric charts in one row, the memory and its
/// governor, and the trend of thirty days.
///
/// The page and the dashboard's Live Activities section draw this one view, so
/// the same numbers, the same words, the same thresholds and the same colours
/// answer in both places. Nothing in the view reads a server: it is given a
/// reading and the recorded past, and it says what it can from those.
///
/// Every part is drawn from what has been measured. A metric the server has
/// not answered shows no line and says it has nothing; a day the app was not
/// measuring has no bar; a period before the app began measuring is left empty
/// rather than given a shape. The colours are kept honest in a second sense
/// too: a figure takes the colour of how it reads, a chart line keeps the
/// colour of the metric it belongs to, and the two are never merged.
///
/// The card is an interactive card of the dashboard's own kind: the pointer
/// lights its surface, as it lights the players' and the timer's cards, and a
/// click on it opens the section's page.
struct NotchSplashDashboardCard: View {
    let snapshot: NotchSplashSnapshot?
    let phase: NotchSplashTaskTracker.Phase
    /// The clock's value at the moment the card is drawn.
    var elapsed: TimeInterval = 0
    /// The task's tokens, as the tracker counted them: the difference the
    /// engine's cumulative counters have made across this task, and frozen at
    /// its end.
    var taskTokens: NotchSplashTaskTracker.TaskTokens = .zero
    var isMonitoring = false
    var isSpilling = false
    /// The measured past: the readings the four charts draw, and the daily
    /// tokens the trend draws.
    var history: NotchSplashHistory = .empty
    /// Why the reading stopped answering, while it is being watched.
    var failure: NotchSplashFailure?
    /// The server being read, named when it does not answer.
    var address: String = NotchSplashSupport.placeholder
    /// The way out of the session, offered in the header as the reference draws it.
    var onStop: (() -> Void)?
    var compact = false
    /// Whether a click on the card leads somewhere. On the section's own page
    /// the card has nowhere to go, and a card should not promise a journey it
    /// cannot take.
    var canOpenSection = true
    /// The moment the charts end, so the cards and the clock answer the same
    /// instant.
    var now: Date = Date()

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var notch = NotchService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    /// The day of the trend the pointer rests on, which the card's caption
    /// names with its two counts. The agents' chart's own rule: the day is a
    /// value and not a view, so leaving the bars clears the line again.
    @State private var hoveredDay: Date?
    private var text: NotchSplashStrings { FeatureStrings.notchSplash(l10n.language) }
    private var status: NotchSplashStatus? { snapshot?.status }
    private var metrics: NotchSplashStatus.Metrics? { status?.metrics }
    private var series: [NotchSplashSample] { history.series(endingAt: now) }
    private var days: [NotchSplashDay] { history.trend(now: now) }

    /// The card's own rule, asked once: the page shows the thirty days, and the
    /// compact card of the dashboard's Live Activities section does not. The
    /// section's height is measured by `NotchSplashLayout.cardHeight`, which
    /// answers the same question the same way, so the card the page measures is
    /// the card the page draws.
    private var showsTrend: Bool { !compact }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchSplashLayout.sectionSpacing) {
            header
            charts
            memoryCard
            // Thirty days of tokens, and the hovering that reads one of them:
            // the card is the page's own reading, with room to be pointed at.
            // The dashboard's Live Activities card is a glance at what is
            // running now, and a chart of a month does not belong in a glance.
            if showsTrend {
                trendCard
            }
        }
        .padding(NotchSplashLayout.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(NotchControlSurface(cornerRadius: NotchSplashLayout.cornerRadius,
                                      selected: hovered, interactive: canOpenSection,
                                      fillOpacity: NotchDashboardLayout.fillOpacity))
        .contentShape(RoundedRectangle(cornerRadius: NotchSplashLayout.cornerRadius, style: .continuous))
        .onHover { hovered = $0 }
        .modifier(NotchSplashCardTap(enabled: canOpenSection) { notch.select(.splash) })
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.title)
        .accessibilityIdentifier("notch.splash.card")
    }

    // MARK: The header, on one line

    /// The dashboard's mark and name on the left, and on the same line the
    /// tokens this task has moved, the task's clock, and the lit circle that
    /// ends the reading.
    ///
    /// The mark before the name is the Codex mark the AI page draws - the same
    /// mark the gallery's tile wears and the same view of it, at the size of
    /// this line - so the section is known by one shape wherever it shows. The
    /// mark and the name are one line with the page's own gap between them, at
    /// every size the card is drawn at: the compact card of the dashboard's Live
    /// Activities and the page's whole card are the same line, and a section
    /// whose name is crowded against its mark in one place and not the other is
    /// two sections.
    ///
    /// The words the reference does not draw are not drawn here either: the old
    /// line of compact resource values lives in the memory card now, where there
    /// is room for all three of them, their units and their bar.
    private var header: some View {
        let clock = NotchSplashSupport.taskClock(elapsed)
        return HStack(spacing: 6) {
            HStack(spacing: NotchLayout.sectionMarkTitleGap) {
                NotchSectionMark(module: .splash, size: compact ? NotchSplashLayout.titleIconSize - 1
                                                                : NotchSplashLayout.titleIconSize)
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
                // While a reading is not coming, the reason outranks totals
                // that are certainly out of date.
                reasonLine(clock)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { tokens; clockMark(clock) }
                    HStack(spacing: 8) { tokens }
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
            HStack(spacing: 8) { reason; tokens; clockMark(clock) }
            HStack(spacing: 8) { reason; clockMark(clock) }
            HStack(spacing: 8) { tokens; clockMark(clock) }
            reason
            clockMark(clock)
        }
    }

    /// Why the reading is not coming, in the room the line has for it.
    private var reason: some View {
        Text(failureText(failure ?? .unreachable))
            .font(.system(size: 9.5))
            .foregroundStyle(.white.opacity(0.68))
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize()
    }

    /// The tokens this task has moved, up for the in and down for the out, in
    /// the two colours the trend uses for the same two things.
    ///
    /// The task's own, and not the engine's: the engine counts tokens across
    /// its whole life, and a header is a glance at the work being timed. A new
    /// task begins at nothing, an intermediate request of the same task adds to
    /// what the task has already moved, and the end of the task freezes the
    /// figures beside the frozen clock. A restart, a reset counter, and a field
    /// the server does not report are all met with the task keeping what it
    /// measured: the header never shows a negative and never shows less than
    /// the task did.
    ///
    /// The trend's thirty days are not this line. A task beginning adds a task
    /// and takes no day away.
    @ViewBuilder private var tokens: some View {
        HStack(spacing: 8) {
            tokenPair(symbol: "arrow.up", value: NotchSplashSupport.tokensText(taskTokens.input),
                      tint: NotchSplashPalette.blue, name: text.inputTokens)
            tokenPair(symbol: "arrow.down", value: NotchSplashSupport.tokensText(taskTokens.output),
                      tint: NotchSplashPalette.green, name: text.outputTokens)
        }
        .font(.system(size: compact ? NotchSplashLayout.readingSize - 1.5 : NotchSplashLayout.readingSize,
                      weight: .medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text.inputTokens) \(NotchSplashSupport.tokensText(taskTokens.input)), "
            + "\(text.outputTokens) \(NotchSplashSupport.tokensText(taskTokens.output))")
    }

    private func tokenPair(symbol: String, value: String, tint: Color, name: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .semibold))
                .accessibilityHidden(true)
            Text(value).monospacedDigit()
        }
        .foregroundStyle(tint)
        .accessibilityLabel(name)
    }

    /// The task's clock. It belongs to the task: nothing at all before the
    /// engine has work, running while it does, frozen at its length after.
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
                                    tint: NotchSplashPalette.beige, lifts: false, action: onStop)
                .accessibilityIdentifier("notch.splash.stop")
        }
    }

    // MARK: The four charts, in one row

    /// Four cards, one row: the speed of the decode, the speed of the prefill,
    /// the first token's time, and the cache's hits. Each line keeps its
    /// metric's colour and each figure takes the colour of how it reads, so a
    /// card that reads badly is not also drawn in a colour that says so twice.
    private var charts: some View {
        let decode = metrics?.decodeTokensPerSecond
        let prefill = metrics?.prefillTokensPerSecond
        let ttft = NotchSplashSupport.ttftSeconds(milliseconds: metrics?.ttftMilliseconds)
        let cache = NotchSplashSupport.cacheHitPercent(hits: status?.cache.hits,
                                                      requests: status?.cache.requests,
                                                      reportedRate: status?.cache.reportedRate)
        return HStack(spacing: NotchSplashLayout.metricSpacing) {
            NotchSplashMetricCard(title: text.decode,
                                  values: series.compactMap(\.decode),
                                  line: NotchSplashPalette.orange,
                                  value: NotchSplashSupport.speedText(decode),
                                  unit: decode == nil ? nil : text.tokensPerSecond,
                                  tone: NotchSplashSupport.decodeTone(decode),
                                  empty: text.noMeasurements)
            NotchSplashMetricCard(title: text.prefill,
                                  values: series.compactMap(\.prefill),
                                  line: NotchSplashPalette.blue,
                                  value: NotchSplashSupport.speedText(prefill),
                                  unit: prefill == nil ? nil : text.tokensPerSecond,
                                  tone: NotchSplashSupport.prefillTone(prefill),
                                  empty: text.noMeasurements)
            NotchSplashMetricCard(title: text.ttft,
                                  values: series.compactMap(\.ttftSeconds),
                                  line: NotchSplashPalette.blue,
                                  value: NotchSplashSupport.ttftParts(ttft)?.value,
                                  unit: NotchSplashSupport.ttftParts(ttft)?.unit,
                                  tone: NotchSplashSupport.ttftTone(ttft),
                                  empty: text.noMeasurements)
            NotchSplashMetricCard(title: text.cacheHitRate,
                                  values: series.compactMap(\.cachePercent),
                                  line: NotchSplashPalette.green,
                                  value: NotchSplashSupport.percentText(cache),
                                  unit: nil,
                                  tone: NotchSplashSupport.cacheTone(cache),
                                  empty: text.noMeasurements) {
                counts
            }
        }
        .frame(height: NotchSplashLayout.metricCardHeight)
    }

    /// Under the cache's rate, the two counts it is made of, so a rate is
    /// never shown without the numbers behind it.
    @ViewBuilder private var counts: some View {
        if let hits = status?.cache.hits, let requests = status?.cache.requests {
            Text(text.hitsAndRequests(hits, requests))
                .font(.system(size: NotchSplashLayout.footerSize))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel(text.cacheHitRate)
        }
    }

    // MARK: The memory, and the governor's bar

    /// Three numbers and a bar, in one row under the card's name: the cache's
    /// own, the memory the governor charges, the governor's limit, and the
    /// charge over the limit.
    ///
    /// The name and the three readings are one line, because the card is a
    /// glance and not a page: the name says what the numbers are, and the
    /// numbers stand under nothing, in the room the width of the page gives
    /// them. The bar is under them, full width, because a bar is read at the
    /// length it is drawn at.
    ///
    /// The bar and the memory's colour are the same rule, so the number, the
    /// bar and the colour of a card cannot tell three stories. No limit, and a
    /// limit of nothing, leave the bar empty: a missing number is drawn as
    /// missing, and not as a bar of some length.
    private var memoryCard: some View {
        let utilization = NotchSplashSupport.governorUtilization(
            chargedBytes: status?.governor.chargedBytes, limitBytes: status?.governor.limitBytes)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: NotchSplashLayout.metricSpacing) {
                Text(text.memoryAndKVCache)
                    .font(.system(size: NotchSplashLayout.sectionTitleSize, weight: .semibold))
                    .foregroundStyle(NotchSplashPalette.beige.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .fixedSize()
                Spacer(minLength: 6)
                // The three readings, named, at the same size and in one row:
                // the name of each is under its figure, so the line stays one
                // line at every width the page draws this card at.
                memoryColumn(title: text.kvCache,
                             parts: NotchSplashSupport.bytesText(status?.kv.activeBytes),
                             tone: NotchSplashPalette.tone(kvTone, reference: NotchSplashPalette.purple),
                             note: kvShortage)
                memoryColumn(title: text.memoryUsed,
                             parts: NotchSplashSupport.bytesText(status?.governor.chargedBytes),
                             tone: NotchSplashPalette.tone(
                                 NotchSplashSupport.governorUtilizationTone(utilization)),
                             note: nil)
                memoryColumn(title: text.governorLimit,
                             parts: NotchSplashSupport.bytesText(status?.governor.limitBytes),
                             tone: NotchSplashPalette.tone(headroomTone,
                                                           reference: NotchSplashPalette.orange),
                             note: nil)
            }
            utilizationRow(utilization)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: NotchSplashLayout.memoryCardHeight)
        .background(.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: NotchSplashLayout.metricCornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.memoryAndKVCache)
    }

    /// One reading of the memory's three: its figure and its unit, and its
    /// name under them. The name goes under the figure because the three
    /// readings share the card's one line with the card's own name: a name over
    /// a figure would make two lines of a line, and the card is measured to one.
    private func memoryColumn(title: String, parts: (value: String, unit: String)?,
                              tone: Color, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(parts?.value ?? NotchSplashSupport.placeholder)
                    .font(.system(size: NotchSplashLayout.memoryValueSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(parts?.unit ?? "")
                    .font(.system(size: NotchSplashLayout.memoryUnitSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize()
            }
            // The name, and the shortage when there is one: the colour is the
            // glance, these are the explanation.
            Text(note ?? title)
                .font(.system(size: note == nil ? NotchSplashLayout.memoryLabelSize
                                                : NotchSplashLayout.captionSize - 0.5))
                .foregroundStyle(note == nil ? Color.white.opacity(0.55) : NotchSplashPalette.amber)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    /// The bar, its name, and the number beside it.
    private func utilizationRow(_ utilization: Double?) -> some View {
        HStack(spacing: 7) {
            Text(text.utilization)
                .font(.system(size: NotchSplashLayout.captionSize))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize()
            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    if let utilization {
                        Capsule()
                            .fill(NotchSplashPalette.tone(NotchSplashSupport.governorUtilizationTone(utilization)))
                            .frame(width: max(2, bar.size.width * min(100, max(0, utilization)) / 100))
                    }
                }
            }
            .frame(height: NotchSplashLayout.utilizationBarHeight)
            Text(utilization.map { NotchSplashSupport.percentText($0) } ?? NotchSplashSupport.placeholder)
                .font(.system(size: NotchSplashLayout.captionSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(NotchSplashPalette.tone(NotchSplashSupport.governorUtilizationTone(utilization)))
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text.utilization)
        .accessibilityValue(utilization.map { NotchSplashSupport.percentText($0) } ?? NotchSplashSupport.placeholder)
    }

    /// The cache's colour: purple while the pages are there, amber when they
    /// run short, red while the server spills or cannot reserve.
    private var kvTone: NotchSplashTone {
        NotchSplashSupport.kvTone(pagesFree: status?.kv.pagesFree, pagesTotal: status?.kv.pagesTotal,
                                  spilling: isSpilling,
                                  reservationFailures: status?.kv.reservationFailures)
    }

    /// The shortage, named in words when there is one: a colour alone is not
    /// an explanation, and the cache's purple saying nothing is the point of
    /// the colour.
    private var kvShortage: String? {
        switch kvTone {
        case .amber: return text.kvScarce
        case .red: return text.kvSpilling
        default: return nil
        }
    }

    /// What the reading's failure is called, in the words of the language and
    /// with the address that did not answer.
    private func failureText(_ failure: NotchSplashFailure) -> String {
        switch failure {
        case .notConfigured: return text.noAddress
        case .unreachable: return text.noAnswer(address)
        case .status(let code): return text.serverAnswered(code)
        case .unreadable: return text.unreadable
        case .stale: return text.staleAnswer
        }
    }

    /// How close the governor's charge sits to its limit, told by the colour
    /// of the limit itself: orange while there is room, amber and red as the
    /// room goes.
    private var headroomTone: NotchSplashTone {
        NotchSplashSupport.memoryPressureTone(headroomPercent: NotchSplashSupport.governorHeadroom(
            chargedBytes: status?.governor.chargedBytes, limitBytes: status?.governor.limitBytes))
    }

    // MARK: Thirty days of tokens

    /// The last thirty days, of the agents' trend chart: two colours stacked
    /// in a bar a day, the period's total above the bars, the dates under
    /// them, and the two colours named below.
    ///
    /// The bars are pointed at, as the agents' chart is pointed at: resting on
    /// a day turns the line above the bars from the period's total into that
    /// day's own tokens - the date, the tokens in and the tokens out, each named
    /// and each in the colour of its part of the stack, and counted whole,
    /// because a day read at a point is a day read exactly. The other bars dim
    /// the same way, so the two charts answer a pointer alike.
    ///
    /// A day is the difference of the engine's counters across that day, and
    /// not the total the engine has reached, so a quiet day is a day of
    /// nothing and a restart does not move the engine's whole life into today.
    /// Where nothing has ever been measured the card says so, and draws no
    /// bars and no dates: a day is never invented, and a day with nothing in it
    /// is drawn as nothing.
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Text(text.trend)
                    .font(.system(size: NotchSplashLayout.sectionTitleSize, weight: .semibold))
                    .foregroundStyle(NotchSplashPalette.beige.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 6)
                // The card's one line of words: the period and its tokens at
                // rest, the pointed-at day and its two counts under the pointer.
                if let day = hoveredDay, let entry = days.first(where: { $0.start == day }) {
                    hoveredDayCaption(entry)
                } else {
                    Text(text.daysAndTokens(days.count, NotchSplashSupport.tokensText(history.total(of: days))))
                        .font(.system(size: NotchSplashLayout.captionSize, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if history.hasTokens {
                NotchTrendBars(series: [
                    .init(tint: NotchSplashPalette.blue, values: days.map { Double($0.input) }),
                    .init(tint: NotchSplashPalette.green, values: days.map { Double($0.output) }),
                ], dates: days.map(\.start), hoverable: true, hovered: hoveredDay) { hovered in
                    if hoveredDay != hovered { hoveredDay = hovered }
                }
                .frame(maxWidth: .infinity)
                .frame(height: NotchSplashLayout.trendBarsHeight)
                .animation(reduceMotion ? nil : .smooth(duration: 0.15), value: hoveredDay)
                dayLabels
            } else {
                Text(text.noHistoryYet)
                    .font(.system(size: NotchSplashLayout.captionSize))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            trendLegend
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: NotchSplashLayout.trendCardHeight)
        .background(.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: NotchSplashLayout.metricCornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.trend)
    }

    /// The day the pointer rests on, counted: its date, the tokens in, the
    /// tokens out. Whole numbers, because a day named at a point is not
    /// sketched in thousands, and the two counts in the two colours the bar
    /// above is stacked in, so the line and the bar are one statement.
    private func hoveredDayCaption(_ day: NotchSplashDay) -> some View {
        HStack(spacing: 6) {
            Text(day.start.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: NotchSplashLayout.captionSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize()
            tokenPair(symbol: "arrow.up", value: exactTokens(day.input),
                      tint: NotchSplashPalette.blue, name: text.inputSeries)
            tokenPair(symbol: "arrow.down", value: exactTokens(day.output),
                      tint: NotchSplashPalette.green, name: text.outputSeries)
        }
        .font(.system(size: NotchSplashLayout.captionSize, weight: .medium))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.start.formatted(.dateTime.month(.abbreviated).day())), "
            + "\(text.inputSeries) \(exactTokens(day.input)), \(text.outputSeries) \(exactTokens(day.output))")
    }

    /// A day's count, whole. The header's totals are written short, because
    /// they are read at a glance; a day the pointer is on is read exactly.
    private func exactTokens(_ tokens: Int64) -> String {
        tokens.formatted(.number.locale(l10n.language.formattingLocale()))
    }

    /// The first day, a middle one, and the last: dates enough to say what the
    /// bars span, few enough to stay out of the bars' way.
    @ViewBuilder private var dayLabels: some View {
        if let first = days.first, let last = days.last, days.count > 2 {
            HStack {
                dayLabel(first)
                Spacer(minLength: 4)
                dayLabel(days[days.count / 2])
                Spacer(minLength: 4)
                dayLabel(last)
            }
            .font(.system(size: NotchSplashLayout.captionSize - 0.5))
            .foregroundStyle(.white.opacity(0.45))
            .accessibilityHidden(true)
        }
    }

    private func dayLabel(_ day: NotchSplashDay) -> some View {
        Text(day.start.formatted(.dateTime.month(.abbreviated).day()))
            .fixedSize()
            .lineLimit(1)
    }

    private var trendLegend: some View {
        HStack(spacing: 10) {
            legendMark(text.inputSeries, NotchSplashPalette.blue)
            legendMark(text.outputSeries, NotchSplashPalette.green)
            Spacer(minLength: 0)
        }
        .font(.system(size: NotchSplashLayout.captionSize))
    }

    private func legendMark(_ name: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint.opacity(0.95))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(name)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityLabel(name)
    }
}

/// A card's way to the section's page: a click, and the same thing for a
/// voice, on a card that has somewhere to go.
private struct NotchSplashCardTap: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        // The card is drawn in both cases: a card that cannot be clicked is
        // still a reading, and dropping it would leave its page empty.
        if enabled {
            content
                .onTapGesture(perform: action)
                .accessibilityAction { action() }
        } else {
            content
        }
    }
}

// MARK: - One metric's chart

/// A metric's card: its name, its figure in the colour of how it reads, the
/// unit it is counted in, the line of its last half hour in the metric's own
/// colour, and a line for the counts a rate is made of.
///
/// The two colours are kept apart on purpose. The line belongs to the metric
/// and says which of the four this is; the figure belongs to the threshold and
/// says how it reads. A card that wore its threshold's colour twice would
/// shout one piece of news in two voices, and a card whose line changed colour
/// with its figure could not be recognised by its shape and colour at a glance.
struct NotchSplashMetricCard<Footer: View>: View {
    let title: String
    /// The window's measurements, oldest first; empty when nothing has been
    /// measured, which is drawn as nothing and not as a flat line.
    let values: [Double]
    /// The line's colour, the metric's own.
    let line: Color
    let value: String?
    let unit: String?
    let tone: NotchSplashTone
    /// What to say while there is nothing to draw.
    var empty: String? = nil
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: NotchSplashLayout.labelSize))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? NotchSplashSupport.placeholder)
                    .font(.system(size: NotchSplashLayout.valueSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(NotchSplashPalette.tone(tone))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.system(size: NotchSplashLayout.footerSize))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize()
                }
            }
            NotchSparkline(values: values, tint: line, height: NotchSplashLayout.sparklineHeight)
            Group {
                if values.isEmpty, let empty {
                    Text(empty)
                        .font(.system(size: NotchSplashLayout.footerSize))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    footer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: NotchSplashLayout.metricCardHeight)
        .background(.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: NotchSplashLayout.metricCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

extension NotchSplashMetricCard where Footer == EmptyView {
    init(title: String, values: [Double], line: Color, value: String?, unit: String?,
         tone: NotchSplashTone, empty: String? = nil) {
        self.init(title: title, values: values, line: line, value: value, unit: unit, tone: tone,
                  empty: empty, footer: { EmptyView() })
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

    /// Whether the page has a reading to draw: a session asking the server,
    /// a reading it has, or a task's phase to report. The page's own rule, in
    /// the same words the row's action uses, so the row and the page agree the
    /// moment Start is pressed.
    private var showsReading: Bool {
        service.isMonitoring || service.snapshot != nil || service.phase != .idle
    }

    private var interval: Binding<Int> {
        Binding(get: { service.intervalSeconds },
                set: { value in withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
                    service.setInterval(value)
                } })
    }

    var body: some View {
        Group {
            if enabled, showsReading {
                dashboard
            } else {
                setup
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tint(.mint)
        // The island's row leads with the way back and the page's name, as
        // every page's does, and ends with the one action of the moment: Start
        // before a reading, and nothing while one runs. The way out of a
        // session is the card's own corner, which is where the reading is read;
        // the row kept a second mark of the same ending in the island's corner.
        .notchBand(trailing: {
            if !service.isMonitoring {
                startButton
            }
        })
    }

    /// The reading, with the interval it is read at above it while nothing is
    /// being read. The ruler is the page's own choice before a session and
    /// after one, and a running session takes a new value at once, so the page
    /// of a reading draws its card and keeps no room above it for a control the
    /// person is not setting.
    private var dashboard: some View {
        VStack(alignment: .leading, spacing: NotchLayout.rowSpacing) {
            if !service.isMonitoring { intervalRow }
            NotchSplashDashboardCard(
                snapshot: service.snapshot,
                phase: service.phase,
                elapsed: service.elapsed(),
                taskTokens: service.taskTokens,
                isMonitoring: service.isMonitoring,
                isSpilling: service.isSpilling,
                history: service.history,
                failure: service.failure,
                address: service.endpointDescription,
                onStop: service.isMonitoring ? { service.stop() } : nil,
                // The card is already on the page it would lead to.
                canOpenSection: false)
            statusLine
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.title)
    }

    /// The interval, before anything is read, and nothing under it.
    ///
    /// The page's header says what the page is, the ruler says the interval and
    /// the value it rests on, and the top row carries Start. What used to sit
    /// under the ruler - the section's mark at display size and two lines of
    /// what Start does and does not send - repeated the header and the button
    /// in a bigger voice, and made the page reserve room for a block of words.
    /// Where the engine is switched off in Settings, the one way on from here is
    /// Settings, so that ask stays.
    private var setup: some View {
        VStack(alignment: .leading, spacing: NotchLayout.rowSpacing) {
            intervalRow
            if !NotchSplashSupport.isEnabled() {
                NotchPillButton(title: text.openSettings, prominent: true) {
                    NotchService.shared.openSettings(showing: .splash)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    /// Any word about why the reading is not answering, and the last task's
    /// outcome, and nothing else.
    ///
    /// The address and the interval are not written here. Both are settings,
    /// and the page is a reading: the address is set on the app's Settings
    /// screen, and the interval is read there and, before anything is read, on
    /// this page's own ruler. What the engine has just done is the page's
    /// business, and a completed task asked for no room to be read in.
    @ViewBuilder private var statusLine: some View {
        HStack(spacing: 8) {
            if let outcome = service.taskOutcome {
                Text(outcomeTitle(outcome))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(outcome == .completed ? NotchSplashPalette.green : NotchSplashPalette.amber)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
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
