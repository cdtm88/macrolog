import Testing
import Foundation
@testable import MacroLog

/// The model-output → MacroEstimate contract (EST-01/03/04): exactly the
/// expected shape decodes; anything else is a named error, never zeros.
struct EstimationDecodeTests {

    @Test func decodesCleanJSON() throws {
        let raw = #"{"identified": true, "name": "Chicken salad", "kcal": 420.4, "protein": 32.6, "carbs": 12.2, "fat": 24.5, "fiber": 4.4, "sodium": 612.7}"#
        let estimate = try EstimationService.decode(raw, fallbackName: nil)
        #expect(estimate.name == "Chicken salad")
        #expect(estimate.macros.kcal == 420)
        #expect(estimate.macros.protein == 33)
        #expect(estimate.macros.carbs == 12)
        #expect(estimate.macros.fat == 25)
        #expect(estimate.macros.fiber == 4)
        #expect(estimate.macros.sodium == 613)
    }

    @Test func decodesFencedJSON() throws {
        let raw = """
        ```json
        {"identified": true, "name": "Oatmeal", "kcal": 300, "protein": 10, "carbs": 54, "fat": 6, "fiber": 8, "sodium": 150}
        ```
        """
        let estimate = try EstimationService.decode(raw, fallbackName: nil)
        #expect(estimate.name == "Oatmeal")
        #expect(estimate.macros.kcal == 300)
    }

    @Test func decodesProseWrappedJSON() throws {
        let raw = #"Here is the estimate: {"identified": true, "name": "Toast", "kcal": 180, "protein": 5, "carbs": 30, "fat": 4, "fiber": 2, "sodium": 220} — enjoy!"#
        let estimate = try EstimationService.decode(raw, fallbackName: nil)
        #expect(estimate.name == "Toast")
    }

    @Test func unidentifiedFoodThrowsCouldNotIdentify() {
        let raw = #"{"identified": false, "name": null, "kcal": null, "protein": null, "carbs": null, "fat": null, "fiber": null, "sodium": null}"#
        #expect(throws: EstimationError.couldNotIdentify) {
            try EstimationService.decode(raw, fallbackName: nil)
        }
    }

    @Test func identifiedButMissingNumberThrowsUnparseable() {
        // identified=true with a null macro must never be written as a zero (EST-03).
        let raw = #"{"identified": true, "name": "Soup", "kcal": 200, "protein": null, "carbs": 20, "fat": 8, "fiber": 1, "sodium": 900}"#
        #expect(throws: EstimationError.unparseable) {
            try EstimationService.decode(raw, fallbackName: nil)
        }
    }

    @Test func identifiedButMissingFiberOrSodiumThrowsUnparseable() {
        // The pre-fibre/sodium response shape must not decode into silent zeros.
        let raw = #"{"identified": true, "name": "Soup", "kcal": 200, "protein": 12, "carbs": 20, "fat": 8}"#
        #expect(throws: EstimationError.unparseable) {
            try EstimationService.decode(raw, fallbackName: nil)
        }
    }

    @Test func garbageThrowsUnparseable() {
        #expect(throws: EstimationError.unparseable) {
            try EstimationService.decode("I think that's some kind of food.", fallbackName: nil)
        }
    }

    @Test func missingNameFallsBackToDescription() throws {
        let raw = #"{"identified": true, "name": null, "kcal": 500, "protein": 30, "carbs": 40, "fat": 20, "fiber": 5, "sodium": 700}"#
        let estimate = try EstimationService.decode(raw, fallbackName: "leftover pasta")
        #expect(estimate.name == "leftover pasta")
    }

    @Test func blankNameWithoutFallbackUsesPlaceholder() throws {
        let raw = #"{"identified": true, "name": "  ", "kcal": 500, "protein": 30, "carbs": 40, "fat": 20, "fiber": 5, "sodium": 700}"#
        let estimate = try EstimationService.decode(raw, fallbackName: nil)
        #expect(estimate.name == "Meal")
    }
}
