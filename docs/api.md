# API: `wham/usage`

This document pins the empirically observed shape of the Codex usage endpoint and how `codex-meter` parses it. **The endpoint is undocumented** — it's the same one Codex CLI polls for its `/status` view. Re-verify after every Codex CLI version bump.

## Last verified

- Date: 2026-07-27
- Probed via Codex CLI's cached access token (plan: `prolite`).
- Saved fixtures (PII redacted):
  - `assets/fixtures/wham-usage.json` — current shape, weekly window only
  - `assets/fixtures/wham-usage-dual-window.json` — 2026-05-01 shape, session + weekly

### Window history

OpenAI **retired the 5h session limit** sometime between 2026-05-01 and 2026-07-27. The weekly window moved into `primary_window` and `secondary_window` went `null`. They may reinstate session limits, so the parser handles one window or two, in either slot, without a code change — see "Window identification" below.

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

Observed body (2026-07-27, PII redacted):

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
  "rate_limit_reset_credits": {"available_count": 2, "applicable_available_count": 0}
}
```

Deltas from the 2026-05-01 body: `secondary_window` is now `null`, `primary_window` carries the weekly window, `referral_beacon` is gone, and `rate_limit_reset_credits` is new. Only the window change required code; the other two are absorbed by ignore-unknown-fields decoding.

## Field reference

### `rate_limit.primary_window`, `rate_limit.secondary_window` (the v1 surface)

These are the two slots codex-meter decodes. Identical shape; either may be `null` (whole window absent), and any field within may be `null`. **The slots are positional, not semantic** — see "Window identification" below.

| Field | Type | Notes |
|-------|------|-------|
| `used_percent` | `Number` | Percentage 0–100. Integer in observed responses but parser accepts any numeric. **Not a fraction.** Values >= 100 possible once a window is exhausted; clamp at the view layer. |
| `limit_window_seconds` | `Int` | Window duration — `18000` (5h) for a session window, `604800` (7d) for the weekly one. **Load-bearing:** decoded into `UsageWindow.duration` and used both to identify which window this is and to compute the projection. Optional in the parser; see the fallback below. |
| `reset_after_seconds` | `Int` | Pre-computed countdown. Redundant with `reset_at` for our purposes; we compute live countdowns from `reset_at`. Not decoded. |
| `reset_at` | `Number` (unix seconds) | Absolute reset time. Decoded as `Date(timeIntervalSince1970:)`. May be `null`. |

## Window identification

**Never map windows by slot position.** codex-meter did that originally — `primary_window` → session, `secondary_window` → weekly — and when OpenAI retired session limits and moved the weekly window into `primary_window`, the app displayed weekly usage under a "Session" heading. Position is an ordering, not an identity.

`UsageSnapshot.classify(primary:secondary:)` sorts windows into slots by the length each one reports:

| `limit_window_seconds` | Slot |
|---|---|
| ≤ `sessionMaxDuration` (24h) | `UsageSnapshot.session` |
| > 24h | `UsageSnapshot.weekly` |
| absent | positional fallback: primary → session, secondary → weekly, for whichever slot isn't already claimed |

The 24h threshold sits in the empty gap between the two window families (5h vs 7d), so OpenAI retuning either one — a 3h session window, a 5-day weekly — lands in the right slot without a code change. First window into a slot wins; the API has never sent two of a kind.

The positional fallback is the weak spot: a response that drops `limit_window_seconds` **and** publishes only a weekly window in `primary_window` would be misfiled as a session window. Nothing else in the response identifies a window, so that case is unfixable without a new signal — re-verify if `limit_window_seconds` ever disappears.

Both slots are optional and the app treats every combination as normal: session-only, weekly-only (today), both, or neither. Nothing in the UI assumes a window exists.

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
| `promo`, `referral_beacon` | Marketing surfaces | Ignore (`referral_beacon` absent as of 2026-07-27) |
| `rate_limit_reset_credits` | Credits that reset a hit limit early | Ignore |

## Edge cases the parser must handle

1. **`rate_limit` absent or `null`.** Treat as both windows nil (no data). Parser test: `decodesWithoutRateLimit`, `decodesNullRateLimit`.
2. **`primary_window` or `secondary_window` is `null`.** Treat that slot as absent and classify whatever remains. Parser tests: `decodesNullWindows`, `decodesWeeklyOnlyResponse`.
3. **Windows in either slot / at new durations.** Classified by `limit_window_seconds`, never by position. Tests: `classifiesBySlotIndependentDuration`, `classifiesRetunedSessionWindow`, `classifiesAtThresholdBoundary`, `classifiedWindowBeatsPositionalFallback`.
4. **`limit_window_seconds` missing.** Falls back to positional mapping and to `UsageStore.fallbackDuration(for:)` for the projection math. Tests: `fallsBackToPositionalMapping`, `projectionUsesFallbackDuration`.
5. **Window present but `reset_at` missing.** Surface as "resets unknown"; do not try to format a `nil` date. Parser test: `decodesMissingResetAt`.
6. **Unknown top-level fields.** OpenAI adds new fields freely. Parser MUST ignore unknown keys. Test: `ignoresUnknownFields`.
7. **`used_percent` exactly 100 or above.** Cap the visual bar at 100%; treat anything `>= 100` as "at limit". Test: `utilizationCanExceed100`.
8. **HTTP errors:**
   - `401`: surface "Run `codex login` to refresh your sign-in."
   - `403`: plan-tier mismatch — "Authorization rejected — your Codex plan may not allow this."
   - `404`: endpoint removed — "Codex Meter needs an update."
   - `5xx`: transient; honor exponential backoff in `UsagePoller`.
   - `429` with `Retry-After`: honored as a one-shot sleep override.
   - Network failure: keep last known snapshot, mark stale in popover.

## Parser strategy

```swift
struct UsageWindow: Decodable {
    let utilization: Double    // from used_percent
    let resetsAt: Date?        // from reset_at (unix seconds)
    let duration: TimeInterval? // from limit_window_seconds
    // Custom init(from:) decodes used_percent → Double, reset_at → Date.
}

