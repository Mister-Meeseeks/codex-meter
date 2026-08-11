# Auth: reading Codex CLI's locally-cached OAuth token

codex-meter is a passive read-only consumer of Codex CLI's existing OAuth state. We don't run an OAuth flow, don't register a third-party client, and don't store our own tokens. On every poll we read the bearer token Codex CLI has cached on disk and use it for `wham/usage`, plus a supplementary reset-detail call only when the usage response reports a banked reset.

This is dramatically simpler than the claude-meter equivalent: Claude desktop encrypts its tokens under the macOS keychain (Chromium Safe Storage scheme, AES-128-CBC, PBKDF2-HMAC-SHA1). Codex CLI just writes plaintext JSON. There is no decryption to perform, no keychain prompt on first launch, no ACL gymnastics.

## Last verified

- 2026-05-01 — Codex CLI auth schema, `~/.codex/auth.json` mode 0600.

## Hard dependencies

- Codex CLI must be installed.
- The user must have run `codex login` at least once. Codex CLI refreshes the access token in the background when needed; codex-meter just re-reads the file on every poll.
- If Codex CLI hasn't run in long enough that the cached access token has expired, codex-meter will get HTTP 401 and surface "Run `codex login` to refresh your sign-in" until the user does so.

## Data source

```
~/.codex/auth.json
```

File mode is 0600, owned by the user that ran `codex login`. The schema we observed:

```json
{
  "OPENAI_API_KEY": "<top-level alias, may be absent>",
  "tokens": {
    "access_token": "<the bearer we send>",
    "id_token": "...",
    "refresh_token": "...",
    "account_id": "..."
  },
  "last_refresh": "..."
}
```

We prefer `tokens.access_token`. `OPENAI_API_KEY` is a convenience alias that exists at the top level on some installs; it's the fallback. Token expiry isn't surfaced in this file (Codex CLI rotates in place), so we don't filter on it — a stale token surfaces as HTTP 401 from the API instead.

## Read procedure

1. Read `~/.codex/auth.json` as raw bytes.
2. Decode as JSON object.
3. Try `tokens.access_token` (string, non-empty) — return it.
4. Fall back to top-level `OPENAI_API_KEY` (string, non-empty) — return it.
5. Otherwise throw `noUsableToken` (Codex CLI not signed in) or `authFileMalformed` (schema unrecognized).

The `parseTokenFromAuthJSON(_:)` helper in `Services/TokenReader.swift` is a pure function so it's unit-tested directly. The `currentToken()` entry point handles the file IO and surfaces typed errors:

| Symptom | Cause | User-facing message |
|---|---|---|
| `~/.codex/auth.json` missing | Codex CLI not installed or `codex login` never run | "Run `codex login` to enable Codex Meter." |
| File present but unreadable | Permission / IO error | "Couldn't read ~/.codex/auth.json. Check file permissions." |
| File parses but no recognized token field | Codex CLI changed its auth format | "Codex CLI changed its auth format. Update Codex Meter." |
| `tokens.access_token` empty / login incomplete | `codex login` started but didn't finish | "Run `codex login` to refresh your sign-in." |
| API returns 401 | Cached token expired and Codex CLI hasn't refreshed | Same — "Run `codex login` to refresh your sign-in." |

## Critical implementation rule

**Re-read the file on every poll. Never cache the access token across polls.** The token read for a poll may be used for the normal `wham/usage` request and, when that response reports an available banked reset, the immediately-following reset-detail request.

Codex CLI rotates the access token in place: when it refreshes, it writes new bytes to `auth.json`, and we want our next poll to pick those up. The file read is microseconds; there's no perf reason to cache.

## Keychain backend (not supported in v1)

Codex CLI optionally stores tokens in the macOS keychain instead of `auth.json`. codex-meter doesn't read the keychain backend in v1 — if a user has explicitly switched, our error message points them at the file path. Adding keychain support is straightforward (`SecItemCopyMatching` against the documented Codex item) but deferred until anyone reports needing it.

## What we never do

- Modify Codex CLI's `auth.json` or any of its files.
- Mint our own OAuth tokens or run an OAuth flow.
- Register a third-party `client_id` with OpenAI.
- Send Codex CLI's `User-Agent` string. We send our own (`codex-meter/<version> (macOS)`) so any detection on OpenAI's side sees us as ourselves.
- Cache the decrypted access token across polls.
- Send tokens off-device.

## Re-verification

When Codex CLI ships a new version, sanity-check:

```sh
# auth.json still where we expect, schema still readable
ls -la ~/.codex/auth.json
jq -r 'paths(scalars) | join(".")' ~/.codex/auth.json

# extract-codex-token.sh still finds the bearer
utils/extract-codex-token.sh | head -c 16 && echo "..."

# probe the endpoint with the extracted token
utils/probe-codex-usage-api.sh
```

The `probe-codex-usage-api.sh` script does a more thorough sweep — it captures both response body and headers and saves a fresh fixture for parser tests. Run it after any major Codex CLI version bump.

## Policy context

The `wham/usage` and reset-detail endpoints are **undocumented** internal surfaces; `wham/usage` is the one Codex CLI polls for its `/status` view (see openai/codex#10869). OpenAI has not published a stable API for usage queries; feature requests for a headless `codex status --json` are open and unmerged (openai/codex#10233, openai/codex#15281).

This means the endpoint and its response shape can change without notice. codex-meter's parser is forward-compatible (unknown fields are silently ignored), and HTTP errors degrade gracefully — a 404 surfaces "Codex Meter needs an update."

If OpenAI ships a documented usage API, codex-meter should switch to it. The current consumer pattern is "we use what the official CLI uses, and accept that as load-bearing observation."
