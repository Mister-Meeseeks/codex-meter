import Foundation

/// Drives `UsageStore` with periodic API calls. Owns its task lifecycle.
///
/// Polling cadence: 60s regardless of popover open/closed. The
/// `wham/usage` endpoint rate-limits aggressively — pushing harder while
/// the popover is open just trips the limiter sooner. On error,
/// exponential backoff with a 5-minute ceiling; if the server provides a
/// `Retry-After` it's honored as a one-shot override.
///
/// The poller does not interpret data; it just moves bytes from the
/// provider into the store. Errors are categorized by concrete type
/// (`TokenReader.ReadError` vs `CodexAPI.APIError`) so the view layer
/// can show different user-facing messages for "needs sign-in" vs
/// "endpoint failed."
actor UsagePoller {
    private let store: UsageStore
    private let provider: any UsageProvider
    private let normalInterval: TimeInterval
    private let activeInterval: TimeInterval
    private let backoffCeiling: TimeInterval

    private var task: Task<Void, Never>?
    private var isPopoverOpen: Bool = false
    private var consecutiveFailures: Int = 0
    /// One-shot override applied to the next sleep, set when the API tells
    /// us explicitly when to retry (e.g. `Retry-After` on a 429). Cleared
    /// after it's consumed.
    private var nextDelayOverride: TimeInterval?

    init(
        store: UsageStore,
        provider: any UsageProvider,
        normalInterval: TimeInterval = 60,
        activeInterval: TimeInterval = 60,
        backoffCeiling: TimeInterval = 300
    ) {
        self.store = store
        self.provider = provider
        self.normalInterval = normalInterval
        self.activeInterval = activeInterval
        self.backoffCeiling = backoffCeiling
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func setPopoverOpen(_ open: Bool) {
        self.isPopoverOpen = open
    }

    /// Force an out-of-band poll (e.g. user clicks "Refresh"). Resets the
    /// next-tick timer is *not* the caller's job — the running loop's sleep
    /// is unaffected, but the snapshot updates immediately.
    func refreshNow() async {
        await pollOnce()
    }

    // Exposed for tests; computes the next sleep interval given current state.
    func nextInterval() -> TimeInterval {
        if let override = nextDelayOverride {
            return min(override, backoffCeiling)
        }
        let base = isPopoverOpen ? activeInterval : normalInterval
        guard consecutiveFailures > 0 else { return base }
        let backoff = base * pow(2.0, Double(consecutiveFailures - 1))
        return min(backoff, backoffCeiling)
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await pollOnce()
            let seconds = nextInterval()
            nextDelayOverride = nil
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }

    private func pollOnce() async {
        do {
            let snapshot = try await provider.fetchUsage()
            await store.updateSnapshot(snapshot)
            consecutiveFailures = 0
        } catch let err as TokenReader.ReadError {
            await store.recordError(.tokenRead(err))
            consecutiveFailures += 1
        } catch let err as CodexAPI.APIError {
            await store.recordError(.api(err))
            consecutiveFailures += 1
            // Honor server-supplied Retry-After when the rate limiter sets
            // one; otherwise let exponential backoff take over.
            if case .rateLimited(let retryAfter) = err, let s = retryAfter, s > 0 {
                nextDelayOverride = s
            }
        } catch {
            await store.recordError(.api(.network(underlying: error)))
            consecutiveFailures += 1
        }
    }
}
