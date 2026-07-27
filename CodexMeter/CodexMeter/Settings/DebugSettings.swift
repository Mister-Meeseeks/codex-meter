import Foundation
import Observation

/// Hidden developer-only override for the values displayed by the menu-bar
/// label and popover. When `enabled` is true, the views read synthesized
/// values from this struct instead of the real `UsageStore` data, letting a
/// developer step through every visual state (low/high utilization, on-pace,
/// over-pace, under-pace, session window published or not) without having to
/// actually burn the account.
///
/// All fields persist to `UserDefaults` so the override survives relaunches.
/// Hidden in `SettingsView` behind a ⌥⌘⇧D shortcut.
@MainActor
@Observable
final class DebugSettings {
    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Keys.enabled) }
    }

    /// Whether the synthesized snapshot includes a session window at all.
    /// OpenAI retired session limits, so the popover has to look right both
    /// with and without one — this is the switch between those two layouts.
    var sessionWindowPresent: Bool {
        didSet { defaults.set(sessionWindowPresent, forKey: Keys.sessionWindowPresent) }
    }

    var sessionUtil: Double {
        didSet { defaults.set(sessionUtil, forKey: Keys.sessionUtil) }
    }
    var sessionMinutesToReset: Double {
        didSet { defaults.set(sessionMinutesToReset, forKey: Keys.sessionMinutesToReset) }
    }
    var sessionOutcome: DebugOutcomeKind {
        didSet { defaults.set(sessionOutcome.rawValue, forKey: Keys.sessionOutcome) }
    }
    var sessionOverPaceHours: Double {
        didSet { defaults.set(sessionOverPaceHours, forKey: Keys.sessionOverPaceHours) }
    }
    var sessionUnusedFraction: Double {
        didSet { defaults.set(sessionUnusedFraction, forKey: Keys.sessionUnusedFraction) }
    }

    var weeklyUtil: Double {
        didSet { defaults.set(weeklyUtil, forKey: Keys.weeklyUtil) }
    }
    var weeklyMinutesToReset: Double {
        didSet { defaults.set(weeklyMinutesToReset, forKey: Keys.weeklyMinutesToReset) }
    }
    var weeklyOutcome: DebugOutcomeKind {
        didSet { defaults.set(weeklyOutcome.rawValue, forKey: Keys.weeklyOutcome) }
    }
    var weeklyOverPaceHours: Double {
        didSet { defaults.set(weeklyOverPaceHours, forKey: Keys.weeklyOverPaceHours) }
    }
    var weeklyUnusedFraction: Double {
        didSet { defaults.set(weeklyUnusedFraction, forKey: Keys.weeklyUnusedFraction) }
    }

    /// Simulate the API being unreachable while the cached snapshot stays
    /// visible — exercises the rate-limited / network-down popover state.
    var apiUnavailable: Bool {
        didSet { defaults.set(apiUnavailable, forKey: Keys.apiUnavailable) }
    }

    /// Suppress the yellow "DEBUG MODE" capsule at the top of the popover
    /// even when overrides are active. Lets the popover capture cleanly for
    /// screenshots while still using synthesized values.
    var hideBanner: Bool {
        didSet { defaults.set(hideBanner, forKey: Keys.hideBanner) }
    }

    /// Minutes since the last successful poll, fed into the popover's
    /// "Updated X ago" footer so you can preview stale-data styling.
    var minutesSinceUpdate: Double {
        didSet { defaults.set(minutesSinceUpdate, forKey: Keys.minutesSinceUpdate) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.enabled = defaults.bool(forKey: Keys.enabled)
        // Defaults to the two-window layout so the debug panel opens on the
        // richer state; flip it off to preview what today's API actually
        // returns.
        self.sessionWindowPresent = defaults.object(forKey: Keys.sessionWindowPresent) == nil
            ? true
            : defaults.bool(forKey: Keys.sessionWindowPresent)
        self.sessionUtil = Self.read(defaults, key: Keys.sessionUtil, fallback: 50)
        self.sessionMinutesToReset = Self.read(defaults, key: Keys.sessionMinutesToReset, fallback: 120)
        self.sessionOutcome = DebugOutcomeKind(rawValue: defaults.string(forKey: Keys.sessionOutcome) ?? "") ?? .none
        self.sessionOverPaceHours = Self.read(defaults, key: Keys.sessionOverPaceHours, fallback: 6)
        self.sessionUnusedFraction = Self.read(defaults, key: Keys.sessionUnusedFraction, fallback: 0.3)
        self.weeklyUtil = Self.read(defaults, key: Keys.weeklyUtil, fallback: 50)
        self.weeklyMinutesToReset = Self.read(defaults, key: Keys.weeklyMinutesToReset, fallback: 24 * 60)
        self.weeklyOutcome = DebugOutcomeKind(rawValue: defaults.string(forKey: Keys.weeklyOutcome) ?? "") ?? .none
        self.weeklyOverPaceHours = Self.read(defaults, key: Keys.weeklyOverPaceHours, fallback: 24)
        self.weeklyUnusedFraction = Self.read(defaults, key: Keys.weeklyUnusedFraction, fallback: 0.3)
        self.apiUnavailable = defaults.bool(forKey: Keys.apiUnavailable)
        self.hideBanner = defaults.bool(forKey: Keys.hideBanner)
        self.minutesSinceUpdate = Self.read(defaults, key: Keys.minutesSinceUpdate, fallback: 0)
    }

    private static func read(_ defaults: UserDefaults, key: String, fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }

    // MARK: - Synthesis

    /// Synthesized windows carry the same `duration` the real API reports,
    /// so projections use the identical code path as production data.
    func syntheticSnapshot(now: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            session: sessionWindowPresent
                ? UsageWindow(
                    utilization: sessionUtil,
                    resetsAt: now.addingTimeInterval(sessionMinutesToReset * 60),
                    duration: UsageStore.sessionFallbackDuration
                )
                : nil,
            weekly: UsageWindow(
                utilization: weeklyUtil,
                resetsAt: now.addingTimeInterval(weeklyMinutesToReset * 60),
                duration: UsageStore.weeklyFallbackDuration
            )
        )
    }

    func syntheticProjection(for window: TrackedWindow, now: Date = Date()) -> Projection? {
        let snapshot = syntheticSnapshot(now: now)
        let outcome: DebugOutcomeKind
        let overPaceHours: Double
        let unusedFraction: Double
        let minutesToReset: Double
        switch window {
        case .session:
            outcome = sessionOutcome
            overPaceHours = sessionOverPaceHours
            unusedFraction = sessionUnusedFraction
            minutesToReset = sessionMinutesToReset
        case .weekly:
            outcome = weeklyOutcome
            overPaceHours = weeklyOverPaceHours
            unusedFraction = weeklyUnusedFraction
            minutesToReset = weeklyMinutesToReset
        }

        // Pace ratio always tracks the debug snapshot so the gauges
        // respond to the Utilization / Resets-in sliders. The outcome
        // picker only chooses what kind of outcome rides along — it no
        // longer overrides the ratio (which used to leave the needle
        // pinned at 1.0 / 1.5 / 0.6 regardless of the sliders).
        guard let w = snapshot[window],
              let base = Projector.project(
                window: w,
                windowDuration: w.duration ?? UsageStore.fallbackDuration(for: window),
                now: now
              ) else {
            return nil
        }
        switch outcome {
        case .none:
            return base
        case .onPace:
            return Projection(paceRatio: base.paceRatio, confidence: .full, outcome: .onPace)
        case .overPace:
            return Projection(
                paceRatio: base.paceRatio,
                confidence: .full,
                outcome: .overPace(deadTime: max(0, overPaceHours) * 3600)
            )
        case .underPace:
            let frac = max(0, min(1, unusedFraction))
            return Projection(
                paceRatio: base.paceRatio,
                confidence: .full,
                outcome: .underPace(
                    unusedFraction: frac,
                    unusedTime: frac * minutesToReset * 60
                )
            )
        }
    }

    private enum Keys {
        static let enabled = "debug.enabled"
        static let sessionWindowPresent = "debug.session.present"
        static let sessionUtil = "debug.session.util"
        static let sessionMinutesToReset = "debug.session.minutesToReset"
        static let sessionOutcome = "debug.session.outcome"
        static let sessionOverPaceHours = "debug.session.overPaceHours"
        static let sessionUnusedFraction = "debug.session.unusedFraction"
        static let weeklyUtil = "debug.weekly.util"
        static let weeklyMinutesToReset = "debug.weekly.minutesToReset"
        static let weeklyOutcome = "debug.weekly.outcome"
        static let weeklyOverPaceHours = "debug.weekly.overPaceHours"
        static let weeklyUnusedFraction = "debug.weekly.unusedFraction"
        static let apiUnavailable = "debug.apiUnavailable"
        static let hideBanner = "debug.hideBanner"
        static let minutesSinceUpdate = "debug.minutesSinceUpdate"
    }
}

enum DebugOutcomeKind: String, CaseIterable, Codable, Sendable {
    case none, onPace, overPace, underPace

    var label: String {
        switch self {
        case .none: return "No projection"
        case .onPace: return "On pace"
        case .overPace: return "Over pace"
        case .underPace: return "Under pace"
        }
    }
}
