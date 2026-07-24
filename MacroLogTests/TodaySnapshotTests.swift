import Testing
import Foundation
@testable import MacroLog

/// Widget snapshot day-rollover rules (WID-02/04): a snapshot from yesterday
/// must render as zeros, never carry stale totals into a new day.
struct TodaySnapshotTests {

    @Test func snapshotFromSameDayIsReturned() {
        let now = Date()
        let snapshot = TodaySnapshot(totals: Macros(kcal: 1200, protein: 90, carbs: 110, fat: 40),
                                     dayStart: Calendar.current.startOfDay(for: now),
                                     entryCount: 3)
        TodaySnapshotStore.write(snapshot)
        let read = TodaySnapshotStore.read(now: now)
        #expect(read == snapshot)
    }

    @Test func staleSnapshotRendersAsZerosNextDay() {
        let now = Date()
        let snapshot = TodaySnapshot(totals: Macros(kcal: 1200, protein: 90, carbs: 110, fat: 40),
                                     dayStart: Calendar.current.startOfDay(for: now),
                                     entryCount: 3)
        TodaySnapshotStore.write(snapshot)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let read = TodaySnapshotStore.read(now: tomorrow)
        #expect(read.totals == .zero)
        #expect(read.entryCount == 0)
        #expect(read.dayStart == Calendar.current.startOfDay(for: tomorrow))
    }

    @Test func macrosAddition() {
        let sum = Macros(kcal: 100, protein: 10, carbs: 20, fat: 5)
            + Macros(kcal: 250, protein: 15, carbs: 30, fat: 12)
        #expect(sum == Macros(kcal: 350, protein: 25, carbs: 50, fat: 17))
    }
}
