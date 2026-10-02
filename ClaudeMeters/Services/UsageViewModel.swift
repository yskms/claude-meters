import Foundation
import AppKit

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var lastError: UsageProviderError?
    var lastFetchFailed: Bool { lastError != nil }

    /// Evaluated at render time; views re-render on every fetch attempt
    /// (lastError/snapshot are reassigned each time), so the 15-minute and
    /// resets_at cutoffs take effect at the next attempt — at most the 300 s
    /// backoff cap late.
    func displayState(now: Date = Date()) -> UsageDisplayState {
        UsageDisplayState.make(snapshot: snapshot, lastError: lastError, now: now)
    }
    @Published var refreshInterval: TimeInterval {
        didSet {
            guard refreshInterval != oldValue else { return }
            defaults.set(refreshInterval, forKey: Self.refreshIntervalDefaultsKey)
            restartLoop()
        }
    }

    private let provider: UsageProvider
    /// Injected so tests use their own suite: the test host shares the real
    /// app's domain, so writing `.standard` there would clobber the user's
    /// saved interval.
    private let defaults: UserDefaults
    private var loopTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var wakeObserver: NSObjectProtocol?

    /// Bumped on every restartLoop(). A Task.cancel() doesn't interrupt the
    /// synchronous Keychain call inside performFetch() (it can block for
    /// seconds on the OS permission dialog), so a stale task can still be
    /// mid-fetch when a newer one starts. Gating every state write on
    /// "is my generation still current" is what keeps a stale result from
    /// overwriting consecutiveFailures/lastError/snapshot.
    private var currentGeneration = 0

    static let refreshIntervalDefaultsKey = "refreshInterval"
    static let maxBackoffInterval: TimeInterval = 300
    /// The Settings picker's options. 1 minute was dropped on 2026-10-01:
    /// the endpoint sustains only about one request per 2 minutes, so it
    /// added 429s without updating any faster (docs/REQUIREMENTS.md §8).
    static let allowedRefreshIntervals: [TimeInterval] = [120, 300]
    static let defaultRefreshInterval: TimeInterval = 120

    init(provider: UsageProvider = ClaudeUsageProvider(), defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
        let isSaved = defaults.object(forKey: Self.refreshIntervalDefaultsKey) != nil
        let saved = defaults.double(forKey: Self.refreshIntervalDefaultsKey)
        let interval = Self.normalizedRefreshInterval(saved)
        self.refreshInterval = interval
        // Rewrite any saved value the picker can't show (the old 60 s, 0,
        // negatives, ...), so the stored setting matches what's running. Not
        // saved at all stays unsaved, so it follows any future default change.
        if isSaved, saved != interval {
            defaults.set(interval, forKey: Self.refreshIntervalDefaultsKey)
        }
        restartLoop()
        observeWake()
    }

    deinit {
        loopTask?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    /// Popover-triggered manual refresh: restarts the loop so it fetches
    /// immediately instead of waiting out whatever delay is in flight.
    func refreshNow() {
        restartLoop()
    }

    private func restartLoop() {
        currentGeneration += 1
        let generation = currentGeneration
        let previousTask = loopTask
        previousTask?.cancel()
        consecutiveFailures = 0

        // Cancellation doesn't interrupt the synchronous Keychain call, so
        // wait for the previous task to actually exit before starting a new
        // fetch — otherwise the two could run concurrently (duplicate
        // network/Keychain access) even though state updates from the old
        // one are already blocked by the generation check below.
        loopTask = Task { [weak self] in
            await previousTask?.value
            guard !Task.isCancelled, let self, generation == self.currentGeneration else { return }
            await self.runLoop(generation: generation)
        }
    }

    private func runLoop(generation: Int) async {
        while !Task.isCancelled, generation == currentGeneration {
            await performFetch(generation: generation)
            if Task.isCancelled || generation != currentGeneration { return }
            let delay = nextDelay()
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func performFetch(generation: Int) async {
        do {
            let result = try await provider.fetchUsage()
            guard generation == currentGeneration else { return }
            snapshot = result
            lastError = nil
            consecutiveFailures = 0
        } catch is CancellationError {
            // Superseded by a newer generation — not a fetch failure.
        } catch {
            guard generation == currentGeneration else { return }
            lastError = (error as? UsageProviderError) ?? .network(error)
            consecutiveFailures += 1
        }
    }

    /// Unsaved (0), the retired 60 s, or any other value outside the
    /// picker's options falls back to the default.
    static func normalizedRefreshInterval(_ saved: TimeInterval) -> TimeInterval {
        allowedRefreshIntervals.contains(saved) ? saved : defaultRefreshInterval
    }

    private func nextDelay() -> TimeInterval {
        Self.computeDelay(
            refreshInterval: refreshInterval,
            consecutiveFailures: consecutiveFailures,
            maxBackoffInterval: Self.maxBackoffInterval
        )
    }

    /// Pure so it's directly unit-testable without touching Task.sleep timing.
    nonisolated static func computeDelay(
        refreshInterval: TimeInterval,
        consecutiveFailures: Int,
        maxBackoffInterval: TimeInterval
    ) -> TimeInterval {
        guard consecutiveFailures > 0 else { return refreshInterval }
        let backoff = refreshInterval * pow(2, Double(consecutiveFailures))
        return min(backoff, maxBackoffInterval)
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.restartLoop()
            }
        }
    }
}
