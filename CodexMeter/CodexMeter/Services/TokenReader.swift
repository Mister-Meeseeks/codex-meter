import Foundation

/// Reads Codex CLI's locally-cached OAuth bearer token and account ID.
///
/// Codex CLI stores its OAuth state in plaintext at `~/.codex/auth.json`
/// (mode 0600). There is no decryption to perform — unlike Claude desktop,
/// where the token is AES-encrypted under a Chromium Safe Storage master
/// key in the keychain. We just read the file on every poll.
///
/// **Re-read on every poll. Never cache the access token across HTTP calls.**
/// Codex CLI rotates the access token in place; a fresh value written to
/// disk is what we want our next poll to pick up. The file read is cheap
/// (microseconds), so there's no perf reason to cache.
///
/// See `docs/auth.md` for the full protocol.
enum TokenReader {
    enum ReadError: Error, Equatable {
        /// `~/.codex/auth.json` doesn't exist. Codex CLI not installed or
        /// `codex login` never run.
        case authFileMissing
        /// File exists but couldn't be read (permissions, IO error).
        case authFileUnreadable
        /// JSON parse failed or the expected schema isn't there.
        case authFileMalformed
        /// File parsed and we found a token field, but it was empty.
        /// Typically means `codex login` was started but didn't complete.
        case noUsableToken
    }

    /// What a poll needs from `auth.json`: the bearer and, when present,
    /// the account it belongs to.
    struct Credentials: Equatable, Sendable {
        let accessToken: String
        /// `tokens.account_id`. Sent as `chatgpt-account-id` so
        /// `wham/usage` reports the same account context Codex CLI and
        /// the web UI see — without it the server picks its own context
        /// and has reported roughly double the real `used_percent`.
        /// `nil` on the `OPENAI_API_KEY` fallback path, which has none.
        let accountID: String?
    }

    nonisolated static let authFileRelativePath = ".codex/auth.json"

    /// Full happy path. Throws a typed `ReadError` on any failure so callers
    /// can pick the right user-facing message.
    nonisolated static func currentCredentials() throws -> Credentials {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent(authFileRelativePath)
        guard FileManager.default.fileExists(atPath: path) else {
            throw ReadError.authFileMissing
        }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw ReadError.authFileUnreadable
        }
        return try parseCredentialsFromAuthJSON(data)
    }

    /// Pure parser, unit tested. Extracts the bearer token and account ID
    /// from the auth.json contents.
    ///
    /// Observed schema (Codex CLI, 2026-04-26):
    /// ```
    /// {
    ///   "OPENAI_API_KEY": "<top-level alias, may be absent>",
    ///   "tokens": {
    ///     "access_token": "<the bearer we send>",
    ///     "id_token": "...",
    ///     "refresh_token": "...",
    ///     "account_id": "..."
    ///   },
    ///   "last_refresh": "..."
    /// }
    /// ```
    /// We prefer `tokens.access_token` — `OPENAI_API_KEY` is a convenience
    /// alias that may lag during refreshes. Token expiry isn't surfaced in
    /// this file (Codex CLI rotates in place), so we don't filter on it; a
    /// stale token surfaces as HTTP 401 from the API and the user-facing
    /// message tells them to run `codex login`. An empty or missing
    /// `account_id` is not an error — the request just omits the header.
    nonisolated static func parseCredentialsFromAuthJSON(_ data: Data) throws -> Credentials {
        guard
            let parsed = try? JSONSerialization.jsonObject(with: data),
            let dict = parsed as? [String: Any]
        else {
            throw ReadError.authFileMalformed
        }
        if let tokens = dict["tokens"] as? [String: Any],
           let access = tokens["access_token"] as? String {
            guard !access.isEmpty else { throw ReadError.noUsableToken }
            let accountID = (tokens["account_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return Credentials(accessToken: access, accountID: accountID)
        }
        if let topLevel = dict["OPENAI_API_KEY"] as? String {
            guard !topLevel.isEmpty else { throw ReadError.noUsableToken }
            return Credentials(accessToken: topLevel, accountID: nil)
        }
        throw ReadError.authFileMalformed
    }
}
