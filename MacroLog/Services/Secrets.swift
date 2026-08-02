import Foundation

/// Reads credentials that the build injected into Info.plist from the
/// gitignored `Secrets.xcconfig` (PRD decision D-05 / SEC-01; bridge spec
/// HB-07 / MAC-04). Nothing here is ever committed; see README for setup.
///
/// Every accessor returns nil when its key is absent or blank — the bridge
/// features treat a nil as "disabled" rather than an error.
enum Secrets {
    static var anthropicAPIKey: String? { value("ANTHROPIC_API_KEY") }

    // intervals.icu body-mass bridge (P07). Both must be present to activate.
    static var intervalsAthleteID: String? { value("INTERVALS_ATHLETE_ID") }
    static var intervalsAPIKey: String? { value("INTERVALS_API_KEY") }

    // Coach macro relay (P06). Both must be present to activate.
    static var coachBaseURL: URL? {
        value("COACH_BASE_URL").flatMap(URL.init(string:))
    }
    static var coachIngestSecret: String? { value("COACH_INGEST_SECRET") }

    private static func value(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
