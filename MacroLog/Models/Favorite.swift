import Foundation
import SwiftData

/// A preconfigured meal with known macros — one tap logs it without an AI
/// estimate. Configured by the user in the Favourites sheet; surfaced as chips
/// under the text entry box.
@Model
final class Favorite {
    /// Hard cap so the chip row stays scannable.
    static let maxCount = 6

    @Attribute(.unique) var id: UUID
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// Grams. Defaults keep pre-fibre/sodium stores migrating cleanly.
    var fiber: Double = 0
    /// Milligrams.
    var sodium: Double = 0
    /// Display order in the chip row, lowest first.
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, macros: Macros, sortOrder: Int) {
        self.id = id
        self.name = name
        self.kcal = macros.kcal
        self.protein = macros.protein
        self.carbs = macros.carbs
        self.fat = macros.fat
        self.fiber = macros.fiber
        self.sodium = macros.sodium
        self.sortOrder = sortOrder
    }

    var macros: Macros {
        get { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat, fiber: fiber, sodium: sodium) }
        set {
            kcal = newValue.kcal
            protein = newValue.protein
            carbs = newValue.carbs
            fat = newValue.fat
            fiber = newValue.fiber
            sodium = newValue.sodium
        }
    }
}