struct UsageSnapshot: Decodable {
    let session: UsageWindow?   // the short window, when published
    let weekly: UsageWindow?    // the long rolling window
    // Custom init(from:) reaches through the rate_limit nesting, then
    // routes both slots through classify(primary:secondary:).
}
```

- Decode only the three fields we use. All other keys are silently ignored — free forward-compatibility.
- `UsageWindow` does its own date decoding (unix seconds → `Date`), so the top-level `JSONDecoder` is plain — no custom strategy required.
- Slot names are roles, not durations. `session` is whatever short window is published; `weekly` is the long one. Don't reintroduce duration-based names — that's what made the last breakage confusing.

## Re-verification

```sh
# Probe the endpoint with the user's current token; saves a fresh fixture
# (PII redacted) to assets/fixtures/wham-usage.json.
utils/probe-codex-usage-api.sh
```

The script overwrites `wham-usage.json` only. `wham-usage-dual-window.json` is a hand-kept archive of the two-window shape — leave it alone unless OpenAI reinstates session limits, at which point re-probe and refresh both.

If the shape changes meaningfully (renamed fields, different units, different date format), update the parser and bump codex-meter's minor version with a changelog note. A window appearing or disappearing is **not** a parser change — that path is already covered.

## Stability disclaimer

Because the endpoint is undocumented and the CLI's internal surface, OpenAI may move it, rename fields, or break the response shape without notice. codex-meter handles drift gracefully — unknown fields are ignored, missing windows decode to nil, and HTTP failures degrade with the appropriate user-facing message. But the app's correctness floor is "we use what the official CLI uses; if OpenAI changes that, we follow."
