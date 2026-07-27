import Foundation

/// Decoded subset of Codex's `wham/usage` response.
///
/// The API returns far more (per-feature buckets, credits, plan_type, etc.)
/// — we only decode what v1 surfaces: the two rate-limit windows, sorted
/// into slots by their reported length rather than by the positional
/// `primary_window` / `secondary_window` keys they arrive in. See
/// `classify(primary:secondary:)` for why.
///
/// Either slot may be `nil`: OpenAI publishes whichever windows currently
/// apply to the account, and that set changes. As of 2026-07-27 only the
/// weekly window is published.
struct UsageSnapshot: Decodable, Equatable, Sendable {
    /// The short "session" window — 5h (`limit_window_seconds: 18000`)
    /// whenever OpenAI publishes one. `nil` since session limits were
    /// dropped; the app treats its return as a normal state, not an
    /// upgrade.
    let session: UsageWindow?

    /// The long rolling window — 7d (`604800`) today.
    let weekly: UsageWindow?

    /// Windows this long or shorter are session windows; anything longer
    /// is the weekly bucket. 24h sits in the wide empty gap between the
    /// two families (5h vs 7d), so the split survives OpenAI retuning
    /// either window without us having to chase the exact value.
    static let sessionMaxDuration: TimeInterval = 24 * 3600

    init(session: UsageWindow?, weekly: UsageWindow?) {
        self.session = session
        self.weekly = weekly
    }

    subscript(window: TrackedWindow) -> UsageWindow? {
        switch window {
        case .session: return session
        case .weekly: return weekly
        }
    }

    /// The windows the API is currently publishing, in display order.
    var availableWindows: [TrackedWindow] {
        TrackedWindow.allCases.filter { self[$0] != nil }
    }

    /// The window the UI should actually show, honoring `preference` but
    /// falling back to the other one when the preferred window isn't
    /// published. Returns `nil` when the response carried no windows at
    /// all. Without this, a saved preference of `.session` would leave the
    /// menu bar blank for as long as OpenAI keeps session limits retired.
    func resolvedWindow(preferring preference: TrackedWindow) -> TrackedWindow? {
        if self[preference] != nil { return preference }
        if self[preference.other] != nil { return preference.other }
        return nil
    }

    /// Sorts the two positional API slots into session/weekly by the
    /// length each window reports.
    ///
    /// Slot position is not a reliable identifier: OpenAI moved the weekly
    /// window into `primary_window` (leaving `secondary_window` null) when
    /// they dropped session limits, which made a position-based parser
    /// label weekly usage as session usage. Length is stable — a 5h window
    /// says 18000 wherever it appears.
    ///
    /// Falls back to the historical positional mapping for any window that
    /// omits `limit_window_seconds`, which is the best guess available
    /// when the identifying field is missing.
    static func classify(
        primary: UsageWindow?,
        secondary: UsageWindow?
    ) -> (session: UsageWindow?, weekly: UsageWindow?) {
        var session: UsageWindow?
        var weekly: UsageWindow?

        // Windows that report their own length are placed by length. First
        // one into a slot wins; the API has never sent two of a kind.
        for window in [primary, secondary].compactMap({ $0 }) {
            guard let duration = window.duration else { continue }
            if duration <= sessionMaxDuration {
                if session == nil { session = window }
            } else if weekly == nil {
                weekly = window
            }
        }

        // Legacy fallback for windows with no `limit_window_seconds`, only
        // for slots nothing else claimed.
        if let primary, primary.duration == nil, session == nil { session = primary }
        if let secondary, secondary.duration == nil, weekly == nil { weekly = secondary }

        return (session, weekly)
    }

    private enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }

    private enum RateLimitKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        // `rate_limit` may be absent or null in edge cases — treat both
        // windows as nil rather than failing to decode the snapshot.
        guard
            let rl = try? root.nestedContainer(keyedBy: RateLimitKeys.self, forKey: .rateLimit)
        else {
            self.session = nil
            self.weekly = nil
            return
        }
        let primary = try rl.decodeIfPresent(UsageWindow.self, forKey: .primaryWindow)
        let secondary = try rl.decodeIfPresent(UsageWindow.self, forKey: .secondaryWindow)
        (self.session, self.weekly) = Self.classify(primary: primary, secondary: secondary)
    }
}
