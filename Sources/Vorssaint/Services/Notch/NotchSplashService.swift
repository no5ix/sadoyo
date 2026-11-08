// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// Reads Splash's `/status` on the interval a person chose, and keeps the
/// dashboard's two states apart: the monitoring the Start button began, and
/// the request the island times.
///
/// The monitoring is a reader only. It never sends Splash anything but the
/// request for a status, so starting it generates nothing, and stopping it
/// cancels nothing — a generation already running in Splash goes on running.
///
/// Reading is asked off the main thread and reported on the main thread, and
/// the reading is turned into decisions by `NotchSplashTaskTracker`, which
/// holds no thread and no request of its own.
final class NotchSplashService: ObservableObject {
    static let shared = NotchSplashService()

    /// The last reading that arrived, kept after monitoring ends so a frozen
    /// dashboard can be read.
    @Published private(set) var snapshot: NotchSplashSnapshot?
    /// Whether the polling is running, which is the Live Activity card's rule.
    @Published private(set) var isMonitoring = false
    /// The task being timed: idle, running, or finished and frozen.
    @Published private(set) var phase: NotchSplashTaskTracker.Phase = .idle
    /// Why the last reading did not arrive, while the polling is running.
    @Published private(set) var failure: NotchSplashFailure?
    /// The interval the polling runs at, in whole seconds.
    @Published private(set) var intervalSeconds: Int

    /// A reading of the server's spilling and reservation pressure, which
    /// only the tracker can tell from two readings in a row.
    private(set) var isSpilling = false
    private(set) var reservationFailures: Int?

