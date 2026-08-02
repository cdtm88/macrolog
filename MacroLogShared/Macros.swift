import Foundation

/// The nutrient values MacroLog reads, writes to Apple Health, and surfaces on
/// the widget: the four Whoop Journal macros (PRD decision D-06) plus fibre and
/// sodium, added post-PRD from real-world use.
///
/// This type is compiled into both the app and the widget target so the two
/// share one definition of "a set of macros".
public struct Macros: Codable, Equatable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    /// Grams.
    public var fiber: Double
    /// Milligrams.
    public var sodium: Double

    public init(kcal: Double, protein: Double, carbs: Double, fat: Double,
                fiber: Double = 0, sodium: Double = 0) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sodium = sodium
    }

    public static let zero = Macros(kcal: 0, protein: 0, carbs: 0, fat: 0, fiber: 0, sodium: 0)

    public static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(kcal: lhs.kcal + rhs.kcal,
               protein: lhs.protein + rhs.protein,
               carbs: lhs.carbs + rhs.carbs,
               fat: lhs.fat + rhs.fat,
               fiber: lhs.fiber + rhs.fiber,
               sodium: lhs.sodium + rhs.sodium)
    }

    // MARK: - Calorie split

    /// Each macro's share of the calories attributable to macros (protein and
    /// carbs ×4 kcal/g, fat ×9) — the same weighting the ring segments use.
    /// `nil` when nothing has been logged, so views can omit the figure rather
    /// than render a meaningless 0%.
    public var proteinPercent: Int? { percent(of: protein * 4) }
    public var carbsPercent: Int? { percent(of: carbs * 4) }
    public var fatPercent: Int? { percent(of: fat * 9) }

    private func percent(of calories: Double) -> Int? {
        let total = protein * 4 + carbs * 4 + fat * 9
        guard total > 0 else { return nil }
        return Int((calories / total * 100).rounded())
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case kcal, protein, carbs, fat, fiber, sodium
    }

    /// Fibre and sodium default to 0 so a widget snapshot written before they
    /// existed still decodes instead of zeroing the whole day.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kcal = try container.decode(Double.self, forKey: .kcal)
        protein = try container.decode(Double.self, forKey: .protein)
        carbs = try container.decode(Double.self, forKey: .carbs)
        fat = try container.decode(Double.self, forKey: .fat)
        fiber = try container.decodeIfPresent(Double.self, forKey: .fiber) ?? 0
        sodium = try container.decodeIfPresent(Double.self, forKey: .sodium) ?? 0
    }
}
