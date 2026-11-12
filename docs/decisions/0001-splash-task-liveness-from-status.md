# 0001. Splash task liveness is read from `/status`, and the dashboard's clock is the work, not the confirmation window

- Status: accepted
- Date: 2026-11-11
- Context: the problem and constraints.
  Splash's `/status` counts requests. It has no word for a task, so the
  dashboard times a *run* of them: a coding agent's task is several requests,
  with a pause after each while it runs a tool, waits for an approval, or
  composes the next prompt. A run therefore ends at a quiet that has outlasted
  those pauses, and that quiet has to be confirmed by waiting through it.

  The confirmation was measured ten minutes, and the clock the card showed was
  advanced while the confirmation ran. A task that worked for eleven minutes was
  therefore displayed as sixteen, and eighteen was reached on a slower poll: the
  card was showing the app's own patience as part of the task. The confirmation
  and the task are two durations, and only one of them belongs to the card.

  The alternative considered was watching the active conversation file, which the
  app already reads for the Agents activity: a file that stops changing looks
  like a task that has stopped.
- Decision: the chosen approach.
  1. `/status` is the only source of current activity. A run is busy while any
     live field says so: `active_requests`, `scheduler.queued`,
     `scheduler.waiting_resources`, `scheduler.waiting_prefix`,
     `scheduler.waiting_mask`, `scheduler.prefilling`, `scheduler.decoding`,
     `frontend.active`, `frontend.waiting`, `transport.pending`, the HTTP
     requests in flight, and a snapshot the server marks as taken mid-loop
     (`transport.status_stale`). Empty `active_requests` alone is not proof of
     an idle engine.
  2. Cumulative figures are never evidence of current activity.
     `requests.submitted`, `requests.completed`, the token totals, the model's
     uptime and its weight-unloading times say what has happened, not what is
     happening. The request counters may *open* a run - a generation shorter
     than the polling interval leaves nothing but its counters - and they never
     keep one open, because a busy neighbour's counters would hold a finished
     run open forever.
  3. The confirmation window is ten minutes
     (`NotchSplashSupport.taskIdleSeconds`), and it belongs to the dashboard. It
     is not Splash's own `weights.idle_release_seconds`, which is the engine
     deciding when to put its weights to sleep; the two are asked separately and
     one setting does not move the other.
  4. The clock is the work and not the waiting. The first reading that finds the
     engine quiet stops the clock where the work ended; the run stays open for
     the window, so a pause in the middle of a task is not its end; work seen
     again lifts the clock off that mark and the run goes on; the window closing
     freezes the clock at the same number the card has been showing.
  5. A reading that did not arrive, and a reading that arrived already old, are
     not idle evidence. A run is not closed by one failure, a pause in polling,
     or a machine that was asleep. A server that changed identity under the run
     ends it as a run the dashboard cannot speak for.
  6. Watching the session file is rejected as a source of task completion.
     `/status` names requests and an instance and nothing else: there is no
     identifier shared with a client's conversation, so the active session cannot
     be tied to the run being timed. Session files are appended at event
     boundaries, so a long generation leaves the file untouched for minutes and
     an unchanged file would read as a finished task. One session carries many
     requests and tool calls, and some clients write a turn only when it is
     finished. The app's own agent harness needs windows of an hour (Claude) and
     six hours (the rest) before a session file is taken for dead, which is the
     measure of how sparse that signal is at the scale of a single task.
  7. The notice of a run that ended carries its length and the three times that
     place it in the day: where the run began, the quiet mark its clock froze at,
     and the moment the notice goes out. They are three instants and not one. The
     window sits between the quiet mark and the sending, so the sending is the
     session's own clock, and the start is handed to the notice by the tracker -
     arithmetic on the sending time would put both the start and the end a whole
     window too late. Each language places the four figures in its own order, and
     the localization test keeps the places honest.
- Consequences: benefits, costs, risks, and migration/testing implications.
  The card shows the task's length, and the island stops watching at the same
  number. The cost is that a task is called over up to ten minutes after its
  last work, and the run is open in that stretch: an activity that has finished
  keeps its frozen clock, and new work resumes the same run. A status that stops
  answering leaves the run open, which is the safe direction - the card keeps a
  clock it knows is not advancing on evidence - and the reading itself is a
  promise only a hand on the way out takes back.
  If the endpoint ever carries a per-request finish, or any identifier shared
  with a client's conversation, the window and the session question should be
  revisited together, in this record.
- Related code: `Sources/Vorssaint/Services/Notch/NotchSplashSupport.swift`
  (`NotchSplashStatus.Activity.hasWork`, `NotchSplashSupport.taskIdleSeconds`,
  `NotchSplashSupport.timeOfDayText`, `NotchSplashTaskTracker`,
  `NotchSplashService.apply`, `finishTask` and `report`),
  `Sources/Vorssaint/Core/NotchSplashStrings.swift` (`notifyActivityEndedBody`),
  `Sources/Vorssaint/UI/Notch/NotchSplashStrip.swift`,
  `Tests/NotchSplashTests.swift` (the window, the frozen clock, the notice's three
  times, the live fields, the failed and stale readings, the instance that changed).
- Supersedes: not applicable.
