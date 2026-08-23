import Foundation

/// Shared machinery for the outbound bridges (spec P06/P07 plus the nutrition
/// bridge). Everything here exists exactly once so the three bridges cannot
/// drift apart: intervals.icu config and transport, day-string formatting,
/// date-keyed queue rules, failure classification, and the queue files.

// MARK: - intervals.icu

/// The intervals.icu credential pair, shared by the weight and nutrition
/// bridges — one config, one activation switch (HB-07).
struct IntervalsConfig {
    let athleteID: String
    let apiKey: String

    static func load() -> IntervalsConfig? {
        guard let id = Secrets.intervalsAthleteID, let key = Secrets.intervalsAPIKey else {
            return nil
        }
        return IntervalsConfig(athleteID: id, apiKey: key)
    }
}

/// The one wellness transport: `PUT /api/v1/athlete/{id}/wellness/{date}`,
/// basic auth with the literal username `API_KEY` (HB-04). The PUT is a
/// partial update — only the fields in `body` change — and idempotent per
/// date. Live-verified 2026-08-02 (weight) and 2026-08-21 (nutrition).
enum IntervalsAPI {
    static func putWellness(_ body: [String: Any],
                            date: String,
                            config: IntervalsConfig,
                            session: URLSession) async throws {
        let url = URL(string: "https://intervals.icu/api/v1")!
            .appending(path: "athlete/\(config.athleteID)/wellness/\(date)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let credentials = Data("API_KEY:\(config.apiKey)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw BridgeSendError.classify(status: http.statusCode)
        }
    }
}

// MARK: - Day keys

/// Local civil-day string ("yyyy-MM-dd") for the wellness date path. The
/// calendar is deliberately required, not defaulted: a key must be computed
/// with the same calendar as the query it labels, or a mid-session timezone
/// change can file one day's data under another's date.
enum BridgeDay {
    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

// MARK: - Date-keyed queues

/// Queue collapse and bounding shared by the per-date upload queues (HB-10):
/// one pending write per date (newest state wins, original queue position
/// kept so drain stays oldest-first), and a hard cap whose overflow is
/// returned for logging, never dropped silently.
protocol DateKeyedUpload {
    var date: String { get }
}

extension Array where Element: DateKeyedUpload {
    func merging(_ upload: Element) -> [Element] {
        var merged = self
        if let index = merged.firstIndex(where: { $0.date == upload.date }) {
            merged[index] = upload
        } else {
            merged.append(upload)
        }
        return merged
    }

    func bounded(limit: Int) -> (kept: [Element], evicted: [Element]) {
        guard count > limit else { return (self, []) }
        let overflow = count - limit
        return (Array(dropFirst(overflow)), Array(prefix(overflow)))
    }
}

// MARK: - Failure classification

/// Send-failure classification shared by every bridge queue. Transport errors
/// and server-side conditions (5xx, 408, 429) are worth replaying; any other
/// non-2xx is a permanent rejection (rotated secret, wrong athlete ID, bad
/// payload) that can never succeed and must not wedge the queue behind it.
enum BridgeSendError: Error, Equatable {
    case permanent(status: Int)
    case retryable(status: Int)

    static func classify(status: Int) -> BridgeSendError {
        switch status {
        case 500...599, 408, 429: return .retryable(status: status)
        default: return .permanent(status: status)
        }
    }
}

// MARK: - Queue files

/// Locations for the bridge queues: plain JSON files in Application Support,
/// deliberately outside the SwiftData store so the bridges add nothing to the
/// existing persistence model (ARCH-01/05).
enum BridgeFiles {
    static func url(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appending(path: "Bridge", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: name)
    }

    /// Appends lines to a local log file — the shared "never drop silently"
    /// mechanism behind HB-10 evictions and permanently rejected items.
    static func appendLog(_ lines: [String], to url: URL) {
        guard !lines.isEmpty else { return }
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