    private var tracker = NotchSplashTaskTracker()
    private var announcements = NotchSplashAnnouncements()
    private var loop: Task<Void, Never>?
    private var generation = UUID()
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        configuration.waitsForConnectivity = false
                session = URLSession(configuration: configuration)
        intervalSeconds = NotchSplashSupport.savedInterval()
    }

    // MARK: What the page and the card ask for

    /// The clock's value at a moment: a running task's length, a finished
    /// task's frozen length, nothing with no task.
    func elapsed(at date: Date = Date()) -> TimeInterval { tracker.elapsed(at: date) }
    var isTaskRunning: Bool { tracker.isRunning }
    var isTaskFinished: Bool { tracker.isFinished }
    var trackedID: String? { tracker.trackedID }
    var taskOutcome: NotchSplashTaskTracker.Outcome? {
        if case .finished(_, let outcome, _, _) = phase { return outcome }
        return nil
    }

    /// Whether the page has a dashboard to show: a session running, a task
    /// frozen at the end of one, or a reading that came back from a stop.
    var showsDashboard: Bool {
        isMonitoring || isTaskRunning || isTaskFinished || snapshot != nil
    }

    /// The address being read, for the page to name.
    var endpointDescription: String {
        guard let url = NotchSplashSupport.endpoint() else { return NotchSplashSupport.placeholder }
        return "\(url.host ?? ""):\(url.port ?? 0)"
    }

    // MARK: The two switches

    /// Begin monitoring at the chosen interval. Nothing is asked of Splash
    /// beyond the status, so no generation starts.
    func start() {
        guard NotchSplashSupport.isEnabled(), !isMonitoring else { return }
        guard NotchSplashSupport.endpoint() != nil else {
            failure = .notConfigured
            return
        }
        generation = UUID()
        tracker.begin()
        tracker.clearFinished()
        phase = tracker.phase
        failure = nil
        isMonitoring = true
        startLoop()
    }

    /// Stop monitoring. The page returns to its Start state; a generation
    /// already running in Splash is left alone, because stopping the reading
    /// is not stopping the work.
    func stop() {
        guard isMonitoring || loop != nil else { return }
        isMonitoring = false
        generation = UUID()
        loop?.cancel()
        loop = nil
        tracker.clearFinished()
        phase = tracker.phase
        failure = nil
    }

    /// A finished task cleared, so the page is empty again.
    func clearFinishedTask() {
        tracker.clearFinished()
        phase = tracker.phase
    }

    /// The chosen interval, applied to the running session at once.
    func setInterval(_ seconds: Int) {
        let chosen = NotchSplashSupport.interval(seconds)
        guard chosen != intervalSeconds else { return }
        intervalSeconds = chosen
        UserDefaults.standard.set(chosen, forKey: DefaultsKey.notchSplashIntervalSeconds)
        if isMonitoring, let loop {
            // The running nap is cut short, so the new interval is the
            // interval the session keeps from here.
            loop.cancel()
            self.loop = nil
            startLoop()
        }
    }

    // MARK: Lifecycle

    func syncWithPreferences() {
        intervalSeconds = NotchSplashSupport.savedInterval()
        guard NotchSplashSupport.isEnabled() else {
            if isMonitoring { stop() }
            return
        }
        // The address, the port, or the key moved under a running session:
        // read the new one, and let the tracker's instance rule decide what
        // the old request was.
        if isMonitoring, NotchSplashSupport.endpoint() == nil { stop() }
    }

    func stopReading() {
        loop?.cancel()
        loop = nil
    }

    // MARK: The loop

    private func startLoop() {
        let generation = self.generation
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self, self.isMonitoring, self.generation == generation {
                await self.readOnce(generation: generation)
                if Task.isCancelled || !self.isMonitoring || self.generation != generation { return }
                let seconds = max(0.2, TimeInterval(self.intervalSeconds))
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    /// One status, read and applied.
    private func readOnce(generation: UUID) async {
        guard let url = NotchSplashSupport.endpoint() else {
            failure = .notConfigured
            stop()
            return
        }
        var query = URLRequest(url: url)
        query.httpMethod = "GET"
        query.cachePolicy = .reloadIgnoringLocalCacheData
        query.timeoutInterval = min(10, max(2, TimeInterval(intervalSeconds) * 2))
        if let authorization = NotchSplashEndpoint.authorization(
            UserDefaults.standard.string(forKey: DefaultsKey.notchSplashAPIKey) ?? "") {
            query.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        let started = Date()
        do {
            let (data, response) = try await session.data(for: query)
            // A read that belonged to a session that has since been stopped
            // or restarted has nothing to say about this one.
            guard generation == self.generation, !Task.isCancelled else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard code == 200 else {
                report(.status(code), at: started)
                return
            }
            guard let document = SplashJSON.document(data) else {
                report(.unreadable, at: started)
                return
            }
            let status = NotchSplashStatus(document: document)
            guard status.isReadable else {
                report(.unreadable, at: started)
                return
            }
            apply(NotchSplashSnapshot(status: status, fetchedAt: Date()), at: Date())
        } catch {
            guard generation == self.generation else { return }
            // A cancelled read is the session ending by hand, which is not a
            // failure to report.
            if (error as? URLError)?.code == .cancelled, !isMonitoring { failure = nil; return }
            report(.unreachable, at: started)
        }
    }

    private func report(_ failure: NotchSplashFailure, at date: Date) {
        self.failure = failure
        // A reading that did not arrive: the last one stays on the card, and
        // once it is older than the polling should have moved, it stops
        // counting as evidence, so a server that comes back late cannot be
        // read as finishing a request it never saw.
        if let snapshot, isStale(snapshot) { self.failure = .stale }
    }

    private func isStale(_ snapshot: NotchSplashSnapshot) -> Bool {
        Date().timeIntervalSince(snapshot.fetchedAt)
            > TimeInterval(intervalSeconds) * Double(NotchSplashSupport.staleIntervalFactor)
    }

    /// A reading applied to the task, the dashboard, and the notices.
    private func apply(_ snapshot: NotchSplashSnapshot, at date: Date) {
        self.snapshot = snapshot
        failure = nil
        let event = tracker.observe(snapshot, at: date)
        phase = tracker.phase
        isSpilling = tracker.isSpilling
        reservationFailures = snapshot.status.kv.reservationFailures
        guard let event else { return }
        switch event {
        case .started:
            break
        case .finished(let id, let outcome, _, _):
            finishTask(id: id, outcome: outcome)
        }
    }

    /// What the end of a task does: announce it once, and stop the reading
    /// when it ended as a completion.
    private func finishTask(id: String, outcome: NotchSplashTaskTracker.Outcome) {
        let strings = FeatureStrings.notchSplash(L10n.shared.language)
        if announcements.take(id: id, outcome: outcome) {
            Notifier.post(title: strings.notifyCompletedTitle,
                          body: strings.notifyCompletedBody(NotchSplashSupport.taskClock(elapsed(at: Date()))))
        } else if announcements.takeUnsuccessful(id: id, outcome: outcome) {
            Notifier.post(title: outcome == .failed ? strings.notifyFailedTitle : strings.notifyCancelledTitle,
                          body: outcome == .failed ? strings.notifyFailedBody : strings.notifyCancelledBody)
        }
        switch outcome {
        case .completed:
            // The task is over, so the reading is: the clock freezes, the
            // readings stay, and the polling stops.
            stopReadingOnly()
        case .failed, .cancelled, .lost:
            // A task that ended without completing is cleared, so the next
            // request the server reports is timed as the next task, and the
            // monitoring that is still running keeps reading.
            tracker.clearFinished()
            phase = tracker.phase
        }
    }

    /// Stop the polling, keeping everything the page shows.
    private func stopReadingOnly() {
        isMonitoring = false
        generation = UUID()
        loop?.cancel()
        loop = nil
    }
}
