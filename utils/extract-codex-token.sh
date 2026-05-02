#!/usr/bin/env bash
# extract-codex-token.sh — print Codex CLI's cached access token to stdout.
#
# Codex CLI stores its OAuth state in plaintext at ~/.codex/auth.json. There
# is no decryption to perform, unlike Claude desktop. The file mode is 0600,
# so reading it requires running as the same user that ran `codex login`.
#
# Override path with $CODEX_AUTH_PATH if needed (e.g. for a sandboxed test).
set -euo pipefail

AUTH="${CODEX_AUTH_PATH:-$HOME/.codex/auth.json}"

if [[ ! -f "$AUTH" ]]; then
    echo "codex auth file not found at $AUTH" >&2
    echo "run 'codex login' first." >&2
    exit 1
fi

# Tokens.access_token is the bearer Codex CLI itself uses. OPENAI_API_KEY is
# a top-level convenience alias; on a freshly-logged-in install it may be
# absent or stale. Prefer access_token.
TOKEN="$(jq -r '.tokens.access_token // .OPENAI_API_KEY // empty' "$AUTH")"

if [[ -z "$TOKEN" ]]; then
    echo "auth.json present but no recognized token field." >&2
    echo "keys observed:" >&2
    jq -r 'paths(scalars) | join(".")' "$AUTH" >&2
    exit 1
fi

echo "$TOKEN"
