import Foundation

/// The fixed system prompt used for every estimation request. Held here as a
/// single source constant and never varied per request (EST-02). It instructs
/// the model to account for cooking oils, butter, and sauces, and to return a
/// single point estimate as strict JSON (EST-06).
enum EstimationPrompt {
    /// Model used for estimation. PRD decision D-04: latest Sonnet for speed and
    /// cost, with Opus available as a fallback if estimate quality proves
    /// inadequate. Swap `primaryModel` to `fallbackModel` if that day comes.
    static let primaryModel = "claude-sonnet-5"
    static let fallbackModel = "claude-opus-4-8"

    static let system = """
    You are a nutrition estimator for a single user logging meals to Apple Health.

    You will be given either a photo of a meal or a short text description. Return \
    a macronutrient estimate for the WHOLE portion shown or described.

    Rules:
    - Account for cooking oils, butter, dressings, and sauces even when they are \
    not obviously visible — restaurant and home-cooked food usually contains far \
    more added fat than it looks.
    - Return a single point estimate, not a range and not a hedged answer. The user \
    reviews and adjusts every number before it is saved, so commit to your best \
    single guess.
    - Estimate calories (kcal), protein (g), carbohydrate (g), and fat (g).
    - Give a short, specific name for the meal (e.g. "Chicken tikka masala & rice").
    - If you are shown a photo and genuinely cannot tell what the food is, set \
    "identified" to false and leave the numbers null rather than guessing wildly.

    Respond with ONLY a JSON object, no prose, no markdown fences, in exactly this \
    shape:
    {"identified": true, "name": "<short name>", "kcal": <number>, "protein": \
    <grams>, "carbs": <grams>, "fat": <grams>}

    When you cannot identify the food:
    {"identified": false, "name": null, "kcal": null, "protein": null, "carbs": \
    null, "fat": null}
    """

    static let photoInstruction = "Estimate the macros for this meal."

    static func textInstruction(_ description: String) -> String {
        "Estimate the macros for this meal: \(description)"
    }

    /// Instruction when a photo could not be identified and the user supplied a
    /// text description — the photo is re-sent for portion-size context (EST-04).
    static func photoWithTextInstruction(_ description: String) -> String {
        "Estimate the macros for this meal. The photo alone wasn't identifiable; " +
        "the user describes it as: \(description). Use the photo for portion size."
    }

    /// Structured-output schema enforcing the exact response shape, so the API
    /// guarantees valid JSON and the unparseable failure mode disappears (EST-03).
    static let responseSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "identified": ["type": "boolean"],
            "name": ["type": ["string", "null"]],
            "kcal": ["type": ["number", "null"]],
            "protein": ["type": ["number", "null"]],
            "carbs": ["type": ["number", "null"]],
            "fat": ["type": ["number", "null"]]
        ],
        "required": ["identified", "name", "kcal", "protein", "carbs", "fat"],
        "additionalProperties": false
    ]
}
