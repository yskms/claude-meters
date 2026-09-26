import Foundation
import AppKit

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var lastFetchFailed = false
    @Published var refreshInterval: TimeInterval {
        didSet {
            guard refreshInterval != oldValue else { return }
            UserDefaults.standard.set(refreshInterval, forKey: Self.refreshIntervalDefaultsKey)
            restartLoop()
        }
    }

    private let provider: UsageProvider
    private var loopTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var wakeObserver: NSObjectProtocol?

    /// Bumped on every restartLoop(). A Task.cancel() doesn't interrupt the
    /// synchronous Keychain call inside performFetch() (it can block for
    /// seconds on the OS permission dialog), so a stale task can still be
    /// mid-fetch when a newer one starts. Gating every state write on
    /// "is my generation still current" is what keeps a stale result from
    /// overwriting consecutiveFailures/lastFetchFailed/snapshot.
    private var currentGeneration = 0

    private static let refreshIntervalDefaultsKey = "refreshInterval"
    private static let maxBackoffInterval: TimeInterval = 300

    init(provider: UsageProvider = ClaudeUsageProvider()) {
        self.provider = provider
        let saved = UserDefaults.standard.double(forKey: Self.refreshIntervalDefaultsKey)
        self.refreshInterval = saved > 0 ? saved : 60
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
            lastFetchFailed = false
            consecutiveFailures = 0
        } catch is CancellationError {
            // Superseded by a newer generation — not a fetch failure.
        } catch {
            guard generation == currentGeneration else { return }
            lastFetchFailed = true
            consecutiveFailures += 1
        }
    }

    private func nextDelay() -> TimeInterval {
        guard consecutiveFailures > 0 else { return refreshInterval }
        let backoff = refreshInterval * pow(2, Double(consecutiveFailures))
        return min(backoff, Self.maxBackoffInterval)
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
