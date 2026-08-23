import Testing
import Foundation
@testable import MacroLog

/// The daily-totals → intervals.icu wellness bridge: payload shape (the four
/// live-verified fields), per-date queue collapse, the write-nothing rule for
/// a day with no confirmed entries, and the shared drop-permanent /
/// retry-transient drain behaviour. Serialised because the stub's script is
/// process-global.
@Suite(.serialized)
struct NutritionBridgeTests {

    private func tempFile(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("nutrition-tests-\(UUID().uuidString)-\(name)")
    }

    private func makeBridge(queueFile: URL, dropLog: URL) -> NutritionBridge {
        NutritionBridge(config: .init(athleteID: "i0", apiKey: "k"),
                        session: StubURLProtocol.makeSession(),
                        queueFile: queueFile,
                        dropLog: dropLog)
    }

    private let totals = Macros(kcal: 2104.4, protein: 149.6, carbs: 210.2, fat: 70.1,
                                fiber: 31, sodium: 2300)

    // MARK: - Payload

    @Test func payloadCarriesTheFourWellnessFieldsRounded() {
        let payload = NutritionUpload(date: "2026-08-21", totals: totals).payload()
        #expect(payload["kcalConsumed"] as? Int == 2104)
        #expect(payload["protein"] as? Int == 150)
        #expect(payload["carbohydrates"] as? Int == 210)
        #expect(payload["fatTotal"] as? Int == 70)
        // No wellness field exists for fibre or sodium — they must not leak in.
        #expect(payload.count == 4)
    }

    // MARK: - Queue rules

    @Test func mergeCollapsesPerDateNewestWinsKeepingPosition() {
        let updated = Macros(kcal: 1800, protein: 120, carbs: 180, fat: 60,
                             fiber: 25, sodium: 2000)
        var queue: [NutritionUpload] = []
        queue = queue.merging(.init(date: "2026-08-20", totals: totals))
        queue = queue.merging(.init(date: "2026-08-21", totals: totals))
        queue = queue.merging(.init(date: "2026-08-20", totals: updated))

        #expect(queue.map(\.date) == ["2026-08-20", "2026-08-21"])
        #expect(queue[0].totals == updated)
    }

    /// A day whose confirmed entries have all been deleted writes nothing:
    /// recordDay(nil) never queues, and drops any write already queued for
    /// that day so a stale value can't drain later.
    @Test func emptyDayWritesNothingAndDropsItsQueuedWrite() async {
        let queueFile = tempFile("queue.json"), dropLog = tempFile("drops.log")
        // Hold everything queued so the enqueue-triggered drain can't empty it.
        StubURLProtocol.reset(statuses: [500, 500, 500])
        let bridge = makeBridge(queueFile: queueFile, dropLog: dropLog)
        await bridge.seedPending([NutritionUpload(date: "2026-08-20", totals: totals),
                                  NutritionUpload(date: "2026-08-21", totals: totals)])

        await bridge.recordDay(date: "2026-08-20", totals: nil)
        #expect(await bridge.queuedUploads().map(\.date) == ["2026-08-21"])

        // A day never queued stays never queued.
        await bridge.recordDay(date: "2026-08-19", totals: nil)
        #expect(await bridge.queuedUploads().map(\.date) == ["2026-08-21"])
    }

    @Test func boundedEvictsOldestFirst() {
        let queue = (1...5).map { NutritionUpload(date: "2026-08-0\($0)", totals: totals) }
        let (kept, evicted) = queue.bounded(limit: 3)
        #expect(kept.map(\.date) == ["2026-08-03", "2026-08-04", "2026-08-05"])
        #expect(evicted.map(\.date) == ["2026-08-01", "2026-08-02"])
    }

    // MARK: - Drain

    @Test func permanent422DropsHeadAndDrainsTheRest() async throws {
        let queueFile = tempFile("queue.json"), dropLog = tempFile("drops.log")
        let uploads = [NutritionUpload(date: "2026-08-20", totals: totals),
                       NutritionUpload(date: "2026-08-21", totals: totals)]
        let bridge = makeBridge(queueFile: queueFile, dropLog: dropLog)
        await bridge.seedPending(uploads)
        StubURLProtocol.reset(statuses: [422])

        await bridge.drain()

        let remaining = await bridge.queuedUploads()
        #expect(remaining.isEmpty)
        #expect(StubURLProtocol.requestCount == 2)
        let log = try #require(try? String(contentsOf: dropLog, encoding: .utf8))
        #expect(log.contains("2026-08-20 2104 kcal dropped HTTP 422"))
        #expect(!log.contains("2026-08-21"))
    }

    @Test func retryable500RetainsHeadAndOrder() async throws {
        let queueFile = tempFile("queue.json"), dropLog = tempFile("drops.log")
        let uploads = [NutritionUpload(date: "2026-08-20", totals: totals),
                       NutritionUpload(date: "2026-08-21", totals: totals)]
        let bridge = makeBridge(queueFile: queueFile, dropLog: dropLog)
        await bridge.seedPending(uploads)
        StubURLProtocol.reset(statuses: [500])

        await bridge.drain()

        let remaining = await bridge.queuedUploads()
        #expect(remaining == uploads)
        #expect(StubURLProtocol.requestCount == 1)
        #expect(!FileManager.default.fileExists(atPath: dropLog.path))
    }

    // MARK: - Backfill

    @Test func backfillEnqueuesAllDaysOnceThenNeverAgain() async throws {
        let queueFile = tempFile("queue.json"), dropLog = tempFile("drops.log")
        // Hold everything queued so the enqueue-triggered drain can't empty it.
        StubURLProtocol.reset(statuses: [500, 500, 500])

        let bridge = makeBridge(queueFile: queueFile, dropLog: dropLog)
        #expect(await bridge.needsBackfill())

        let days = [NutritionUpload(date: "2026-08-19", totals: totals),
                    NutritionUpload(date: "2026-08-20", totals: totals)]
        await bridge.backfill(days)
        #expect(await bridge.queuedUploads() == days)
        #expect(await !bridge.needsBackfill())

        // A later launch's backfill is a no-op, whatever it carries.
        await bridge.backfill([NutritionUpload(date: "2026-08-21", totals: totals)])
        #expect(await bridge.queuedUploads() == days)

        // The marker survives a relaunch.
        let reloaded = makeBridge(queueFile: queueFile, dropLog: dropLog)
        #expect(await !reloaded.needsBackfill())
    }

    @Test func backfillNeverRunsUnconfigured() async {
        let bridge = NutritionBridge(config: nil,
                                     session: StubURLProtocol.makeSession(),
                                     queueFile: tempFile("queue.json"),
                                     dropLog: tempFile("drops.log"))
        // False rather than true: an inert bridge must not invite the caller
        // to fetch history it will never send.
        #expect(await !bridge.needsBackfill())
        await bridge.backfill([NutritionUpload(date: "2026-08-21", totals: totals)])
        #expect(await bridge.queuedUploads().isEmpty)
    }

    @Test func inertWithoutConfig() async {
        let queueFile = tempFile("queue.json"), dropLog = tempFile("drops.log")
        let bridge = NutritionBridge(config: nil,
                                     session: StubURLProtocol.makeSession(),
                                     queueFile: queueFile,
                                     dropLog: dropLog)
        await bridge.recordDay(date: "2026-08-21", totals: totals)
        let queued = await bridge.queuedUploads()
        #expect(queued.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: queueFile.path))
    }
}
