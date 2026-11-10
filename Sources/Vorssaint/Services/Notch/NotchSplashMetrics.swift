// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the engine measured, in the engine's own words, for one reading.
///
/// The three measuring cards each show two figures and two lines, and both of
/// them are the endpoint's: the batch in hand, and the average over the whole
/// of the engine's running. The app measures nothing of its own. An earlier
/// version measured a current rate itself, from the difference the engine's
/// cumulative token and wall counters made across a window of readings, and
/// that figure was a throughput the endpoint never claimed - a sustained rate
/// inferred from arithmetic, with the app's window, minimum span and division
/// guards deciding what "current" meant. The endpoint answers the same
/// question directly, over the batch it is running, and a figure taken from
/// the engine cannot drift from the engine's own idea of what it is doing.
///
/// Four rules keep the cards honest, and all four are about absence:
///
/// * A field the server does not carry is nil, and its line and its figure are
///   left empty. A card with no figures says it has no measurements.
/// * A batch the server marks not valid, and a rate that is not a number, are
///   not measurements of the present, and the current line stays empty.
/// * Nothing is carried forward as if it were current. A reading that has gone
///   stale, and a session begun over an engine that is not the one the last
///   reading came from, leave the figures empty until a reading answers; the
///   chart's line stops, and does not continue on the strength of the last
///   figure it had.
/// * A number that is not in the reading is never invented: no zero, no
///   smoothing, no filling of a gap.
struct NotchSplashLiveMetrics: Equatable {
    /// The decode batch in hand, tokens per second, as the engine timed it.
    var decode: Double?
    /// The prefill batch in hand, tokens per second.
    var prefill: Double?
    /// Time to first token, in seconds, at the two percentiles the engine names.
    var ttftP50: Double?
    var ttftP95: Double?

    static let empty = NotchSplashLiveMetrics()

    /// The figures of one reading. A server that answers no batch, and a batch
    /// it marks not valid, leave the current figures nil; the averages beside
    /// them are read from the status by the card, not copied into these.
    static func current(_ metrics: NotchSplashStatus.Metrics) -> NotchSplashLiveMetrics {
        NotchSplashLiveMetrics(
            decode: metrics.currentDecodeBatchTokensPerSecond,
            prefill: metrics.currentPrefillBatchTokensPerSecond,
            ttftP50: NotchSplashSupport.ttftSeconds(milliseconds: metrics.ttftMilliseconds),
            ttftP95: NotchSplashSupport.ttftSeconds(milliseconds: metrics.ttftP95Milliseconds)
        )
    }

    /// The decode speed the island's strip shows: the batch in hand, and the
    /// engine's own average over the whole of its running while no batch is in
    /// hand. Both are the engine's figures; neither is invented, and the strip
    /// shows nothing when the server answers neither. The average is shown in
    /// the strip because the strip has room for one figure and the engine's
    /// average is the figure the endpoint gives for a machine at rest; the card
    /// of four readings is where the two are shown apart.
    static func stripDecodeSpeed(current: Double?, overall: Double?) -> Double? {
        if let current, current.isFinite { return current }
        guard let overall, overall.isFinite, overall > 0 else { return nil }
        return overall
    }
}
