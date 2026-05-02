import Foundation

/// Single concrete `UsageProvider` for the Codex backend. Combines token
/// reading and HTTP fetch behind one entry point.
struct CodexProvider: UsageProvider {
    /// Closure rather than a concrete dependency so tests can inject a
    /// fake without subclassing `TokenReader`.
    private let tokenReader: @Sendable () throws -> String
    private let session: URLSession

    init(
        tokenReader: @escaping @Sendable () throws -> String = { try TokenReader.currentToken() },
        session: URLSession = .shared
    ) {
        self.tokenReader = tokenReader
        self.session = session
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let token = try tokenReader()
        return try await CodexAPI.fetchUsage(token: token, session: session)
    }
}
