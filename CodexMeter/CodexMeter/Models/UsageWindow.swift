import Foundation

struct UsageWindow: Decodable, Equatable, Sendable {
    /// Percentage in the range 0.0...100.0 (not a fraction). Codex's
    /// `wham/usage` returns this as `used_percent`. Values >= 100 are
    /// possible once a window is exhausted; clamp at the view layer.
    let utilization: Double

    /// Window reset time in UTC. Decoded from `reset_at` (unix seconds
    /// since epoch). Optional because the API may omit it in edge cases.
    let resetsAt: Date?

    /// Total length of the rate-limit window, from `limit_window_seconds`.
    ///
    /// This is the field that identifies *which* window the API is
    /// describing. `primary_window` / `secondary_window` are positional
    /// slots that OpenAI reassigns — when session limits were dropped the
    /// weekly window moved into `primary_window` — so `UsageSnapshot`
    /// sorts windows by this value rather than by slot. Optional because
    /// the field isn't guaranteed; see `UsageSnapshot.classify`.
    let duration: TimeInterval?

    init(utilization: Double, resetsAt: Date?, duration: TimeInterval? = nil) {
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.duration = duration
    }

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case limitWindowSeconds = "limit_window_seconds"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.utilization = try c.decode(Double.self, forKey: .usedPercent)
        if let secs = try c.decodeIfPresent(TimeInterval.self, forKey: .resetAt) {
            self.resetsAt = Date(timeIntervalSince1970: secs)
        } else {
            self.resetsAt = nil
        }
        self.duration = try c.decodeIfPresent(TimeInterval.self, forKey: .limitWindowSeconds)
    }
}
