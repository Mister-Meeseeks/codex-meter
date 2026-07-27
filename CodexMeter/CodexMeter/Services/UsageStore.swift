import Foundation
import Observation

/// Single source of truth for usage state. Views observe directly via
/// the Observation macros; UsagePoller is the sole writer.
///
/// Snapshot and error are kept independently: a network failure does not
/// erase the last good snapshot — the popover can show stale data plus a
/// "haven't refreshed since X" hint.
@MainActor
@Observable
final class UsageStore {
    private(set) var snapshot: UsageSnapshot?
    private(set) var lastRefresh: Date?
    private(set) var lastError: AppError?

    /// Window lengths used only when the API omits `limit_window_seconds`.
    /// The value the response reports always wins — these are the last
    /// resort so a projection is still possible from a window that didn't
    /// say how long it is.
    static let sessionFallbackDuration: TimeInterval = 5 * 3600
    static let weeklyFallbackDuration: TimeInterval = 7 * 86400

    static func fallbackDuration(for window: TrackedWindow) -> TimeInterval {
        switch window {
        case .session: return sessionFallbackDuration
        case .weekly: return weeklyFallbackDuration
        }
    }

    func updateSnapshot(_ snapshot: UsageSnapshot, at date: Date = Date()) {
        self.snapshot = snapshot
        self.lastRefresh = date
        self.lastError = nil
    }

    func recordError(_ error: AppError) {
        self.lastError = error
    }

    func clear() {
        self.snapshot = nil
        self.lastRefresh = nil
        self.lastError = nil
    }

    /// Compute the projection for one window from the live snapshot.
    /// Returns `nil` whenever `Projector` can't produce a value (no
    /// reset time, zero utilization, etc.).
    func projection(for window: TrackedWindow, now: Date = Date()) -> Projection? {
        guard let usage = snapshot?[window] else { return nil }
        return Projector.project(
            window: usage,
            windowDuration: usage.duration ?? Self.fallbackDuration(for: window),
            now: now
        )
    }
}
