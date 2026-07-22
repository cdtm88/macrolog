import Foundation
import SwiftData
import WidgetKit

/// Query, retention, and widget-publishing logic over the SwiftData store.
/// Mutations of individual entries happen in the view model against the same
/// `ModelContext`; this type centralises the reads and the day-boundary rules.
@MainActor
struct EntryStore {
    let context: ModelContext
    var calendar: Calendar = .current

    // MARK: - Queries

    /// The single entry currently awaiting review, if any. Used to recover a
    /// pending estimate on next launch (CAP-05) and to surface it from capture
    /// without navigating away (REV-03).
    func pendingReviewEntry() -> FoodEntry? {
        let pending = EntryStatus.pendingReview.rawValue
        var descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.statusRaw == pending },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Confirmed entries (written or unwritten) captured today, newest first
    /// (ENT-01).
    func todaysConfirmedEntries(now: Date = Date()) -> [FoodEntry] {
        let dayStart = calendar.startOfDay(for: now)
        let pending = EntryStatus.pendingReview.rawValue
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.statusRaw != pending && $0.capturedAt >= dayStart },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Retention

    /// Removes entries older than today that have been successfully written to
    /// Health; the app keeps no history beyond today (ENT-04). Pending or
    /// unwritten entries survive regardless of age so nothing captured is ever
    /// lost.
    func purgeOldWrittenEntries(now: Date = Date()) {
        let dayStart = calendar.startOfDay(for: now)
        let written = EntryStatus.written.rawValue
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.statusRaw == written && $0.capturedAt < dayStart }
        )
        guard let stale = try? context.fetch(descriptor) else { return }
        for entry in stale { context.delete(entry) }
        try? context.save()
    }

    // MARK: - Widget snapshot

    /// Recomputes today's totals and publishes them to the App Group, then asks
    /// WidgetKit to reload so the widget reflects the change within seconds
    /// (WID-01/02/04).
    func refreshTodaySnapshot(now: Date = Date()) {
        let entries = todaysConfirmedEntries(now: now)
        let totals = entries.reduce(Macros.zero) { $0 + $1.macros }
        let snapshot = TodaySnapshot(totals: totals,
                                     dayStart: calendar.startOfDay(for: now),
                                     entryCount: entries.count)
        TodaySnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
