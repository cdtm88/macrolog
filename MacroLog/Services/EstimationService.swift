import UIKit

/// Turns a photo or text description into a reviewed-ready `MacroEstimate`
/// (phase 02). Owns the fixed prompt, the JSON contract, and the mapping from
/// model output to either an estimate or a named error.
struct EstimationService {

    func estimate(image: UIImage) async throws -> MacroEstimate {
        guard let prepared = ImageProcessing.prepare(image) else {
            throw EstimationError.unparseable
        }
        let content: [AnthropicClient.Content] = [
            .image(base64: prepared.base64, mediaType: prepared.mediaType),
            .text(EstimationPrompt.photoInstruction)
        ]
        return try await run(content: content)
    }

    func estimate(text: String) async throws -> MacroEstimate {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let content: [AnthropicClient.Content] = [
            .text(EstimationPrompt.textInstruction(trimmed))
        ]
        return try await run(content: content, fallbackName: trimmed)
    }

    // MARK: - Shared path

    private func run(content: [AnthropicClient.Content],
                     fallbackName: String? = nil) async throws -> MacroEstimate {
        guard let key = Secrets.anthropicAPIKey else {
            throw EstimationError.missingAPIKey
        }
        let client = AnthropicClient(apiKey: key)
        let raw = try await client.complete(model: EstimationPrompt.primaryModel,
                                            system: EstimationPrompt.system,
                                            content: content)
        return try Self.decode(raw, fallbackName: fallbackName)
    }

    /// Strictly decodes the model output into a `MacroEstimate`. Anything that
    /// isn't the expected four-number shape is surfaced as an error rather than
    /// written as zeros or partial data (EST-03).
    static func decode(_ raw: String, fallbackName: String?) throws -> MacroEstimate {
        guard let jsonData = extractJSON(from: raw) else {
            throw EstimationError.unparseable
        }
        let response: EstimationResponse
        do {
            response = try JSONDecoder().decode(EstimationResponse.self, from: jsonData)
        } catch {
            throw EstimationError.unparseable
        }

        // The model explicitly could not identify the food — prompt for text
        // rather than returning a guess (EST-04).
        guard response.identified,
              let kcal = response.kcal,
              let protein = response.protein,
              let carbs = response.carbs,
              let fat = response.fat else {
            if response.identified { throw EstimationError.unparseable }
            throw EstimationError.couldNotIdentify
        }

        let name = response.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (name?.isEmpty == false ? name : nil)
            ?? fallbackName
            ?? "Meal"

        return MacroEstimate(
            name: resolvedName,
            macros: Macros(kcal: kcal.rounded(),
                           protein: protein.rounded(),
                           carbs: carbs.rounded(),
                           fat: fat.rounded())
        )
    }

    /// Pulls the first balanced `{ ... }` object out of the response text, so a
    /// stray markdown fence or leading prose doesn't defeat decoding.
    private static func extractJSON(from raw: String) -> Data? {
        guard let start = raw.firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = start
        while index < raw.endIndex {
            let ch = raw[index]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    let slice = raw[start...index]
                    return String(slice).data(using: .utf8)
                }
            }
            index = raw.index(after: index)
        }
        return nil
    }
}
