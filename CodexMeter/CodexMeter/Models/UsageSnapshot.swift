import Foundation

/// Decoded subset of Codex's `wham/usage` response.
///
/// The API returns far more (per-feature buckets, credits, plan_type, etc.)
/// — we only decode what v1 surfaces. The two fields below use the names
/// `fiveHour`/`sevenDay` (a holdover from the claude-meter fork) because the
/// Codex window durations *are* exactly 5h and 7d (`limit_window_seconds`
/// = 18000 / 604800), and the rest of the app keys off these names. If
/// OpenAI ever changes the windows, rename here and propagate through
/// `DisplayMode`, `AppSettings`, `UsageStore.fiveHourDuration`, and the
/// view labels.
struct UsageSnapshot: Decodable, Equatable, Sendable {
    /// Maps to `rate_limit.primary_window` (currently 5h).
    let fiveHour: UsageWindow?

    /// Maps to `rate_limit.secondary_window` (currently 7d).
    let sevenDay: UsageWindow?

    init(fiveHour: UsageWindow?, sevenDay: UsageWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
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
            self.fiveHour = nil
            self.sevenDay = nil
            return
        }
        self.fiveHour = try rl.decodeIfPresent(UsageWindow.self, forKey: .primaryWindow)
        self.sevenDay = try rl.decodeIfPresent(UsageWindow.self, forKey: .secondaryWindow)
    }
}
