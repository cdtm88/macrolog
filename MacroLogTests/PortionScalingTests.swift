import Testing
import Foundation
import SwiftData
@testable import MacroLog

/// The review screen's portion multiplier — absolute against the estimate the
/// review opened with, never compounding: 1× always restores the original.
@MainActor
struct PortionScalingTests {

    /// The container is returned alongside the model: the context only weakly
    /// references its container, so callers must keep it alive or the first
    /// insert traps inside SwiftData.
    private func makeModel() throws -> (CaptureViewModel, FoodEntry, ModelContainer) {
        let container = try ModelContainer(
            for: FoodEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = CaptureViewModel(context: container.mainContext)
        let entry = FoodEntry(name: "Curry",
                              macros: Macros(kcal: 850, protein: 40, carbs: 94, fat: 33),
                              capturedAt: Date())
        container.mainContext.insert(entry)
        // Opening review freezes the portion baseline at the AI's numbers.
        model.openReview(for: entry, editingExisting: false)
        return (model, entry, container)
    }

    @Test func halvingScalesAllFourAndRounds() throws {
        let (model, entry, container) = try makeModel()
        withExtendedLifetime(container) {
            model.setPortion(entry, factor: 0.5)
            #expect(entry.macros == Macros(kcal: 425, protein: 20, carbs: 47, fat: 17))
        }
    }

    @Test func factorsDoNotCompound() throws {
        let (model, entry, container) = try makeModel()
        withExtendedLifetime(container) {
            model.setPortion(entry, factor: 0.5)
            model.setPortion(entry, factor: 2)
            // 2× of the ORIGINAL, not 2× of the halved values.
            #expect(entry.macros == Macros(kcal: 1700, protein: 80, carbs: 188, fat: 66))
        }
    }

    @Test func factorOneRestoresOriginalEstimate() throws {
        let (model, entry, container) = try makeModel()
        withExtendedLifetime(container) {
            model.setPortion(entry, factor: 0.5)
            model.setPortion(entry, factor: 1)
            #expect(entry.macros == Macros(kcal: 850, protein: 40, carbs: 94, fat: 33))
            #expect(model.portionFactor == 1)
        }
    }

    @Test func timeStepSnapsToFiveMinuteGrid() throws {
        let (model, entry, container) = try makeModel()
        withExtendedLifetime(container) {
            // 10:13:42 → down snaps to 10:10:00, then steps to 10:05:00.
            var parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            (parts.hour, parts.minute, parts.second) = (10, 13, 42)
            entry.capturedAt = Calendar.current.date(from: parts)!

            model.adjustTime(entry, byMinutes: -5)
            var hm = Calendar.current.dateComponents([.hour, .minute, .second], from: entry.capturedAt)
            #expect((hm.hour, hm.minute, hm.second) == (10, 10, 0))

            model.adjustTime(entry, byMinutes: -5)
            hm = Calendar.current.dateComponents([.hour, .minute, .second], from: entry.capturedAt)
            #expect((hm.hour, hm.minute) == (10, 5))

            model.adjustTime(entry, byMinutes: 5)
            model.adjustTime(entry, byMinutes: 5)
            hm = Calendar.current.dateComponents([.hour, .minute], from: entry.capturedAt)
            #expect((hm.hour, hm.minute) == (10, 15))
        }
    }

    @Test func stepperAdjustmentClampsAtZero() throws {
        let (model, entry, container) = try makeModel()
        withExtendedLifetime(container) {
            entry.macros = Macros(kcal: 5, protein: 0, carbs: 0, fat: 0)
            model.adjust(entry, keyPath: \.kcal, by: -10)
            model.adjust(entry, keyPath: \.protein, by: -1)
            #expect(entry.macros.kcal == 0)
            #expect(entry.macros.protein == 0)
        }
    }
}
