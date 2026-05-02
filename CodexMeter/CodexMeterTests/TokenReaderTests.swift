import Foundation
import Testing
@testable import CodexMeter

@Suite("TokenReader.parseTokenFromAuthJSON")
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
        let token = try TokenReader.parseTokenFromAuthJSON(json)
        #expect(token == "the-real-bearer")
    }

    @Test("Falls back to OPENAI_API_KEY when tokens.access_token is absent")
    func fallsBackToTopLevel() throws {
        let json = makeAuthJSON([
            "OPENAI_API_KEY": "top-level-fallback",
            "last_refresh": "2026-04-26T22:24:00Z",
        ])
        let token = try TokenReader.parseTokenFromAuthJSON(json)
        #expect(token == "top-level-fallback")
    }

    @Test("Falls back to OPENAI_API_KEY when tokens object is empty")
    func fallsBackWhenTokensEmpty() throws {
        let json = makeAuthJSON([
            "OPENAI_API_KEY": "top-level-fallback",
            "tokens": [String: Any](),
        ])
        let token = try TokenReader.parseTokenFromAuthJSON(json)
        #expect(token == "top-level-fallback")
    }

    @Test("Throws noUsableToken when tokens.access_token is empty string")
    func throwsOnEmptyAccessToken() {
        let json = makeAuthJSON([
            "tokens": ["access_token": ""],
        ])
        #expect(throws: TokenReader.ReadError.noUsableToken) {
            try TokenReader.parseTokenFromAuthJSON(json)
        }
    }

    @Test("Throws noUsableToken when OPENAI_API_KEY is empty string")
    func throwsOnEmptyTopLevel() {
        let json = makeAuthJSON([
            "OPENAI_API_KEY": "",
        ])
        #expect(throws: TokenReader.ReadError.noUsableToken) {
            try TokenReader.parseTokenFromAuthJSON(json)
        }
    }

    @Test("Throws authFileMalformed when no recognized token field exists")
    func throwsWhenNoTokenField() {
        let json = makeAuthJSON([
            "last_refresh": "2026-04-26T22:24:00Z",
            "unrelated": "data",
        ])
        #expect(throws: TokenReader.ReadError.authFileMalformed) {
            try TokenReader.parseTokenFromAuthJSON(json)
        }
    }

    @Test("Throws authFileMalformed on non-JSON input")
    func throwsOnNonJSON() {
        #expect(throws: TokenReader.ReadError.authFileMalformed) {
            try TokenReader.parseTokenFromAuthJSON(Data("not json".utf8))
        }
    }

    @Test("Throws authFileMalformed on JSON that isn't a top-level object")
    func throwsOnJSONArray() {
        let arr = try! JSONSerialization.data(withJSONObject: ["a", "b", "c"])
        #expect(throws: TokenReader.ReadError.authFileMalformed) {
            try TokenReader.parseTokenFromAuthJSON(arr)
        }
    }
}
