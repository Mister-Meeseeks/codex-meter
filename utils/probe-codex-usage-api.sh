#!/usr/bin/env bash
# probe-codex-usage-api.sh — fetch the Codex /wham/usage endpoint, dump
# headers + body, and save a fixture for parser tests.
#
# Run after any Codex CLI version bump that might have moved the endpoint
# or changed the response shape.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"

OUT_BODY="${OUT_BODY:-/tmp/codex-meter-usage-probe.json}"
OUT_HEADERS="${OUT_HEADERS:-/tmp/codex-meter-usage-probe.headers.txt}"
FIXTURE_DIR="$REPO_ROOT/assets/fixtures"
FIXTURE_PATH="$FIXTURE_DIR/wham-usage.json"

TOKEN="$("$HERE/extract-codex-token.sh")"

mkdir -p "$FIXTURE_DIR"

# -D dumps headers, -w captures status separately (some 4xx bodies aren't
# JSON, so we don't pipe through jq unconditionally).
HTTP_STATUS="$(
    curl -sS -D "$OUT_HEADERS" -o "$OUT_BODY" -w "%{http_code}" \
        -H "Accept: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -H "User-Agent: codex-meter-probe/0.0 (macOS)" \
        "https://chatgpt.com/backend-api/wham/usage"
)"

echo "--- HTTP $HTTP_STATUS ---"
echo
echo "--- Headers ---"
cat "$OUT_HEADERS"
echo
echo "--- Body ---"
if jq . "$OUT_BODY" 2>/dev/null; then
    : # already pretty-printed
else
    cat "$OUT_BODY"
fi
echo

if [[ "$HTTP_STATUS" == "200" ]]; then
    # Save a fixture for parser tests. Only save 200s so we don't accidentally
    # bake an error response into the test bundle. Redact PII (user_id,
    # account_id, email) so the fixture is safe to commit.
    if jq '
        (.user_id // empty) |= "user-XXXXXXXXXXXXXXXXXX"
        | (.account_id // empty) |= "user-XXXXXXXXXXXXXXXXXX"
        | (.email // empty) |= "user@example.com"
    ' "$OUT_BODY" > "$FIXTURE_PATH" 2>/dev/null; then
        echo "fixture saved (PII redacted) → $FIXTURE_PATH"
    else
        echo "WARN: 200 OK but body wasn't JSON — fixture not saved" >&2
    fi
fi

echo "body    → $OUT_BODY"
echo "headers → $OUT_HEADERS"
