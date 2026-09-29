import Foundation

struct MeterUsage: Equatable {
    let percentUsed: Int
    let resetsAt: Date
}

struct UsageSnapshot: Equatable {
    let session: MeterUsage
    let weekly: MeterUsage
    let fetchedAt: Date
}

/// What every view shows for each meter. The menu bar glyph, the Popover's
/// rings and reset labels, and VoiceOver must all derive from this one value
/// (never from `snapshot`/`lastError` directly) so they can't disagree about
/// whether a meter is shown. The underlying snapshot is never cleared here —
/// only hidden — so the last fetch time stays available.
struct UsageDisplayState: Equatable {
    /// nil = show "–" for that meter.
    let session: MeterUsage?
    let weekly: MeterUsage?
    /// Set when the latest fetch failed but at least one meter still shows a
    /// value from this earlier successful fetch.
    let staleSince: Date?

    /// A value older than this is hidden even on a transient failure. Wall
    /// clock, so time spent asleep counts. Inclusive: exactly 15 minutes old
    /// is already hidden.
    static let maxStaleAge: TimeInterval = 15 * 60

    static func make(snapshot: UsageSnapshot?, lastError: UsageProviderError?, now: Date) -> UsageDisplayState {
        guard let snapshot else {
            return UsageDisplayState(session: nil, weekly: nil, staleSince: nil)
        }
        if let lastError {
            // A non-transient failure (auth, missing credential, changed
            // response shape) must surface as "–", not hide behind old values.
            guard lastError.isTransient,
                  now.timeIntervalSince(snapshot.fetchedAt) < maxStaleAge else {
                return UsageDisplayState(session: nil, weekly: nil, staleSince: nil)
            }
        }
        // Checked per meter: a session reset must not hide a still-valid
        // weekly value (and vice versa).
        let session = now < snapshot.session.resetsAt ? snapshot.session : nil
        let weekly = now < snapshot.weekly.resetsAt ? snapshot.weekly : nil
        let showsAny = session != nil || weekly != nil
        return UsageDisplayState(
            session: session,
            weekly: weekly,
            staleSince: lastError != nil && showsAny ? snapshot.fetchedAt : nil
        )
    }
}
