import Foundation

/// Single concrete `UsageProvider` for the Codex backend. Combines
/// credential reading and HTTP fetch behind one entry point.
struct CodexProvider: UsageProvider {
    /// Closure rather than a concrete dependency so tests can inject a
    /// fake without subclassing `TokenReader`.
    private let credentialsReader: @Sendable () throws -> TokenReader.Credentials
    private let session: URLSession

    init(
        credentialsReader: @escaping @Sendable () throws -> TokenReader.Credentials = {
            try TokenReader.currentCredentials()
        },
        session: URLSession = .shared
    ) {
        self.credentialsReader = credentialsReader
        self.session = session
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let credentials = try credentialsReader()
        return try await CodexAPI.fetchUsage(credentials: credentials, session: session)
    }
}
