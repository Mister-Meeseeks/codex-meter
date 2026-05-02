# API: `wham/usage`

This document pins the empirically observed shape of the Codex usage endpoint and how `codex-meter` parses it. **The endpoint is undocumented** — it's the same one Codex CLI polls for its `/status` view. Re-verify after every Codex CLI version bump.

## Last verified

- Date: 2026-05-01
- Probed via Codex CLI's cached access token (plan: `prolite`).
- Saved fixture: `assets/fixtures/wham-usage.json` (PII redacted).

## Request

```
GET https://chatgpt.com/backend-api/wham/usage
```

| Header | Value |
|--------|-------|
| `Accept` | `application/json` |
| `Authorization` | `Bearer <access-token>` |
| `User-Agent` | `codex-meter/<version> (macOS)` |

No `Content-Type` (no body), no beta-channel header. The bearer is `tokens.access_token` from `~/.codex/auth.json`; see `docs/auth.md`.

## Auth requirements

- A logged-in Codex CLI install. No specific scope is enforced beyond the token itself being valid.
- An expired or revoked token returns HTTP 401. The poller surfaces this as "Run `codex login` to refresh your sign-in" — the recovery is to relaunch Codex CLI, which refreshes the token in the background.

## Response shape

Observed body (2026-05-01, PII redacted):

```json
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
      "rate_limit": { ... }
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
```

## Field reference

### `rate_limit.primary_window`, `rate_limit.secondary_window` (the v1 surface)

These are the two windows codex-meter decodes. Identical shape; either may be `null` (whole window absent), and any field within may be `null`.

| Field | Type | Notes |
|-------|------|-------|
| `used_percent` | `Number` | Percentage 0–100. Integer in observed responses but parser accepts any numeric. **Not a fraction.** Values >= 100 possible once a window is exhausted; clamp at the view layer. |
| `limit_window_seconds` | `Int` | Window duration. Currently `18000` (5h) for primary, `604800` (7d) for secondary. We don't decode this — `Models/UsageWindow.swift` keeps fixed `fiveHourDuration` / `sevenDayDuration` constants in `UsageStore`, with a note. |
| `reset_after_seconds` | `Int` | Pre-computed countdown. Redundant with `reset_at` for our purposes; we compute live countdowns from `reset_at`. Not decoded. |
| `reset_at` | `Number` (unix seconds) | Absolute reset time. Decoded as `Date(timeIntervalSince1970:)`. May be `null`. |

The window-name mapping in `UsageSnapshot`:
- `primary_window` → `UsageSnapshot.fiveHour`
- `secondary_window` → `UsageSnapshot.sevenDay`

The Swift property names are a holdover from the claude-meter fork; they're accurate today (windows are exactly 5h / 7d) but if OpenAI ever changes the windows, rename them. See the doc-comment in `Models/UsageSnapshot.swift`.

### Other fields (out of v1 scope, may surface in v1.1)

| Field | Likely meaning | Action in v1 |
|-------|---------------|--------------|
| `user_id`, `account_id`, `email` | User identity | Ignore (PII; we don't surface or log) |
| `plan_type` | Subscription tier (e.g. `prolite`, `pro`, `team`) | Ignore — could badge popover later |
| `code_review_rate_limit` | Per-feature limit (Codex code review) | Ignore |
| `additional_rate_limits` | Per-feature buckets (Spark / Bengalfox / etc.) | Ignore |
| `credits` | Pay-as-you-go balance | Ignore — out of scope per AGENTS.md (not a billing tracker) |
| `spend_control` | User-set spend cap | Ignore |
| `rate_limit_reached_type` | Categorical reason if a limit is hit | Ignore |
| `promo`, `referral_beacon` | Marketing surfaces | Ignore |

## Edge cases the parser must handle

1. **`rate_limit` absent or `null`.** Treat as both windows nil (no data). Parser test: `decodesWithoutRateLimit`, `decodesNullRateLimit`.
2. **`primary_window` or `secondary_window` is `null`.** Treat that window as nil. Parser test: `decodesNullWindows`.
3. **Window present but `reset_at` missing.** Surface as "resets unknown"; do not try to format a `nil` date. Parser test: `decodesMissingResetAt`.
4. **Unknown top-level fields.** OpenAI adds new fields freely. Parser MUST ignore unknown keys. Test: `ignoresUnknownFields`.
5. **`used_percent` exactly 100 or above.** Cap the visual bar at 100%; treat anything `>= 100` as "at limit". Test: `utilizationCanExceed100`.
6. **HTTP errors:**
   - `401`: surface "Run `codex login` to refresh your sign-in."
   - `403`: plan-tier mismatch — "Authorization rejected — your Codex plan may not allow this."
   - `404`: endpoint removed — "Codex Meter needs an update."
   - `5xx`: transient; honor exponential backoff in `UsagePoller`.
   - `429` with `Retry-After`: honored as a one-shot sleep override.
   - Network failure: keep last known snapshot, mark stale in popover.

## Parser strategy

```swift
struct UsageWindow: Decodable {
    let utilization: Double  // from used_percent
    let resetsAt: Date?      // from reset_at (unix seconds)
    // Custom init(from:) decodes used_percent → Double, reset_at → Date.
}

struct UsageSnapshot: Decodable {
    let fiveHour: UsageWindow?   // from rate_limit.primary_window
    let sevenDay: UsageWindow?   // from rate_limit.secondary_window
    // Custom init(from:) reaches through the rate_limit nesting.
}
```

- Decode only the two fields we use. All other top-level keys are silently ignored — free forward-compatibility.
- `UsageWindow` does its own date decoding (unix seconds → `Date`), so the top-level `JSONDecoder` is plain — no custom strategy required.

## Re-verification

```sh
# Probe the endpoint with the user's current token; saves a fresh fixture
# (PII redacted) to assets/fixtures/wham-usage.json.
utils/probe-codex-usage-api.sh
```

If the shape changes meaningfully (renamed fields, different units, different date format), update the parser and bump codex-meter's minor version with a changelog note.

## Stability disclaimer

Because the endpoint is undocumented and the CLI's internal surface, OpenAI may move it, rename fields, or break the response shape without notice. codex-meter handles drift gracefully — unknown fields are ignored, missing windows decode to nil, and HTTP failures degrade with the appropriate user-facing message. But the app's correctness floor is "we use what the official CLI uses; if OpenAI changes that, we follow."
