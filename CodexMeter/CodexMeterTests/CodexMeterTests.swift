import Foundation
import Testing
@testable import CodexMeter

@Suite("UsageSnapshot decoding")
struct UsageSnapshotDecodingTests {

    @Test("Decodes the weekly-only response the API returns today")
    func decodesWeeklyOnlyResponse() throws {
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(weeklyOnlyResponse.utf8))
        // The weekly window arrives in `primary_window` now that session
        // limits are retired — it must not land in the session slot.
        #expect(snapshot.session == nil)
        #expect(snapshot.weekly?.utilization == 12.0)
        #expect(snapshot.weekly?.duration == 604800)
        #expect(snapshot.weekly?.resetsAt != nil)
    }

    @Test("Decodes the dual-window response from before session limits were dropped")
    func decodesDualWindowResponse() throws {
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(dualWindowResponse.utf8))
        #expect(snapshot.session?.utilization == 1.0)
        #expect(snapshot.session?.duration == 18000)
        #expect(snapshot.weekly?.utilization == 4.0)
        #expect(snapshot.weekly?.duration == 604800)
    }

    @Test("Windows are placed by reported length, not by slot order")
    func classifiesBySlotIndependentDuration() throws {
        // Same two windows, swapped between the positional slots.
        let json = """
        {
          "rate_limit": {
            "primary_window": {"used_percent": 4, "limit_window_seconds": 604800, "reset_at": 1777983799},
            "secondary_window": {"used_percent": 1, "limit_window_seconds": 18000, "reset_at": 1777694872}
          }
        }
        """
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.session?.utilization == 1.0)
        #expect(snapshot.weekly?.utilization == 4.0)
    }

    @Test("A session window of a new length still classifies as session")
    func classifiesRetunedSessionWindow() throws {
        // If OpenAI reinstates session limits at, say, 3 hours, the split
        // has to hold without a code change.
        let json = """
        {
          "rate_limit": {
            "primary_window": {"used_percent": 30, "limit_window_seconds": 10800, "reset_at": 1777694872},
            "secondary_window": {"used_percent": 40, "limit_window_seconds": 604800, "reset_at": 1777983799}
          }
        }
        """
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.session?.utilization == 30.0)
        #expect(snapshot.session?.duration == 10800)
        #expect(snapshot.weekly?.utilization == 40.0)
    }

    @Test("Without limit_window_seconds, windows fall back to positional mapping")
    func fallsBackToPositionalMapping() throws {
        let json = """
        {
          "rate_limit": {
            "primary_window": {"used_percent": 20, "reset_at": 1777694872},
            "secondary_window": {"used_percent": 50, "reset_at": 1777983799}
          }
        }
        """
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.session?.utilization == 20.0)
        #expect(snapshot.session?.duration == nil)
        #expect(snapshot.weekly?.utilization == 50.0)
    }

    @Test("A length-bearing window wins the slot over a length-less one")
    func classifiedWindowBeatsPositionalFallback() throws {
        // Weekly window in the primary slot, an unlabeled window in the
        // secondary: the labeled one owns weekly, the unlabeled one takes
        // the slot its position implies.
        let json = """
        {
          "rate_limit": {
            "primary_window": {"used_percent": 12, "limit_window_seconds": 604800, "reset_at": 1785615365},
            "secondary_window": {"used_percent": 3, "reset_at": 1777694872}
          }
        }
        """
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.weekly?.utilization == 12.0)
        #expect(snapshot.session == nil, "unlabeled secondary can't claim the weekly slot, and isn't a session window")
    }

    @Test("Exactly-24h window counts as session; anything longer is weekly")
    func classifiesAtThresholdBoundary() throws {
        let json = """
        {
          "rate_limit": {
            "primary_window": {"used_percent": 10, "limit_window_seconds": 86400, "reset_at": 1777694872},
            "secondary_window": {"used_percent": 20, "limit_window_seconds": 86401, "reset_at": 1777983799}
          }
        }
        """
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.session?.utilization == 10.0)
        #expect(snapshot.weekly?.utilization == 20.0)
    }

    @Test("Body without rate_limit decodes to both-windows-nil")
    func decodesWithoutRateLimit() throws {
        let json = #"{"plan_type": "free"}"#
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.session == nil)
        #expect(snapshot.weekly == nil)
    }

    @Test("rate_limit: null decodes to both-windows-nil")
    func decodesNullRateLimit() throws {
        let json = #"{"rate_limit": null}"#
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.session == nil)
        #expect(snapshot.weekly == nil)
    }

    @Test("rate_limit present but windows null decodes to nil/nil")
    func decodesNullWindows() throws {
        let json = #"{"rate_limit": {"primary_window": null, "secondary_window": null}}"#
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.session == nil)
        #expect(snapshot.weekly == nil)
    }

    @Test("Window present but reset_at missing decodes resetsAt as nil")
    func decodesMissingResetAt() throws {
        let json = #"{"rate_limit": {"primary_window": {"used_percent": 0, "limit_window_seconds": 18000}, "secondary_window": null}}"#
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.session?.utilization == 0.0)
        #expect(snapshot.session?.resetsAt == nil)
    }

    @Test("Unknown top-level and per-window fields are ignored")
    func ignoresUnknownFields() throws {
        let json = """
        {
          "rate_limit": {
            "allowed": true,
            "limit_reached": false,
            "primary_window": {"used_percent": 14, "limit_window_seconds": 18000, "reset_after_seconds": 12496, "reset_at": 1777694872},
            "secondary_window": {"used_percent": 65, "limit_window_seconds": 604800, "reset_after_seconds": 301422, "reset_at": 1777983799}
          },
          "additional_rate_limits": [],
          "credits": {"has_credits": false},
          "rate_limit_reset_credits": {"available_count": 2, "applicable_available_count": 0},
          "future_field_openai_invents": "junk"
        }
        """
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.session?.utilization == 14.0)
        #expect(snapshot.weekly?.utilization == 65.0)
    }

    @Test("Utilization above 100 is preserved (caller clamps for display)")
    func utilizationCanExceed100() throws {
        let json = #"""
        {"rate_limit": {"primary_window": {"used_percent": 105.5, "limit_window_seconds": 18000, "reset_at": 1777694872}, "secondary_window": null}}
        """#
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.session?.utilization == 105.5)
    }

    @Test("Fractional used_percent decodes correctly")
    func decodesFractionalPercent() throws {
        let json = #"""
        {"rate_limit": {"primary_window": {"used_percent": 7.25, "limit_window_seconds": 18000, "reset_at": 1777694872}, "secondary_window": null}}
        """#
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.session?.utilization == 7.25)
    }

    @Test("reset_at unix seconds decodes to Date")
    func decodesUnixSecondsResetAt() throws {
        let json = #"""
        {"rate_limit": {"primary_window": {"used_percent": 14, "limit_window_seconds": 18000, "reset_at": 1777694872}, "secondary_window": null}}
        """#
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        guard let date = snapshot.session?.resetsAt else {
            Issue.record("expected non-nil reset date")
            return
        }
        #expect(date.timeIntervalSince1970 == 1777694872)
    }

    @Test("Missing used_percent throws decoding error")
    func missingUsedPercentThrows() {
        let json = #"""
        {"rate_limit": {"primary_window": {"reset_at": 1777694872}, "secondary_window": null}}
        """#
        #expect(throws: DecodingError.self) {
            try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        }
    }
}

@Suite("Banked reset decoding")
struct BankedResetDecodingTests {
    @Test("Uses the API count and earliest available expiry")
    func decodesEarliestAvailableExpiry() throws {
        let json = #"""
        {
          "credits": [
            {"status": "redeemed", "expires_at": "2026-08-01T12:00:00Z"},
            {"status": "available", "expires_at": "2026-08-20T12:00:00Z"},
            {"status": "available", "expires_at": "2026-08-12T17:45:56.252865Z"}
          ],
          "available_count": 2,
          "total_earned_count": 3
        }
        """#

        let info = try CodexAPI.decodeBankedResetInfo(from: Data(json.utf8))

        #expect(info?.availableCount == 2)
        let expectedExpiry = 1_786_556_756.252865
        #expect(abs((info?.nextExpiry.timeIntervalSince1970 ?? 0) - expectedExpiry) < 0.001)
    }

    @Test("Zero available resets produces no display info")
    func zeroAvailableResetsIsNil() throws {
        let json = #"""
        {"credits": [], "available_count": 0, "total_earned_count": 0}
        """#

        let info = try CodexAPI.decodeBankedResetInfo(from: Data(json.utf8))

        #expect(info == nil)
    }

    @Test("Available reset without an expiry produces no display info")
    func missingExpiryIsNil() throws {
        let json = #"""
        {"credits": [{"status": "available", "expires_at": null}], "available_count": 1}
        """#

        let info = try CodexAPI.decodeBankedResetInfo(from: Data(json.utf8))

        #expect(info == nil)
    }
}

@Suite("Banked reset presentation")
struct BankedResetPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_786_000_000)

    @Test("Uses the verbose countdown convention")
    func verboseCountdown() {
        let info = BankedResetInfo(
            availableCount: 2,
            nextExpiry: now.addingTimeInterval(4 * 86400)
        )

        let status = BankedResetStatus(info: info, now: now)

        #expect(status.countText == "2 Resets Left")
        #expect(status.expiryText == "Next Expiry in 4 days")
        #expect(!status.isExpiringSoon)
    }

    @Test("Uses singular reset copy")
    func singularResetCopy() {
        let info = BankedResetInfo(
            availableCount: 1,
            nextExpiry: now.addingTimeInterval(4 * 86400)
        )

        let status = BankedResetStatus(info: info, now: now)

        #expect(status.countText == "1 Reset Left")
    }

    @Test("Expiry is urgent only below 24 hours")
    func urgentBelowTwentyFourHours() {
        let atThreshold = BankedResetStatus(
            info: BankedResetInfo(
                availableCount: 1,
                nextExpiry: now.addingTimeInterval(24 * 3600)
            ),
            now: now
        )
        let belowThreshold = BankedResetStatus(
            info: BankedResetInfo(
                availableCount: 1,
                nextExpiry: now.addingTimeInterval(24 * 3600 - 1)
            ),
            now: now
        )

        #expect(!atThreshold.isExpiringSoon)
        #expect(belowThreshold.isExpiringSoon)
    }
}

@Suite("Committed fixtures")
struct FixtureDecodingTests {

    /// Fixtures live in the repo, not the test bundle — they're probe
    /// output that `utils/probe-codex-usage-api.sh` refreshes, and reading
    /// them from source keeps the parser honest against the bytes actually
    /// committed rather than an inline copy that can drift.
    private static func fixture(_ name: String) throws -> Data {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()  // CodexMeterTests
            .deletingLastPathComponent()  // CodexMeter
            .deletingLastPathComponent()  // repo root
        return try Data(contentsOf: repoRoot.appending(path: "assets/fixtures/\(name)"))
    }

    @Test("wham-usage.json — the live shape — decodes to weekly only")
    func decodesCurrentFixture() throws {
        let snapshot = try CodexAPI.decoder.decode(
            UsageSnapshot.self, from: Self.fixture("wham-usage.json")
        )
        #expect(snapshot.session == nil)
        #expect(snapshot.weekly?.duration == 604800)
        #expect(snapshot.availableWindows == [.weekly])
    }

    @Test("wham-usage-dual-window.json — the archived shape — decodes to both windows")
    func decodesDualWindowFixture() throws {
        let snapshot = try CodexAPI.decoder.decode(
            UsageSnapshot.self, from: Self.fixture("wham-usage-dual-window.json")
        )
        #expect(snapshot.session?.duration == 18000)
        #expect(snapshot.weekly?.duration == 604800)
        #expect(snapshot.availableWindows == [.session, .weekly])
    }

    @Test("Fixtures carry no PII")
    func fixturesAreRedacted() throws {
        for name in ["wham-usage.json", "wham-usage-dual-window.json"] {
            let body = String(decoding: try Self.fixture(name), as: UTF8.self)
            #expect(body.contains("user@example.com"), "\(name): email should be redacted")
            #expect(!body.contains("@crocodilelabs"), "\(name): real email leaked")
        }
    }
}

@Suite("UsageSnapshot window availability")
struct UsageSnapshotAvailabilityTests {

    private static func snapshot(session: Double?, weekly: Double?) -> UsageSnapshot {
        UsageSnapshot(
            session: session.map { UsageWindow(utilization: $0, resetsAt: nil, duration: 18000) },
            weekly: weekly.map { UsageWindow(utilization: $0, resetsAt: nil, duration: 604800) }
        )
    }

    @Test("availableWindows lists published windows in display order")
    func availableWindowsOrder() {
        #expect(Self.snapshot(session: 1, weekly: 2).availableWindows == [.session, .weekly])
        #expect(Self.snapshot(session: nil, weekly: 2).availableWindows == [.weekly])
        #expect(Self.snapshot(session: 1, weekly: nil).availableWindows == [.session])
        #expect(Self.snapshot(session: nil, weekly: nil).availableWindows.isEmpty)
    }

    @Test("Preferred window is honored when it's published")
    func resolvesToPreference() {
        let snapshot = Self.snapshot(session: 1, weekly: 2)
        #expect(snapshot.resolvedWindow(preferring: .session) == .session)
        #expect(snapshot.resolvedWindow(preferring: .weekly) == .weekly)
    }

    @Test("Preferring a retired window falls back to the published one")
    func fallsBackWhenPreferredMissing() {
        // The case that matters today: a user whose saved preference is
        // Session, on an API that no longer publishes it.
        let snapshot = Self.snapshot(session: nil, weekly: 2)
        #expect(snapshot.resolvedWindow(preferring: .session) == .weekly)
    }

    @Test("No published windows resolves to nil")
    func resolvesToNilWhenEmpty() {
        #expect(Self.snapshot(session: nil, weekly: nil).resolvedWindow(preferring: .session) == nil)
    }

    @Test("Persisted pre-rename raw values still decode")
    func migratesLegacyRawValues() {
        #expect(TrackedWindow.fromPersisted("fiveHour") == .session)
        #expect(TrackedWindow.fromPersisted("sevenDay") == .weekly)
        #expect(TrackedWindow.fromPersisted("session") == .session)
        #expect(TrackedWindow.fromPersisted("weekly") == .weekly)
        #expect(TrackedWindow.fromPersisted("nonsense") == nil)
    }
}

/// The body observed from `GET /backend-api/wham/usage` on 2026-07-27
/// (PII redacted): session limits retired, the weekly window occupying
/// `primary_window`. Mirrors `assets/fixtures/wham-usage.json`.
private let weeklyOnlyResponse = """
{
  "user_id": "user-XXXXXXXXXXXXXXXXXX",
  "account_id": "user-XXXXXXXXXXXXXXXXXX",
  "email": "user@example.com",
  "plan_type": "prolite",
  "rate_limit": {
    "allowed": true,
    "limit_reached": false,
    "primary_window": {
      "used_percent": 12,
      "limit_window_seconds": 604800,
      "reset_after_seconds": 448085,
      "reset_at": 1785615365
    },
    "secondary_window": null
  },
  "code_review_rate_limit": null,
  "additional_rate_limits": [
    {
      "limit_name": "GPT-5.3-Codex-Spark",
      "metered_feature": "codex_bengalfox",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {"used_percent": 0, "limit_window_seconds": 604800, "reset_after_seconds": 604800, "reset_at": 1785772080},
        "secondary_window": null
      }
    }
  ],
  "credits": {
    "has_credits": false,
    "unlimited": false,
    "overage_limit_reached": false,
    "balance": "0",
    "approx_local_messages": [0, 0],
    "approx_cloud_messages": [0, 0]
  },
  "spend_control": {"reached": false, "individual_limit": null},
  "rate_limit_reached_type": null,
  "promo": null,
  "rate_limit_reset_credits": {"available_count": 2, "applicable_available_count": 0}
}
"""

/// The body observed on 2026-05-01, back when OpenAI published a 5h
/// session window alongside the weekly one. Kept so the parser stays
/// correct if session limits are reinstated. Mirrors
/// `assets/fixtures/wham-usage-dual-window.json`.
private let dualWindowResponse = """
{
  "user_id": "user-XXXXXXXXXXXXXXXXXX",
  "account_id": "user-XXXXXXXXXXXXXXXXXX",
  "email": "user@example.com",
  "plan_type": "prolite",
  "rate_limit": {
    "allowed": true,
    "limit_reached": false,
    "primary_window": {
      "used_percent": 1,
      "limit_window_seconds": 18000,
      "reset_after_seconds": 12496,
      "reset_at": 1777694872
    },
    "secondary_window": {
      "used_percent": 4,
      "limit_window_seconds": 604800,
      "reset_after_seconds": 301422,
      "reset_at": 1777983799
    }
  },
  "code_review_rate_limit": null,
  "additional_rate_limits": [
    {
      "limit_name": "GPT-5.3-Codex-Spark",
      "metered_feature": "codex_bengalfox",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {"used_percent": 0, "limit_window_seconds": 18000, "reset_after_seconds": 18000, "reset_at": 1777700377},
        "secondary_window": {"used_percent": 0, "limit_window_seconds": 604800, "reset_after_seconds": 604800, "reset_at": 1778287177}
      }
    }
  ],
  "credits": {
    "has_credits": false,
    "unlimited": false,
    "overage_limit_reached": false,
    "balance": "0",
    "approx_local_messages": [0, 0],
    "approx_cloud_messages": [0, 0]
  },
  "spend_control": {"reached": false, "individual_limit": null},
  "rate_limit_reached_type": null,
  "promo": null,
  "referral_beacon": null
}
"""
