import Testing
import Foundation
import SwiftData
@testable import MacroLog

/// "Discard" on the review screen must mean discard. Steppers mutate the
/// autosaving SwiftData model in place, so discarding an *edit* of an existing
/// entry has to restore the values review opened with — otherwise the local
/// copy silently diverges from the Health sample (D-08). New pending entries
/// are still deleted outright (REV-04).
@MainActor
struct EditDiscardTests {

    private let originalMacros = Macros(kcal: 600, protein: 40, carbs: 60, fat: 20)

    /// The container is returned alongside the model: the context only weakly
    /// references its container, so callers must keep it alive.
    private func makeEditingModel(status: EntryStatus = .written) throws
        -> (CaptureViewModel, FoodEntry, Date, ModelContainer) {
        let container = try ModelContainer(
            for: FoodEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = CaptureViewModel(context: container.mainContext)
        let capturedAt = Date().addingTimeInterval(-3600)
        let entry = FoodEntry(name: "Lunch",
                              macros: originalMacros,
                              capturedAt: capturedAt,
                              status: status)
        container.mainContext.insert(entry)
        try container.mainContext.save()
        model.openReview(for: entry, editingExisting: true)
        return (model, entry, capturedAt, container)
    }

    @Test func discardingEditedExistingEntryRestoresMacros() throws {
        let (model, entry, _, container) = try makeEditingModel()
        withExtendedLifetime(container) {
            model.adjust(entry, keyPath: \.protein, by: 20) // 40 → 60
            #expect(entry.macros.protein == 60)

            model.discard(entry)

            #expect(entry.macros == originalMacros)
            #expect(model.reviewEntry == nil)
        }
    }

    @Test func discardingEditedExistingEntryRestoresCapturedAt() throws {
        let (model, entry, originalCapturedAt, container) = try makeEditingModel()
        withExtendedLifetime(container) {
            model.adjustTime(entry, byMinutes: -5)
            #expect(entry.capturedAt != originalCapturedAt)

            model.discard(entry)

            #expect(entry.capturedAt == originalCapturedAt)
        }
    }

    @Test func discardingExistingEntryAfterPortionScaleRestoresOriginal() throws {
        let (model, entry, _, container) = try makeEditingModel()
        withExtendedLifetime(container) {
            model.setPortion(entry, factor: 2)
            #expect(entry.macros.kcal == 1200)

            model.discard(entry)

            #expect(entry.macros == originalMacros)
        }
    }

    @Test func discardingNewPendingEntryStillDeletesIt() throws {
        let container = try ModelContainer(
            for: FoodEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = CaptureViewModel(context: container.mainContext)
        try withExtendedLifetime(container) {
            let entry = FoodEntry(name: "New meal",
                                  macros: originalMacros,
                                  capturedAt: Date(),
                                  status: .pendingReview)
            container.mainContext.insert(entry)
            try container.mainContext.save()
            model.pendingEntry = entry
            model.openReview(for: entry, editingExisting: false)

            model.discard(entry)

            let remaining = try container.mainContext.fetch(FetchDescriptor<FoodEntry>())
            #expect(remaining.isEmpty)
            #expect(model.pendingEntry == nil)
        }
    }

    @Test func confirmingEditedEntryKeepsNewValues() async throws {
        let (model, entry, _, container) = try makeEditingModel()
        model.adjust(entry, keyPath: \.protein, by: 20) // 40 → 60

        // The Health write itself may fail in the test environment (no
        // authorization) — either way the edited values must survive;
        // only Discard reverts.
        await model.confirmAsync(entry)

        #expect(entry.macros.protein == 60)
        #expect(model.reviewEntry == nil)
        _ = container // keep the context's container alive through the awaits
    }
}
