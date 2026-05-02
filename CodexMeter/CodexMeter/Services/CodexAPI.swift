import Foundation

/// HTTP client for Codex's `wham/usage` endpoint.
///
/// The endpoint is **undocumented** — it's the same one Codex CLI polls
/// for its `/status` view (see openai/codex#10869). Treat all schema
/// details as load-bearing observations, not contracts. See `docs/api.md`
/// for the response shape this client decodes.
enum CodexAPI {
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    static var userAgent: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        return "codex-meter/\(v) (macOS)"
    }

    /// Plain `JSONDecoder` — `UsageWindow.init(from:)` handles its own
    /// date conversion (unix seconds), so no custom strategy is required.
    static let decoder = JSONDecoder()

    enum APIError: Error {
        /// 401 — token rejected. Caller should surface "run codex login".
        case unauthorized
        /// 403 — usually a scope / plan-tier mismatch. Body included for diagnostics.
        case forbidden(body: String)
        /// 404 — endpoint removed or moved. codex-meter likely needs an update.
        case notFound
        /// 429 — rate limited. `retryAfter` is parsed from the `Retry-After`
        /// header in seconds when the server provides it, else nil.
        case rateLimited(retryAfter: TimeInterval?)
        /// 5xx — server-side issue. Caller should back off and retry later.
        case server(status: Int)
        /// HTTP succeeded but body didn't decode to UsageSnapshot.
        case decoding(underlying: any Error)
        /// Anything else (3xx, 4xx other than the above).
        case unexpected(status: Int, body: String)
        /// URLSession-level failure (offline, DNS, TLS, etc).
        case network(underlying: any Error)
        /// URLResponse wasn't an HTTPURLResponse.
        case invalidResponse
    }

    /// Parses the `Retry-After` HTTP header, which can be either an integer
    /// number of seconds or an HTTP date. Returns nil if absent or invalid.
    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)) {
            return max(0, seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: raw) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    static func fetchUsage(token: String, session: URLSession = .shared) async throws -> UsageSnapshot {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            do {
                return try decoder.decode(UsageSnapshot.self, from: data)
            } catch {
                throw APIError.decoding(underlying: error)
            }
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden(body: String(decoding: data, as: UTF8.self))
        case 404:
            throw APIError.notFound
        case 429:
            throw APIError.rateLimited(retryAfter: retryAfter(from: http))
        case 500..<600:
            throw APIError.server(status: http.statusCode)
        default:
            throw APIError.unexpected(
                status: http.statusCode,
                body: String(decoding: data, as: UTF8.self)
            )
        }
    }
}
