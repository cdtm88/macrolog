import Foundation
import SwiftData
import WidgetKit

/// Query, history-bound, and widget-publishing logic over the SwiftData store.
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

    // MARK: - History bounds

    /// Start of the earliest day holding a confirmed entry — the back limit for
    /// the day-paged list. Entries are retained indefinitely (day history,
    /// 2026-08-05, superseding ENT-04's day-boundary purge); photos are never
    /// persisted, so the store stays tiny regardless.
    func earliestConfirmedDayStart(now: Date = Date()) -> Date {
        let pending = EntryStatus.pendingReview.rawValue
        var descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.statusRaw != pending },
            sortBy: [SortDescriptor(\.capturedAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        let today = calendar.startOfDay(for: now)
        guard let earliest = (try? context.fetch(descriptor))?.first?.capturedAt else {
            return today
        }
        return min(calendar.startOfDay(for: earliest), today)
    }

    // MARK: - Export

    /// Every confirmed entry, oldest first — the full-export feed. A full
    /// fetch is fine: the store stays tiny (photos are never persisted).
    func allConfirmedEntries() -> [FoodEntry] {
        let pending = EntryStatus.pendingReview.rawValue
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.statusRaw != pending },
            sortBy: [SortDescriptor(\.capturedAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Every confirmed day's totals, oldest first — the lite-export feed.
    func allConfirmedDailyTotals() -> [DailyTotal] {
        let entries = allConfirmedEntries()
        var result: [DailyTotal] = []
        for entry in entries {
            let dayStart = calendar.startOfDay(for: entry.capturedAt)
            if let last = result.last, last.dayStart == dayStart {
                result[result.count - 1] = DailyTotal(dayStart: dayStart,
                                                      totals: last.totals + entry.macros,
                                                      entryCount: last.entryCount + 1)
            } else {
                result.append(DailyTotal(dayStart: dayStart,
                                         totals: entry.macros,
                                         entryCount: 1))
            }
        }
        return result
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
