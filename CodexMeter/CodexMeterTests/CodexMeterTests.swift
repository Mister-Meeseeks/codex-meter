import Foundation
import Testing
@testable import CodexMeter

@Suite("UsageSnapshot decoding")
struct UsageSnapshotDecodingTests {

    @Test("Decodes the empirically observed full response")
    func decodesObservedResponse() throws {
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(observedResponse.utf8))
        #expect(snapshot.fiveHour?.utilization == 1.0)
        #expect(snapshot.sevenDay?.utilization == 4.0)
        #expect(snapshot.fiveHour?.resetsAt != nil)
        #expect(snapshot.sevenDay?.resetsAt != nil)
    }

    @Test("Body without rate_limit decodes to both-windows-nil")
    func decodesWithoutRateLimit() throws {
        let json = #"{"plan_type": "free"}"#
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.sevenDay == nil)
    }

    @Test("rate_limit: null decodes to both-windows-nil")
    func decodesNullRateLimit() throws {
        let json = #"{"rate_limit": null}"#
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.sevenDay == nil)
    }

    @Test("rate_limit present but windows null decodes to nil/nil")
    func decodesNullWindows() throws {
        let json = #"{"rate_limit": {"primary_window": null, "secondary_window": null}}"#
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.sevenDay == nil)
    }

    @Test("Window present but reset_at missing decodes resetsAt as nil")
    func decodesMissingResetAt() throws {
        let json = #"{"rate_limit": {"primary_window": {"used_percent": 0}, "secondary_window": null}}"#
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.fiveHour?.utilization == 0.0)
        #expect(snapshot.fiveHour?.resetsAt == nil)
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
          "future_field_openai_invents": "junk"
        }
        """
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.fiveHour?.utilization == 14.0)
        #expect(snapshot.sevenDay?.utilization == 65.0)
    }

    @Test("Utilization above 100 is preserved (caller clamps for display)")
    func utilizationCanExceed100() throws {
        let json = #"""
        {"rate_limit": {"primary_window": {"used_percent": 105.5, "reset_at": 1777694872}, "secondary_window": null}}
        """#
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.fiveHour?.utilization == 105.5)
    }

    @Test("Fractional used_percent decodes correctly")
    func decodesFractionalPercent() throws {
        let json = #"""
        {"rate_limit": {"primary_window": {"used_percent": 7.25, "reset_at": 1777694872}, "secondary_window": null}}
        """#
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.fiveHour?.utilization == 7.25)
    }

    @Test("reset_at unix seconds decodes to Date")
    func decodesUnixSecondsResetAt() throws {
        let json = #"""
        {"rate_limit": {"primary_window": {"used_percent": 14, "reset_at": 1777694872}, "secondary_window": null}}
        """#
        let snapshot = try CodexAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        guard let date = snapshot.fiveHour?.resetsAt else {
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

/// Trimmed copy of the body observed from `GET /backend-api/wham/usage`
/// on 2026-05-01 (PII redacted). Pinned here so the parser keeps working
/// as OpenAI adds new top-level fields.
private let observedResponse = """
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
