import Foundation
import Testing
@testable import CodexMeter

@MainActor
@Suite("UsageStore")
struct UsageStoreTests {

    @Test("Initial state is empty")
    func initialState() {
        let store = UsageStore()
        #expect(store.snapshot == nil)
        #expect(store.lastRefresh == nil)
        #expect(store.lastError == nil)
    }

    @Test("updateSnapshot sets snapshot + timestamp and clears error")
    func updateClearsError() {
        let store = UsageStore()
        store.recordError(.api(.unauthorized))
        #expect(store.lastError != nil)

        let snapshot = UsageSnapshot(
            session: UsageWindow(utilization: 14.0, resetsAt: nil),
            weekly: UsageWindow(utilization: 65.0, resetsAt: nil)
        )
        let date = Date(timeIntervalSince1970: 1_777_577_933)
        store.updateSnapshot(snapshot, at: date)

        #expect(store.snapshot == snapshot)
        #expect(store.lastRefresh == date)
        #expect(store.lastError == nil)
    }

    @Test("recordError preserves the last good snapshot")
    func errorPreservesSnapshot() {
        let store = UsageStore()
        let snapshot = UsageSnapshot(
            session: UsageWindow(utilization: 14.0, resetsAt: nil),
            weekly: nil
        )
        store.updateSnapshot(snapshot)

        store.recordError(.api(.unauthorized))

        #expect(store.snapshot == snapshot, "snapshot should survive a recorded error")
        #expect(store.lastError != nil)
    }

    @Test("clear wipes everything")
    func clearWipes() {
        let store = UsageStore()
        store.updateSnapshot(UsageSnapshot(session: nil, weekly: nil))
        store.recordError(.api(.unauthorized))
        store.clear()
        #expect(store.snapshot == nil)
        #expect(store.lastRefresh == nil)
        #expect(store.lastError == nil)
    }

    @Test("Projection for an unpublished window is nil")
    func projectionForMissingWindow() {
        let store = UsageStore()
        store.updateSnapshot(UsageSnapshot(
            session: nil,
            weekly: UsageWindow(utilization: 50, resetsAt: Date().addingTimeInterval(3.5 * 86400), duration: 604800)
        ))
        #expect(store.projection(for: .session) == nil)
        #expect(store.projection(for: .weekly) != nil)
    }

    @Test("Projection uses the length the API reported, not the fallback")
    func projectionUsesReportedDuration() {
        let now = Date(timeIntervalSince1970: 1_777_577_933)
        let store = UsageStore()
        // A 2h window, half elapsed, half used → on pace. Scoring it
        // against the 5h fallback instead would read as 2.5× over pace.
        store.updateSnapshot(UsageSnapshot(
            session: UsageWindow(utilization: 50,
                                 resetsAt: now.addingTimeInterval(3600),
                                 duration: 2 * 3600),
            weekly: nil
        ))
        guard let p = store.projection(for: .session, now: now) else {
            Issue.record("expected non-nil projection")
            return
        }
        #expect(abs(p.paceRatio - 1.0) < 0.001)
    }

    @Test("Projection falls back to the fixed length when the API omits it")
    func projectionUsesFallbackDuration() {
        let now = Date(timeIntervalSince1970: 1_777_577_933)
        let store = UsageStore()
        // No reported duration → 5h fallback. 2.5h left of a 5h window at
        // 50% used is exactly on pace.
        store.updateSnapshot(UsageSnapshot(
            session: UsageWindow(utilization: 50, resetsAt: now.addingTimeInterval(2.5 * 3600)),
            weekly: nil
        ))
        guard let p = store.projection(for: .session, now: now) else {
            Issue.record("expected non-nil projection")
            return
        }
        #expect(abs(p.paceRatio - 1.0) < 0.001)
    }
}
