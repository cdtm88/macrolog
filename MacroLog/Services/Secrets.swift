import Foundation

/// Reads the Anthropic API key that the build injected into Info.plist from the
/// gitignored `Secrets.xcconfig` (PRD decision D-05 / SEC-01). The key is never
/// committed to version control; see README for the one-time setup.
enum Secrets {
    static var anthropicAPIKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
