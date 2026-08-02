import Testing
import Foundation
@testable import MacroLog

/// The weight bridge's day-collapse, deletion propagation, and queue bounding
/// (bridge spec HB-02/03/10).
struct WeightLedgerTests {

    private func moment(day: Int, hour: Int) -> Date {
        var parts = DateComponents()
        (parts.year, parts.month, parts.day, parts.hour) = (2026, 8, day, hour)
        return Calendar.current.date(from: parts)!
    }

    @Test func threeReadingsOneDayCollapseToEarliest() {
        var ledger = WeightLedger()
        let changed = ledger.apply(added: [
            (UUID(), moment(day: 1, hour: 9), 82.4),
            (UUID(), moment(day: 1, hour: 7), 82.1),
            (UUID(), moment(day: 1, hour: 21), 83.0)
        ], deleted: [])

        #expect(changed == ["2026-08-01"])
        #expect(ledger.value(forDay: "2026-08-01") == 82.1)
    }

    @Test func deletingEarliestRecomputesTheDay() {
        var ledger = WeightLedger()
        let earliest = UUID()
        _ = ledger.apply(added: [
            (earliest, moment(day: 1, hour: 7), 82.1),
            (UUID(), moment(day: 1, hour: 9), 82.4)
        ], deleted: [])

        let changed = ledger.apply(added: [], deleted: [earliest])
        #expect(changed == ["2026-08-01"])
        #expect(ledger.value(forDay: "2026-08-01") == 82.4)
    }

    @Test func deletingEverySampleOfADayYieldsNil() {
        var ledger = WeightLedger()
        let only = UUID()
        _ = ledger.apply(added: [(only, moment(day: 2, hour: 8), 81.9)], deleted: [])
        _ = ledger.apply(added: [], deleted: [only])
        // Propagates upstream as a cleared value (HB-02).
        #expect(ledger.value(forDay: "2026-08-02") == nil)
    }

    @Test func unknownDeletionChangesNothing() {
        var ledger = WeightLedger()
        let changed = ledger.apply(added: [], deleted: [UUID()])
        #expect(changed.isEmpty)
    }

    @Test func pendingMergeKeepsOneWritePerDateInPlace() {
        var queue = [WeightUpload(date: "2026-08-01", weightKg: 82.1),
                     WeightUpload(date: "2026-08-02", weightKg: 82.0)]
        queue = WeightUpload.merge(queue, with: WeightUpload(date: "2026-08-01", weightKg: 81.8))

        #expect(queue.count == 2)
        // Oldest-first drain order preserved; the value is the newest state.
        #expect(queue[0] == WeightUpload(date: "2026-08-01", weightKg: 81.8))
    }

    @Test func boundEvictsOldestAndReportsThem() {
        let queue = (1...5).map { WeightUpload(date: "2026-08-0\($0)", weightKg: 80 + Double($0)) }
        let (kept, evicted) = WeightUpload.bounded(queue, limit: 3)

        #expect(kept.map(\.date) == ["2026-08-03", "2026-08-04", "2026-08-05"])
        #expect(evicted.map(\.date) == ["2026-08-01", "2026-08-02"])
    }
}
