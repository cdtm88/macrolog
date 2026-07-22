import Foundation

/// The four macronutrient values MacroLog reads, writes to Apple Health, and
/// surfaces on the widget. These are the only nutrition entries Whoop's Journal
/// consumes (PRD decision D-06), so nothing else is modelled.
///
/// This type is compiled into both the app and the widget target so the two
/// share one definition of "a set of macros".
public struct Macros: Codable, Equatable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double

    public init(kcal: Double, protein: Double, carbs: Double, fat: Double) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    public static let zero = Macros(kcal: 0, protein: 0, carbs: 0, fat: 0)

    public static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(kcal: lhs.kcal + rhs.kcal,
               protein: lhs.protein + rhs.protein,
               carbs: lhs.carbs + rhs.carbs,
               fat: lhs.fat + rhs.fat)
    }
}
