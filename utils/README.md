# utils/

Verification helpers used during development and for periodic re-checks against Codex CLI's auth file and the `wham/usage` endpoint. **Not** part of the shipped app — these are developer-side tools.

## Scripts

### `extract-codex-token.sh`

Prints the cached Codex CLI bearer token to stdout. Reads `~/.codex/auth.json` (override with `$CODEX_AUTH_PATH`) and extracts `tokens.access_token`, falling back to top-level `OPENAI_API_KEY`. Exits non-zero with a diagnostic if the file is missing or no recognized token field is present.

```sh
utils/extract-codex-token.sh > /dev/null && echo "got token" || echo "no token"
```

Use this when you need a token for one-off curl invocations against `chatgpt.com/backend-api/*`.

### `probe-codex-usage-api.sh`

Calls `GET https://chatgpt.com/backend-api/wham/usage` and dumps the response. Saves a redacted fixture (with `user_id`, `account_id`, and `email` replaced) to `assets/fixtures/wham-usage.json` for parser tests. Run after any Codex CLI version bump that might have moved the endpoint or changed the response shape.

```sh
utils/probe-codex-usage-api.sh
```

Outputs:
- HTTP status + headers to stdout
- Pretty-printed body to stdout
- Body to `/tmp/codex-meter-usage-probe.json`
- Headers to `/tmp/codex-meter-usage-probe.headers.txt`
- Redacted fixture to `assets/fixtures/wham-usage.json` (only on HTTP 200)

`assets/fixtures/wham-usage-dual-window.json` sits alongside it as a hand-kept archive of the shape the endpoint returned while OpenAI still published a 5h session window. The probe never touches it.

## Why these aren't in the app

- They depend on shell-side tools (`jq`, `curl`) that are fine for a developer-side probe but wrong for the shipped binary.
- They're for verification, not user-facing functionality. The production code path is the in-app `TokenReader` + `CodexProvider` + `CodexAPI`.
- If the probe scripts return data the app doesn't, that's a parser bug — fix the parser, not the script.

## When to re-run

- Whenever Codex CLI ships a new version, to confirm the auth-file schema and endpoint shape still match what `Services/TokenReader.swift` and `Services/CodexAPI.swift` decode.
- Before cutting a release, as a smoke test that the API contract hasn't drifted.
- When debugging "why doesn't my popover show data?" — the probe surfaces 4xx/5xx + headers that the in-app error path may compress.
