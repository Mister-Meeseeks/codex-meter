import Foundation
import Testing
@testable import CodexMeter

@Suite("UsagePoller")
struct UsagePollerTests {

    private struct FakeProvider: UsageProvider {
        let fetch: @Sendable () async throws -> UsageSnapshot
        func fetchUsage() async throws -> UsageSnapshot { try await fetch() }
    }

    private static let okProvider = FakeProvider(fetch: {
        UsageSnapshot(session: nil, weekly: nil)
    })
    private static let failingProvider = FakeProvider(fetch: { throw FakeError.boom })

    @Test("Base interval used when no failures")
    func baseIntervalNoFailures() async {
        let store = await UsageStore()
        let poller = UsagePoller(
            store: store,
            provider: Self.okProvider,
            interval: 60,
            backoffCeiling: 300
        )
        let interval = await poller.nextInterval()
        #expect(interval == 60)
    }

    @Test("Shipping default is the 60s cadence AGENTS.md mandates")
    func defaultIntervalIs60() async {
        // The endpoint rate-limits, so there is deliberately no faster
        // cadence to select — not while the popover is open, not anywhere.
        let store = await UsageStore()
        let poller = UsagePoller(store: store, provider: Self.okProvider)
        let interval = await poller.nextInterval()
        #expect(interval == 60)
    }

    @Test("Backoff doubles on each failure, capped at ceiling")
    func backoffDoublesAndCaps() async {
        let store = await UsageStore()
        let poller = UsagePoller(
            store: store,
            provider: Self.failingProvider,
            interval: 60,
            backoffCeiling: 300
        )

        // 1 failure: 60 * 2^0 = 60
        await poller.refreshNow()
        var iv = await poller.nextInterval()
        #expect(iv == 60)

        // 2 failures: 60 * 2^1 = 120
        await poller.refreshNow()
        iv = await poller.nextInterval()
        #expect(iv == 120)

        // 3 failures: 60 * 2^2 = 240
        await poller.refreshNow()
        iv = await poller.nextInterval()
        #expect(iv == 240)

        // 4 failures: 60 * 2^3 = 480 → capped at 300
        await poller.refreshNow()
        iv = await poller.nextInterval()
        #expect(iv == 300)

        // 10 failures: still capped
        for _ in 0..<6 { await poller.refreshNow() }
        iv = await poller.nextInterval()
        #expect(iv == 300)
    }

    @Test("Recorded error survives in store after failed pollOnce")
    func failurePropagatesToStore() async {
        let store = await UsageStore()
        let poller = UsagePoller(
            store: store,
            provider: Self.failingProvider,
            interval: 60
        )
        await poller.refreshNow()
        let hasError = await MainActor.run { store.lastError != nil }
        #expect(hasError)
    }
}

private enum FakeError: Error {
    case boom
}
