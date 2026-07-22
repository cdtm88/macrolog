import Foundation

/// Failure modes surfaced to the user during estimation. Each case names its
/// cause so the review/capture UI can distinguish, per PRD decision D-10 (fail
/// loudly, never guess) and requirements EST-05 / EST-07 / EST-04.
enum EstimationError: LocalizedError, Equatable, Identifiable {
    var id: String { errorTitle + (errorDescription ?? "") }

    /// No network connectivity. Explicitly names connectivity and offers retry;
    /// the input is preserved (EST-05).
    case noConnectivity

    /// An API-level failure — authentication, rate limit, quota, or server
    /// error — distinguishable from a connectivity failure (EST-07).
    case api(status: Int, message: String)

    /// The model's response could not be parsed into the four numeric values
    /// (EST-03).
    case unparseable

    /// The food in the photo could not be identified; the app should prompt for
    /// a supplementary text description (EST-04).
    case couldNotIdentify

    /// The API key is missing from the gitignored config (SEC-01 setup step).
    case missingAPIKey

    var errorTitle: String {
        switch self {
        case .noConnectivity:   return "No connection"
        case .api:              return "Couldn't reach the estimator"
        case .unparseable:      return "Unexpected response"
        case .couldNotIdentify: return "Couldn't identify the food"
        case .missingAPIKey:    return "API key not set"
        }
    }

    var errorDescription: String? {
        switch self {
        case .noConnectivity:
            return "You're offline. Your meal is saved — reconnect and retry."
        case .api(let status, let message):
            return "The estimator returned an error (\(status)). \(message)"
        case .unparseable:
            return "The estimator sent something we couldn't read. Retry, or describe the meal in text."
        case .couldNotIdentify:
            return "Add a short text description so we can estimate it."
        case .missingAPIKey:
            return "Add your Anthropic API key to Secrets.xcconfig and rebuild."
        }
    }
}
