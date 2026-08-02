import Testing
import Foundation
import SwiftData
@testable import MacroLog

/// A typed description must survive a failed estimate (so a repeat "couldn't
/// identify" reseeds the text sheet, CAP-05/EST-05) and be cleared once an
/// estimate succeeds (so it can't leak into an unrelated later capture).
@MainActor
struct RetainedTextTests {

    @Test func retainedTextSurvivesFailureAndClearsOnSuccess() throws {
        let container = try ModelContainer(
            for: FoodEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = CaptureViewModel(context: container.mainContext)

        try withExtendedLifetime(container) {
            model.submitText("mystery grain bowl")
            // Keep the test offline: cancel the fired request and drive the
            // estimation outcomes directly.
            model.workTask?.cancel()
            #expect(model.lastText == "mystery grain bowl")

            // Model couldn't identify it → sheet reopens; the description
            // must still be there to reseed the field.
            model.handleEstimationError(.couldNotIdentify)
            #expect(model.needsTextAfterPhoto)
            #expect(model.isShowingText)
            #expect(model.lastText == "mystery grain bowl")

            // A successful estimate consumes the description.
            model.handleEstimate(
                MacroEstimate(name: "Grain bowl",
                              macros: Macros(kcal: 500, protein: 20, carbs: 70, fat: 15)),
                capturedAt: Date())
            #expect(model.lastText == nil)

            let saved = try container.mainContext.fetch(FetchDescriptor<FoodEntry>())
            #expect(saved.count == 1)
        }
    }

    /// A non-identification failure (API, connectivity) also reopens the text
    /// sheet with the description retained, so the retry is an edit rather
    /// than a retype — and never carries a phantom photo for a text-only
    /// submission.
    @Test func apiFailureReopensSheetWithTextRetained() throws {
        let container = try ModelContainer(
            for: FoodEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = CaptureViewModel(context: container.mainContext)

        withExtendedLifetime(container) {
            model.submitText("mystery grain bowl")
            model.workTask?.cancel()

            model.handleEstimationError(.api(status: 500, message: "overloaded"))
            #expect(model.isShowingText)
            #expect(model.estimationError == .api(status: 500, message: "overloaded"))
            #expect(model.lastText == "mystery grain bowl")
            #expect(!model.needsTextAfterPhoto) // no photo was part of the failure
        }
    }
}
