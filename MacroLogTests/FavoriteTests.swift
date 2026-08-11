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

    /// Swiping a logged meal into favourites: appends while there's room,
    /// updates in place on a name match (case-insensitive), refuses at the cap.
    @Test func saveAsFavoriteAppendsUpdatesAndCaps() throws {
        let container = try ModelContainer(
            for: FoodEntry.self, Favorite.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = CaptureViewModel(context: container.mainContext)

        try withExtendedLifetime(container) {
            let porridge = FoodEntry(name: "Porridge",
                                     macros: Macros(kcal: 300, protein: 12, carbs: 50, fat: 6),
                                     capturedAt: Date(), status: .written)
            #expect(model.saveAsFavorite(porridge) == .saved)

            // Same name, different case: the favourite's values update.
            let edited = FoodEntry(name: "porridge",
                                   macros: Macros(kcal: 350, protein: 15, carbs: 55, fat: 8),
                                   capturedAt: Date(), status: .written)
            #expect(model.saveAsFavorite(edited) == .updated)
            let favorites = try container.mainContext.fetch(FetchDescriptor<Favorite>())
            #expect(favorites.count == 1)
            #expect(favorites.first?.kcal == 350)

            // Fill to the cap; the next distinct name is refused.
            for index in 1..<Favorite.maxCount {
                let filler = FoodEntry(name: "Meal \(index)", macros: .zero,
                                       capturedAt: Date(), status: .written)
                #expect(model.saveAsFavorite(filler) == .saved)
            }
            let overflow = FoodEntry(name: "One too many", macros: .zero,
                                     capturedAt: Date(), status: .written)
            #expect(model.saveAsFavorite(overflow) == .full)
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
