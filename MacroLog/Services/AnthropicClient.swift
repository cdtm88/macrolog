import Foundation

/// Minimal client for the Anthropic Messages API, called directly from the app
/// with no backend (PRD decision D-03). Uses the vision-capable messages
/// endpoint; no tools or MCP (assumption in §9 of the PRD).
struct AnthropicClient {
    private let apiKey: String
    private let session: URLSession

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// One content block in a user message: an image, or text.
    enum Content {
        case image(base64: String, mediaType: String)
        case text(String)

        var json: [String: Any] {
            switch self {
            case .image(let base64, let mediaType):
                return [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": mediaType,
                        "data": base64
                    ]
                ]
            case .text(let text):
                return ["type": "text", "text": text]
            }
        }
    }

    /// Sends a single-user-turn request and returns the concatenated text of the
    /// assistant's response. Throws an `EstimationError` on any failure so the UI
    /// can distinguish connectivity from API problems.
    ///
    /// When `outputSchema` is provided it is sent as a structured-output format,
    /// so the response text is guaranteed to be JSON matching the schema (EST-03
    /// — no unparseable responses).
    func complete(model: String,
                  system: String,
                  content: [Content],
                  maxTokens: Int = 512,
                  outputSchema: [String: Any]? = nil) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60 // PERF-03 handles the "still working" hint in UI
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [
                ["role": "user", "content": content.map(\.json)]
            ]
        ]
        if let outputSchema {
            body["output_config"] = [
                "format": ["type": "json_schema", "schema": outputSchema]
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw Self.mapTransport(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw EstimationError.api(status: 0, message: "No HTTP response.")
        }

        guard (200...299).contains(http.statusCode) else {
            throw EstimationError.api(status: http.statusCode,
                                      message: Self.apiMessage(from: data, status: http.statusCode))
        }

        return try Self.extractText(from: data)
    }

    // MARK: - Response parsing

    private static func extractText(from data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EstimationError.unparseable
        }
        // A safety refusal is a valid HTTP 200 — treat as an API-level refusal so
        // the user sees a named cause rather than a silent zero.
        if let stop = object["stop_reason"] as? String, stop == "refusal" {
            throw EstimationError.api(status: 200, message: "The request was declined.")
        }
        guard let content = object["content"] as? [[String: Any]] else {
            throw EstimationError.unparseable
        }
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else { throw EstimationError.unparseable }
        return text
    }

    private static func apiMessage(from data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        switch status {
        case 401, 403: return "Authentication failed — check the API key."
        case 429:      return "Rate limit or quota exceeded."
        case 500...:   return "The service had a server error."
        default:       return "HTTP \(status)."
        }
    }

    private static func mapTransport(_ error: URLError) -> EstimationError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost,
             .cannotConnectToHost, .cannotFindHost, .timedOut,
             .dataNotAllowed, .internationalRoamingOff:
            return .noConnectivity
        default:
            return .api(status: 0, message: error.localizedDescription)
        }
    }
}
