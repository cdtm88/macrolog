import Testing
import Foundation
import SwiftData
@testable import MacroLog

/// The review screen's portion scaling — all four macros scale together,
/// rounded to whole numbers, never below zero.
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
        return (model, entry, container)
    }

    @Test func halvingScalesAllFourAndRounds() throws {
        let (model, entry, container) = try makeModel()
        withExtendedLifetime(container) {
            model.scale(entry, by: 0.5)
            #expect(entry.macros == Macros(kcal: 425, protein: 20, carbs: 47, fat: 17))
        }
    }

    @Test func doublingScalesAllFour() throws {
        let (model, entry, container) = try makeModel()
        withExtendedLifetime(container) {
            model.scale(entry, by: 2)
            #expect(entry.macros == Macros(kcal: 1700, protein: 80, carbs: 188, fat: 66))
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
