import Foundation

/// Available Codex rate-limit resets and the earliest time one expires.
struct BankedResetInfo: Equatable, Sendable {
    let availableCount: Int
    let nextExpiry: Date
}
