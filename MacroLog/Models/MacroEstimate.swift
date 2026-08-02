import Foundation

/// The result of asking the model to estimate a meal. Either the food was
/// identified and we have numbers, or it could not be identified and the app
/// should prompt for a text description rather than returning a guess (EST-04).
struct MacroEstimate: Equatable {
    /// Short human-readable name for the meal, e.g. "Chicken tikka masala & rice".
    var name: String
    var macros: Macros
}

/// The exact JSON contract the model is asked to return. Decoding this is the
/// single source of truth for EST-01/03: exactly the expected numeric keys, or
/// an error state — never silently-written zeros.
struct EstimationResponse: Decodable {
    let identified: Bool
    let name: String?
    let kcal: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let fiber: Double?
    let sodium: Double?
}
