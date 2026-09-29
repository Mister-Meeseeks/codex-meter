import Foundation
import Testing
@testable import CodexMeter

@Suite("TokenReader.parseCredentialsFromAuthJSON")
struct TokenReaderParseTests {

    private func makeAuthJSON(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    @Test("Picks tokens.access_token when present")
    func picksTokensAccessToken() throws {
        let json = makeAuthJSON([
            "OPENAI_API_KEY": "top-level-alias",
            "tokens": [
                "access_token": "the-real-bearer",
                "id_token": "ignored",
                "refresh_token": "ignored",
                "account_id": "user-XXXX",
            ],
            "last_refresh": "2026-04-26T22:24:00Z",
        ])
        let credentials = try TokenReader.parseCredentialsFromAuthJSON(json)
        #expect(credentials.accessToken == "the-real-bearer")
        #expect(credentials.accountID == "user-XXXX")
    }

    @Test("Falls back to OPENAI_API_KEY when tokens.access_token is absent")
    func fallsBackToTopLevel() throws {
        let json = makeAuthJSON([
            "OPENAI_API_KEY": "top-level-fallback",
            "last_refresh": "2026-04-26T22:24:00Z",
        ])
        let credentials = try TokenReader.parseCredentialsFromAuthJSON(json)
        #expect(credentials.accessToken == "top-level-fallback")
        #expect(credentials.accountID == nil)
    }

    @Test("Falls back to OPENAI_API_KEY when tokens object is empty")
    func fallsBackWhenTokensEmpty() throws {
        let json = makeAuthJSON([
            "OPENAI_API_KEY": "top-level-fallback",
            "tokens": [String: Any](),
        ])
        let credentials = try TokenReader.parseCredentialsFromAuthJSON(json)
        #expect(credentials.accessToken == "top-level-fallback")
        #expect(credentials.accountID == nil)
    }

    @Test("Account ID is nil when tokens.account_id is missing or empty")
    func accountIDOptional() throws {
        for tokens: [String: Any] in [
            ["access_token": "bearer"],
            ["access_token": "bearer", "account_id": ""],
        ] {
            let credentials = try TokenReader.parseCredentialsFromAuthJSON(
                makeAuthJSON(["tokens": tokens])
            )
            #expect(credentials.accessToken == "bearer")
            #expect(credentials.accountID == nil)
        }
    }

    @Test("Throws noUsableToken when tokens.access_token is empty string")
    func throwsOnEmptyAccessToken() {
        let json = makeAuthJSON([
            "tokens": ["access_token": ""],
        ])
        #expect(throws: TokenReader.ReadError.noUsableToken) {
            try TokenReader.parseCredentialsFromAuthJSON(json)
        }
    }

    @Test("Throws noUsableToken when OPENAI_API_KEY is empty string")
    func throwsOnEmptyTopLevel() {
        let json = makeAuthJSON([
            "OPENAI_API_KEY": "",
        ])
        #expect(throws: TokenReader.ReadError.noUsableToken) {
            try TokenReader.parseCredentialsFromAuthJSON(json)
        }
    }

    @Test("Throws authFileMalformed when no recognized token field exists")
    func throwsWhenNoTokenField() {
        let json = makeAuthJSON([
            "last_refresh": "2026-04-26T22:24:00Z",
            "unrelated": "data",
        ])
        #expect(throws: TokenReader.ReadError.authFileMalformed) {
            try TokenReader.parseCredentialsFromAuthJSON(json)
        }
    }

    @Test("Throws authFileMalformed on non-JSON input")
    func throwsOnNonJSON() {
        #expect(throws: TokenReader.ReadError.authFileMalformed) {
            try TokenReader.parseCredentialsFromAuthJSON(Data("not json".utf8))
        }
    }

    @Test("Throws authFileMalformed on JSON that isn't a top-level object")
    func throwsOnJSONArray() {
        let arr = try! JSONSerialization.data(withJSONObject: ["a", "b", "c"])
        #expect(throws: TokenReader.ReadError.authFileMalformed) {
            try TokenReader.parseCredentialsFromAuthJSON(arr)
        }
    }
}

@Suite("CodexAPI.makeRequest")
struct CodexAPIRequestTests {

    @Test("Sends chatgpt-account-id when the account is known")
    func sendsAccountHeader() {
        let request = CodexAPI.makeRequest(
            url: CodexAPI.usageURL,
            credentials: .init(accessToken: "bearer", accountID: "acct-123")
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer bearer")
        #expect(request.value(forHTTPHeaderField: "chatgpt-account-id") == "acct-123")
    }

    @Test("Omits chatgpt-account-id when the account is unknown")
    func omitsAccountHeader() {
        let request = CodexAPI.makeRequest(
            url: CodexAPI.usageURL,
            credentials: .init(accessToken: "bearer", accountID: nil)
        )
        #expect(request.value(forHTTPHeaderField: "chatgpt-account-id") == nil)
    }
}
