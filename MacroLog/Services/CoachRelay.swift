import Foundation

/// One meal state bound for the coach: the latest confirmed values, or a
/// deletion marker, keyed by the stable local entry ID (MAC-01/03).
struct CoachMealItem: Codable, Equatable {
    var mealID: UUID
    var loggedAt: Date
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var deleted: Bool
}

extension CoachMealItem {
    /// Meal type derived from the local capture hour — MacroLog has no meal
    /// concept of its own, and the boundaries only steer coaching copy.
    static func mealType(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5...10:  return "breakfast"
        case 11...15: return "lunch"
        case 16...21: return "dinner"
        default:      return "snack"
        }
    }

    /// Local-offset ISO 8601, e.g. `2026-08-01T13:20:00+04:00` — the coach
    /// cares which meal of the athlete's day this was, not about UTC.
    static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }()

    /// The exact wire shape from the bridge spec §5 — nothing more.
    func payload(calendar: Calendar = .current) -> [String: Any] {
        [
            "meal_id": mealID.uuidString.lowercased(),
            "logged_at": Self.timestampFormatter.string(from: loggedAt),
            "meal_type": Self.mealType(for: loggedAt, calendar: calendar),
            "calories": Int(kcal.rounded()),
            "protein_g": Int(protein.rounded()),
            "carbs_g": Int(carbs.rounded()),
            "fat_g": Int(fat.rounded()),
            "deleted": deleted
        ]
    }

    /// Queue collapse: one pending state per meal ID, newest wins, so an edit
    /// updates the queued post and a delete supersedes any queued upsert.
    /// Replay of the survivor is idempotent upstream on meal_id (MAC-08).
    static func merge(_ queue: [CoachMealItem], with item: CoachMealItem) -> [CoachMealItem] {
        var merged = queue.filter { $0.mealID != item.mealID }
        merged.append(item)
        return merged
    }
}

/// Fire-and-forget relay of per-meal macros to the coach ingest endpoint
/// (bridge spec P06). Fully inert when the coach URL/secret are absent from
/// the gitignored config.
///
/// Independence guarantees (ARCH-01/02, MAC-05/06/07): its own on-disk queue,
/// never awaited by the confirm path, never blocks or is blocked by the
/// HealthKit write, and never surfaces an error to the user — failures retry
/// with backoff in-session and drain on the next foreground launch.
actor CoachRelay {
    struct Config {
        let baseURL: URL
        let secret: String
    }

    static func loadConfig() -> Config? {
        guard let url = Secrets.coachBaseURL, let secret = Secrets.coachIngestSecret else {
            return nil
        }
        return Config(baseURL: url, secret: secret)
    }

    private let config: Config?
    private let session: URLSession
    private let queueFile: URL
    private let dropLog: URL

    private var queue: [CoachMealItem] = []
    private var loaded = false
    private var consecutiveFailures = 0
    private var retryTask: Task<Void, Never>?

    init(config: Config? = CoachRelay.loadConfig(),
         session: URLSession = .shared,
         queueFile: URL = BridgeFiles.url("coach-queue.json"),
         dropLog: URL = BridgeFiles.url("coach-drops.log")) {
        self.config = config
        self.session = session
        self.queueFile = queueFile
        self.dropLog = dropLog
    }

    // MARK: - Enqueue

    func recordConfirmation(mealID: UUID, loggedAt: Date, macros: Macros) {
        enqueue(CoachMealItem(mealID: mealID, loggedAt: loggedAt,
                              kcal: macros.kcal, protein: macros.protein,
                              carbs: macros.carbs, fat: macros.fat,
                              deleted: false))
    }

    func recordDeletion(mealID: UUID, loggedAt: Date, macros: Macros) {
        enqueue(CoachMealItem(mealID: mealID, loggedAt: loggedAt,
                              kcal: macros.kcal, protein: macros.protein,
                              carbs: macros.carbs, fat: macros.fat,
                              deleted: true))
    }

    private func enqueue(_ item: CoachMealItem) {
        guard config != nil else { return }
        loadIfNeeded()
        queue = CoachMealItem.merge(queue, with: item)
        persist()
        kick()
    }

    // MARK: - Drain

    /// Called on foreground launch and after every enqueue. Resets any backoff
    /// wait so a fresh foreground always tries immediately (MAC-06).
    func kick() {
        guard config != nil else { return }
        retryTask?.cancel()
        retryTask = nil
        consecutiveFailures = 0
        Task { await drain() }
    }

    // Internal (not private) so tests can drive the drain deterministically
    // against a stubbed session, without kick()'s unstructured Task.
    func drain() async {
        guard let config else { return }
        loadIfNeeded()
        while let item = queue.first {
            do {
                try await post(item, config: config)
                queue.removeFirst()
                persist()
                consecutiveFailures = 0
            } catch BridgeSendError.permanent(let status) {
                // The endpoint rejected this item outright (rotated secret,
                // malformed payload) — replay can never succeed, and leaving
                // it at the head would wedge every later meal behind it
                // forever. Log the full payload, drop it, keep draining.
                // Still invisible to the user (MAC-06).
                BridgeFiles.appendLog(["HTTP \(status) dropped \(payloadDescription(item))"],
                                      to: dropLog)
                queue.removeFirst()
                persist()
            } catch {
                // Retryable (transport, timeout, 5xx, 408, 429): oldest-first
                // ordering is preserved; back off and retry the whole queue
                // later (MAC-06).
                consecutiveFailures += 1
                scheduleRetry()
                return
            }
        }
    }

    private func payloadDescription(_ item: CoachMealItem) -> String {
        (try? JSONSerialization.data(withJSONObject: item.payload()))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? item.mealID.uuidString.lowercased()
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        let delay = min(pow(2, Double(consecutiveFailures)) * 15, 900)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.retryFired()
        }
    }

    private func retryFired() async {
        retryTask = nil
        await drain()
    }

    // MARK: - Network

    private func post(_ item: CoachMealItem, config: Config) async throws {
        var request = URLRequest(url: config.baseURL.appending(path: "ingest/meal"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.secret, forHTTPHeaderField: "X-Ingest-Secret")
        request.httpBody = try JSONSerialization.data(withJSONObject: item.payload())

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw BridgeSendError.classify(status: http.statusCode)
        }
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: queueFile),
           let stored = try? JSONDecoder().decode([CoachMealItem].self, from: data) {
            queue = stored
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(queue) {
            try? data.write(to: queueFile, options: .atomic)
        }
    }

    // Test hook: the queue as it would drain, oldest first.
    func queuedItems() -> [CoachMealItem] {
        loadIfNeeded()
        return queue
    }
}

// BridgeSendError and BridgeFiles, shared by every bridge queue, live in
// BridgeSupport.swift.
