# 0003. The closed island's throughput is the engine's work now

- Status: accepted
- Date: 2026-11-12
- Context: A Splash dashboard idle at `127.0.0.1:8001` answers `active_requests: []`,
  every scheduler, frontend and transport count at zero, `status_stale: false`,
  `metrics.current_decode_batch.valid = true` with a rate beside it (`104.5 t/s` in a
  real reading), and a lifetime `metrics.decode_tokens_per_second` (`92.3`) next to it.
  `valid` says the last batch measurement is well-formed, not that a batch is being
  measured now. The closed island's strip took `current_decode_batch` as the figure and
  fell back to the lifetime average when it was missing, so a one-second task left
  `92.3t/s` on the notch for the whole five-minute quiescence window, and a single
  reading that showed counters moving opened a run at once, freezing the strip's clock
  at `00:01` with `↑0 ↓0`.
- Decision: The strip shows the throughput of a batch the engine is measuring now, and
  nothing else.
  - `NotchSplashLiveMetrics.current(_:present:)` keeps the current batch's decode and
    prefill rates only when `present` is the engine's own answer that it has work in
    hand (`status.hasWork`). The percentiles of finished requests are not figures of the
    present and are kept as they were.
  - `NotchSplashLiveMetrics.stripDecodeSpeed(current:)` takes the current batch's rate
    alone: no lifetime-average fallback, and nil for a nil, non-finite or non-positive
    rate. The averages belong to the Complete Dashboard, which keeps drawing them while
    the engine rests.
  - `NotchSplashService.stripReadingIsLive` is the liveness gate: a reading present, no
    failure, monitoring, not older than the polling should have left it, and
    `status.hasWork`. `stripDecodeSpeed` answers nil unless the reading is live, and
    `stripShowsDecodeSpeed` requires a live reading with a rate in it. The strip's
    placeholder is kept only for an engine at work whose reading answers no batch, so a
    missing number leaves a place, not a stale figure.
  - The closed island's activity is the same gate: `showsIslandActivity(sectionVisible:
    isTaskRunning:isLive:)` needs a task running *and* a live reading, so a run held
    open for its confirmation window shows a clock, and shows no throughput over an
    engine at rest.
- Consequences: An idle engine leaves the notch with no Splash strip at all, which is
  the width the strip has with no activity; a task's own clock is unaffected. The strip
  can now go and come back inside one run, so a test must not read the strip's presence
  as the task's state - the tracker's phase is the task, and it is asserted directly.
  What unit tests prove is the reading-to-figure rule against captured `/status` bodies;
  the real endpoint, and what the notch looks like while a prompt streams, need the
  Release app.
- Related code: `Sources/Vorssaint/Services/Notch/NotchSplashMetrics.swift`
  (`current(_:present:)`, `stripDecodeSpeed(current:)`),
  `Sources/Vorssaint/Services/Notch/NotchSplashSupport.swift` (`stripReadingIsLive`,
  `stripDecodeSpeed`, `stripShowsDecodeSpeed`, `showsIslandActivity`),
  `Sources/Vorssaint/Services/Notch/NotchService.swift` (`hasSplashActivity`),
  `Sources/Vorssaint/UI/Notch/NotchSplashStrip.swift`,
  `Sources/Vorssaint/UI/Notch/NotchCapsuleViews.swift`.
  Tests: `Tests/NotchSplashTests.swift` (`stripThroughputChecks`, `liveMetricChecks`,
  `islandActivityChecks`). Supersedes nothing: the liveness of a task from `status` stays
  as [0001](0001-splash-task-liveness-from-status.md) records it.
