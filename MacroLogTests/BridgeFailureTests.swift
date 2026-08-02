import Testing
import Foundation
@testable import MacroLog

/// Serves a scripted sequence of HTTP statuses to any request on a session
/// configured with this protocol; once the script is exhausted every request
/// gets 200. Statuses are consumed in request order, which is deterministic
/// because both bridge drains are serial loops.
final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var scripted: [Int] = []
    nonisolated(unsafe) private(set) static var requestCount = 0

    static func reset(statuses: [Int]) {
        lock.lock(); defer { lock.unlock() }
        scripted = statuses
        requestCount = 0
    }

    private static func nextStatus() -> Int {
        lock.lock(); defer { lock.unlock() }
        requestCount += 1
        return scripted.isEmpty ? 200 : scripted.removeFirst()
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: Self.nextStatus(),
                                       httpVersion: nil,
                                       headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A queue must never be wedged by a permanently failing item (rotated
/// secret, malformed payload): 4xx rejections are logged and dropped so the
/// rest of the queue drains, while transport-class failures (5xx, 408, 429)
/// keep the current stop-and-retry-later behaviour. Serialised because the
/// stub's script is process-global.
@Suite(.serialized)
struct BridgeFailureTests {

    private func tempFile(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bridge-tests-\(UUID().uuidString)-\(name)")
    }

    private func makeRelay(queueFile: URL, dropLog: URL) -> CoachRelay {
        CoachRelay(config: .init(baseURL: URL(string: "https://coach.invalid")!, secret: "s"),
                   session: StubURLProtocol.makeSession(),
                   queueFile: queueFile,
                   dropLog: dropLog)
    }

    private func seedQueue(_ file: URL, count: Int) throws -> [CoachMealItem] {
        let items = (0..<count).map { i in
            CoachMealItem(mealID: UUID(), loggedAt: Date().addingTimeInterval(Double(i)),
                          kcal: 500, protein: 30, carbs: 50, fat: 20, deleted: false)
        }
        try JSONEncoder().encode(items).write(to: file)
        return items
    }

    // MARK: - Coach relay

    @Test func permanent400DropsHeadAndDrainsTheRest() async throws {
        let queueFile = tempFile("queue.json"), dropLog = tempFile("drops.log")
        let items = try seedQueue(queueFile, count: 3)
        StubURLProtocol.reset(statuses: [400])

        let relay = makeRelay(queueFile: queueFile, dropLog: dropLog)
        await relay.drain()

        // Head dropped, the two behind it drained (three requests total).
        let remaining = await relay.queuedItems()
        #expect(remaining.isEmpty)
        #expect(StubURLProtocol.requestCount == 3)

        // The dropped item was logged with its payload before being discarded.
        let log = try #require(try? String(contentsOf: dropLog, encoding: .utf8))
        #expect(log.contains("HTTP 400"))
        #expect(log.contains(items[0].mealID.uuidString.lowercased()))
        #expect(!log.contains(items[1].mealID.uuidString.lowercased()))
    }

    @Test func retryable500RetainsHeadAndPreservesOrder() async throws {
        let queueFile = tempFile("queue.json"), dropLog = tempFile("drops.log")
        let items = try seedQueue(queueFile, count: 2)
        StubURLProtocol.reset(statuses: [500])

        let relay = makeRelay(queueFile: queueFile, dropLog: dropLog)
        await relay.drain()

        // Stopped at the head; nothing dropped, nothing reordered, one request.
        let remaining = await relay.queuedItems()
        #expect(remaining.map(\.mealID) == items.map(\.mealID))
        #expect(StubURLProtocol.requestCount == 1)
        #expect(!FileManager.default.fileExists(atPath: dropLog.path))
    }

    @Test func statuses429And408AreRetryableNotDropped() async throws {
        for status in [429, 408] {
            let queueFile = tempFile("queue.json"), dropLog = tempFile("drops.log")
            let items = try seedQueue(queueFile, count: 1)
            StubURLProtocol.reset(statuses: [status])

            let relay = makeRelay(queueFile: queueFile, dropLog: dropLog)
            await relay.drain()

            let remaining = await relay.queuedItems()
            #expect(remaining.map(\.mealID) == items.map(\.mealID),
                    "HTTP \(status) must retain the item for retry")
            #expect(!FileManager.default.fileExists(atPath: dropLog.path))
        }
    }

    // MARK: - Weight bridge

    @Test func weightQueuePermanent422DropsHeadAndDrainsTheRest() async throws {
        let stateFile = tempFile("state.json"), evictionLog = tempFile("evictions.log")
        let bridge = WeightBridge(config: .init(athleteID: "i0", apiKey: "k"),
                                  session: StubURLProtocol.makeSession(),
                                  stateFile: stateFile,
                                  evictionLog: evictionLog)
        await bridge.seedPending([WeightUpload(date: "2026-08-01", weightKg: 81.5),
                                  WeightUpload(date: "2026-08-02", weightKg: 81.2)])
        StubURLProtocol.reset(statuses: [422])

        await bridge.drain()

        let pending = await bridge.pendingUploads()
        #expect(pending.isEmpty)
        #expect(StubURLProtocol.requestCount == 2)
        let log = try #require(try? String(contentsOf: evictionLog, encoding: .utf8))
        #expect(log.contains("2026-08-01 81.5 dropped HTTP 422"))
        #expect(!log.contains("2026-08-02"))
    }

    @Test func weightQueueRetryable500RetainsHeadAndOrder() async throws {
        let stateFile = tempFile("state.json"), evictionLog = tempFile("evictions.log")
        let bridge = WeightBridge(config: .init(athleteID: "i0", apiKey: "k"),
                                  session: StubURLProtocol.makeSession(),
                                  stateFile: stateFile,
                                  evictionLog: evictionLog)
        let uploads = [WeightUpload(date: "2026-08-01", weightKg: 81.5),
                       WeightUpload(date: "2026-08-02", weightKg: 81.2)]
        await bridge.seedPending(uploads)
        StubURLProtocol.reset(statuses: [500])

        await bridge.drain()

        let pending = await bridge.pendingUploads()
        #expect(pending == uploads)
        #expect(StubURLProtocol.requestCount == 1)
        #expect(!FileManager.default.fileExists(atPath: evictionLog.path))
    }
}
