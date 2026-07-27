import Foundation

/// Which usage window the menu bar tracks. The other window's state is
/// indicated by the ambient warning dot on the gauge — see `docs/metrics.md`.
///
/// The cases name the window's *role*, not its duration, because OpenAI
/// changes both which windows exist and how long they are. `.session` is
/// whichever short window is published (5h historically), `.weekly` the
/// long rolling one (7d today).
enum TrackedWindow: String, CaseIterable, Codable, Sendable {
    case session
    case weekly

    /// Human-readable name, used for popover row headings, dial labels and
    /// the pacing status sentence. Plain `String` so `Models` keeps its
    /// no-dependencies rule.
    var label: String {
        switch self {
        case .session: return "Session"
        case .weekly: return "Weekly"
        }
    }

    /// The window that isn't this one — drives the menu bar's non-tracked
    /// warning dot and the fallback in `UsageSnapshot.resolvedWindow`.
    var other: TrackedWindow {
        self == .session ? .weekly : .session
    }

    /// Decodes a value persisted by `AppSettings`, accepting the raw
    /// values written by builds that named the cases after their durations
    /// (`fiveHour` / `sevenDay`). Without this, upgrading users would have
    /// their tracked-window choice silently reset to the default.
    static func fromPersisted(_ raw: String) -> TrackedWindow? {
        switch raw {
        case "session", "fiveHour": return .session
        case "weekly", "sevenDay": return .weekly
        default: return nil
        }
    }
}
