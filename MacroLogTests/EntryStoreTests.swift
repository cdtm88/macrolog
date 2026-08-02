import Testing
import Foundation
import SwiftData
@testable import MacroLog

/// Day-boundary and retention rules over the SwiftData store (ENT-01/04,
/// CAP-05): purge only old *written* entries, never anything unwritten.
@MainActor
struct EntryStoreTests {

    /// Returns the container alongside the store: the context only weakly
    /// references its container, so callers must keep it alive or the first
    /// insert traps inside SwiftData.
    private func makeStore() throws -> (EntryStore, ModelContainer) {
        let container = try ModelContainer(
            for: FoodEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (EntryStore(context: container.mainContext), container)
    }

    private func insert(_ context: ModelContext,
                        name: String,
                        daysAgo: Int,
                        status: EntryStatus,
                        now: Date) -> FoodEntry {
        let capturedAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        let entry = FoodEntry(name: name,
                              macros: Macros(kcal: 100, protein: 10, carbs: 10, fat: 5),
                              capturedAt: capturedAt,
                              status: status)
        context.insert(entry)
        return entry
    }

    @Test func purgeDeletesOnlyOldWrittenEntries() throws {
        let (store, container) = try makeStore()
        let context = container.mainContext
        let now = Date()
        _ = insert(context, name: "old written", daysAgo: 1, status: .written, now: now)
        _ = insert(context, name: "old unwritten", daysAgo: 1, status: .unwritten, now: now)
        _ = insert(context, name: "old pending", daysAgo: 2, status: .pendingReview, now: now)
        _ = insert(context, name: "today written", daysAgo: 0, status: .written, now: now)
        try context.save()

        store.purgeOldWrittenEntries(now: now)

        let remaining = try context.fetch(FetchDescriptor<FoodEntry>()).map(\.name).sorted()
        #expect(remaining == ["old pending", "old unwritten", "today written"])
    }

    @Test func todaysConfirmedEntriesExcludePendingAndYesterday() throws {
        let (store, container) = try makeStore()
        let context = container.mainContext
        let now = Date()
        _ = insert(context, name: "today written", daysAgo: 0, status: .written, now: now)
        _ = insert(context, name: "today unwritten", daysAgo: 0, status: .unwritten, now: now)
        _ = insert(context, name: "today pending", daysAgo: 0, status: .pendingReview, now: now)
        _ = insert(context, name: "yesterday written", daysAgo: 1, status: .written, now: now)
        try context.save()

        let names = store.todaysConfirmedEntries(now: now).map(\.name).sorted()
        #expect(names == ["today unwritten", "today written"])
    }

    @Test func todaysConfirmedEntriesSortedNewestFirst() throws {
        let (store, container) = try makeStore()
        let context = container.mainContext
        let now = Date()
        let earlier = FoodEntry(name: "breakfast",
                                macros: .zero,
                                capturedAt: now.addingTimeInterval(-3600),
                                status: .written)
        let later = FoodEntry(name: "lunch",
                              macros: .zero,
                              capturedAt: now,
                              status: .written)
        context.insert(earlier)
        context.insert(later)
        try context.save()

        #expect(store.todaysConfirmedEntries(now: now).map(\.name) == ["lunch", "breakfast"])
    }

    @Test func pendingReviewEntryReturnsNewestPending() throws {
        let (store, container) = try makeStore()
        let context = container.mainContext
        let now = Date()
        _ = insert(context, name: "written", daysAgo: 0, status: .written, now: now)
        let older = FoodEntry(name: "older pending", macros: .zero,
                              capturedAt: now.addingTimeInterval(-600), status: .pendingReview)
        let newer = FoodEntry(name: "newer pending", macros: .zero,
                              capturedAt: now, status: .pendingReview)
        context.insert(older)
        context.insert(newer)
        try context.save()

        #expect(store.pendingReviewEntry()?.name == "newer pending")
    }

    @Test func pendingReviewEntryNilWhenNothingPending() throws {
        let (store, container) = try makeStore()
        let context = container.mainContext
        _ = insert(context, name: "written", daysAgo: 0, status: .written, now: Date())
        try context.save()
        #expect(store.pendingReviewEntry() == nil)
    }

    /// A corrupt store file must fail container creation (the app degrades to
    /// an explicit error state rather than crash-looping), and resetting must
    /// allow a fresh container at the same URL.
    @Test func corruptStoreThrowsAndResetRecovers() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("default.store")
        try Data("definitely not a sqlite database".utf8).write(to: url)

        #expect(throws: (any Error).self) {
            _ = try StoreBootstrap.makeContainer(at: url)
        }

        StoreBootstrap.reset(at: url)
        let container = try StoreBootstrap.makeContainer(at: url)
        container.mainContext.insert(FoodEntry(name: "recovered",
                                               macros: .zero,
                                               capturedAt: Date(),
                                               status: .pendingReview))
        try container.mainContext.save()
    }
}
