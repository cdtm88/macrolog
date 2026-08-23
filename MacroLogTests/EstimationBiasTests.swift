import Testing
import Foundation
@testable import MacroLog

/// The settings sheet's estimation-accuracy numbers: signed aggregate error
/// as a fraction of the confirmed total, over instrumented meals only.
struct EstimationBiasTests {

    private func item(estimated: Macros?, confirmed: Macros) -> MealExportItem {
        MealExportItem(capturedAt: Date(timeIntervalSince1970: 0), name: "Meal",
                       macros: confirmed, estimated: estimated)
    }

    @Test func aggregateSignedFractionPerMacro() throws {
        // Estimates: 550 kcal vs 500 confirmed (+10%), protein 45 vs 50 (−10%).
        let items = [
            item(estimated: Macros(kcal: 300, protein: 20, carbs: 30, fat: 10, fiber: 3, sodium: 500),
                 confirmed: Macros(kcal: 250, protein: 25, carbs: 30, fat: 10, fiber: 3, sodium: 500)),
            item(estimated: Macros(kcal: 250, protein: 25, carbs: 30, fat: 10, fiber: 3, sodium: 500),
                 confirmed: Macros(kcal: 250, protein: 25, carbs: 30, fat: 10, fiber: 3, sodium: 500))
        ]
        let bias = try #require(EstimationBias.compute(items: items))
        #expect(bias.mealCount == 2)
        #expect(abs(bias.kcal! - 0.1) < 0.0001)
        #expect(abs(bias.protein! - (-0.1)) < 0.0001)
        #expect(bias.carbs! == 0)
        #expect(bias.fat! == 0)
    }

    @Test func mealsWithoutEstimatesAreExcluded() throws {
        // A favourite (no estimate) must not dilute the bias.
        let items = [
            item(estimated: Macros(kcal: 220, protein: 10, carbs: 20, fat: 8, fiber: 2, sodium: 300),
                 confirmed: Macros(kcal: 200, protein: 10, carbs: 20, fat: 8, fiber: 2, sodium: 300)),
            item(estimated: nil,
                 confirmed: Macros(kcal: 1000, protein: 80, carbs: 100, fat: 40, fiber: 10, sodium: 900))
        ]
        let bias = try #require(EstimationBias.compute(items: items))
        #expect(bias.mealCount == 1)
        #expect(abs(bias.kcal! - 0.1) < 0.0001)
    }

    @Test func noInstrumentedMealsMeansNil() {
        let items = [item(estimated: nil, confirmed: Macros(kcal: 500, protein: 30, carbs: 50, fat: 20))]
        #expect(EstimationBias.compute(items: items) == nil)
        #expect(EstimationBias.compute(items: []) == nil)
    }

    @Test func zeroConfirmedTotalMeansNilForThatMacro() throws {
        // Confirmed fibre is zero across the set — no denominator, no figure.
        let items = [
            item(estimated: Macros(kcal: 220, protein: 10, carbs: 20, fat: 8, fiber: 4, sodium: 300),
                 confirmed: Macros(kcal: 200, protein: 10, carbs: 20, fat: 8, fiber: 0, sodium: 300))
        ]
        let bias = try #require(EstimationBias.compute(items: items))
        #expect(bias.fiber == nil)
        #expect(bias.kcal != nil)
    }
}
