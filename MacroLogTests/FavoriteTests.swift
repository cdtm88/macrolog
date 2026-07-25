import Testing
import Foundation
import SwiftData
@testable import MacroLog

/// Logging a favourite skips estimation and goes straight to review with the
/// preset values, as a normal pending entry (REV-01 still applies).
@MainActor
struct FavoriteTests {

    @Test func submitFavoriteOpensReviewWithPresetValues() throws {
        let container = try ModelContainer(
            for: FoodEntry.self, Favorite.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = CaptureViewModel(context: container.mainContext)

        withExtendedLifetime(container) {
            let macros = Macros(kcal: 410, protein: 32, carbs: 40, fat: 12)
            model.submitFavorite(name: "Usual breakfast", macros: macros)

            #expect(model.reviewEntry?.name == "Usual breakfast")
            #expect(model.reviewEntry?.macros == macros)
            #expect(model.reviewEntry?.status == .pendingReview)
            #expect(model.pendingEntry?.id == model.reviewEntry?.id)
            // Baseline frozen at the preset, so the portion chips work from it.
            #expect(model.portionFactor == 1)
        }
    }

    @Test func favoriteMacrosRoundTrip() throws {
        let macros = Macros(kcal: 320, protein: 30, carbs: 38, fat: 6)
        let favorite = Favorite(name: "Protein shake", macros: macros, sortOrder: 0)
        #expect(favorite.macros == macros)
        favorite.macros = Macros(kcal: 100, protein: 10, carbs: 5, fat: 2)
        #expect(favorite.kcal == 100)
        #expect(favorite.fat == 2)
    }
}
