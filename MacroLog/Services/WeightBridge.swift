import Foundation
import HealthKit

/// A local registry of every bodyMass sample the anchored query has reported,
/// so a deletion in Health can recompute the affected day from what remains
/// (HB-02/03) without ever re-reading history.
struct WeightLedger: Codable, Equatable {
    struct Sample: Codable, Equatable {
        var day: String        // local "yyyy-MM-dd"
        var takenAt: Date
        var weightKg: Double
    }

    var samples: [UUID: Sample] = [:]

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Applies one anchored-query delta and returns the day keys whose value
    /// may have changed, oldest first.
    mutating func apply(added: [(uuid: UUID, takenAt: Date, weightKg: Double)],
                        deleted: [UUID],
                        calendar: Calendar = .current) -> [String] {
        var changed = Set<String>()
        for sample in added {
            let day = Self.dayKey(for: sample.takenAt, calendar: calendar)
            samples[sample.uuid] = Sample(day: day, takenAt: sample.takenAt, weightKg: sample.weightKg)
            changed.insert(day)
        }
        for uuid in deleted {
            if let removed = samples.removeValue(forKey: uuid) {
                changed.insert(removed.day)
            }
        }
        return changed.sorted()
    }

    /// One value per day: the earliest reading of that day (HB-03), or nil
    /// when every sample for the day has been deleted — which propagates as a
    /// cleared value upstream (HB-02).
    func value(forDay day: String) -> Double? {
        samples.values
            .filter { $0.day == day }
            .min { $0.takenAt < $1.takenAt }?
            .weightKg
    }
}

/// One pending intervals.icu write: a day and its weight, nil meaning "clear".
struct WeightUpload: Codable, Equatable {
    var date: String
    var weightKg: Double?
}

extension WeightUpload {
    /// Queue collapse and bounding (HB-10): one pending write per date (newest
    /// state wins, original queue position kept so drain stays oldest-first),
    /// and a hard cap whose overflow is returned for logging, never dropped
    /// silently.
    static func merge(_ queue: [WeightUpload], with upload: WeightUpload) -> [WeightUpload] {
        var merged = queue
        if let index = merged.firstIndex(where: { $0.date == upload.date }) {
            merged[index] = upload
        } else {
            merged.append(upload)
        }
        return merged
    }

    static func bounded(_ queue: [WeightUpload], limit: Int) -> (kept: [WeightUpload], evicted: [WeightUpload]) {
        guard queue.count > limit else { return (queue, []) }
        let overflow = queue.count - limit
        return (Array(queue.dropFirst(overflow)), Array(queue.prefix(overflow)))
    }
}

/// One-way bodyMass sync: Apple Health → intervals.icu wellness (bridge spec
/// P07). Fully inert until the intervals athlete ID and API key exist in the
/// gitignored config — it then requests read access for bodyMass only, in
/// that context rather than at first install (HB-08).
///
/// Runs on foreground launch, entirely off the meal-logging path (HB-11):
/// an anchored query with a persisted anchor yields adds and deletes since
/// last run (HB-01/02), days collapse to their earliest reading (HB-03), and
/// failed writes queue on disk to drain next foreground (HB-05). No weight
/// value ever appears in the UI (HB-12).
actor WeightBridge {
    struct Config {
        let athleteID: String
        let apiKey: String
    }

    static func loadConfig() -> Config? {
        guard let id = Secrets.intervalsAthleteID, let key = Secrets.intervalsAPIKey else {
            return nil
        }
        return Config(athleteID: id, apiKey: key)
    }

    /// Everything persisted between launches, one JSON file.
    private struct State: Codable {
        var anchor: Data?
        var ledger = WeightLedger()
        var pending: [WeightUpload] = []
        var authRequested = false
        var emptyHintShown = false
    }

    /// HB-10 bound: over a year of daily values queued before eviction.
    private static let queueLimit = 366

    private let config: Config?
    private let session: URLSession
    private let stateFile: URL
    private let evictionLog: URL
    private let store = HKHealthStore()
    private let bodyMass = HKQuantityType(.bodyMass)

    private var state = State()
    private var loaded = false
    private var syncing = false

    init(config: Config? = WeightBridge.loadConfig(),
         session: URLSession = .shared,
         stateFile: URL = BridgeFiles.url("weight-state.json"),
         evictionLog: URL = BridgeFiles.url("weight-evictions.log")) {
        self.config = config
        self.session = session
        self.stateFile = stateFile
        self.evictionLog = evictionLog
    }

    // MARK: - Foreground sync

    /// The whole cycle: authorize (once, in context), read the delta, requeue
    /// changed days, drain. `onNotice` delivers the single HB-09 hint — the
    /// only thing this bridge ever says to the user.
    func syncOnForeground(onNotice: @escaping @Sendable (String) -> Void) async {
        guard let config, HKHealthStore.isHealthDataAvailable(), !syncing else { return }
        syncing = true
        defer { syncing = false }
        loadIfNeeded()

        await requestAuthorizationIfNeeded()

        do {
            let anchor = state.anchor.flatMap {
                try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
            }
            let descriptor = HKAnchoredObjectQueryDescriptor(
                predicates: [.quantitySample(type: bodyMass)],
                anchor: anchor)
            let result = try await descriptor.result(for: store)

            let added = result.addedSamples.map { sample -> (UUID, Date, Double) in
                let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                return (sample.uuid, sample.startDate, (kg * 10).rounded() / 10)
            }
            let deleted = result.deletedObjects.map(\.uuid)

            let changedDays = state.ledger.apply(added: added, deleted: deleted)
            for day in changedDays {
                let upload = WeightUpload(date: day, weightKg: state.ledger.value(forDay: day))
                state.pending = WeightUpload.merge(state.pending, with: upload)
            }
            enforceQueueBound()
            state.anchor = try? NSKeyedArchiver.archivedData(withRootObject: result.newAnchor,
                                                             requiringSecureCoding: true)
            persist()
            surfaceEmptyHintIfWarranted(onNotice: onNotice)
        } catch {
            // Read failures are silent; the anchor is unchanged so the next
            // foreground retries the same delta (HB-11).
        }

        await drain(config: config)
    }

    /// Read access for bodyMass only, requested separately from the nutrition
    /// write authorisation and only once the bridge is configured (HB-08).
    private func requestAuthorizationIfNeeded() async {
        guard !state.authRequested else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [bodyMass])
            state.authRequested = true
            persist()
        } catch {
            // Leave the flag unset so a transient failure re-asks next launch.
        }
    }

    /// HealthKit hides read denial behind an empty result (the permission
    /// trap). If the very first full backfill returns nothing at all, say so
    /// once — one visible state change, never a nag (HB-09).
    private func surfaceEmptyHintIfWarranted(onNotice: @escaping @Sendable (String) -> Void) {
        guard state.authRequested, !state.emptyHintShown, state.ledger.samples.isEmpty else { return }
        state.emptyHintShown = true
        persist()
        onNotice("No weight readable from Health. If you use a smart scale, check MacroLog's read access under Settings › Health.")
    }

    // MARK: - Drain

    private func drain(config: Config) async {
        while let upload = state.pending.first {
            do {
                try await put(upload, config: config)
                state.pending.removeFirst()
                persist()
            } catch {
                // Oldest-first order preserved; drains next foreground (HB-05).
                return
            }
        }
    }

    /// `PUT /api/v1/athlete/{id}/wellness/{date}` with `weight` in kg, basic
    /// auth with the literal username `API_KEY` (HB-04). Idempotent per date.
    private func put(_ upload: WeightUpload, config: Config) async throws {
        let url = URL(string: "https://intervals.icu/api/v1")!
            .appending(path: "athlete/\(config.athleteID)/wellness/\(upload.date)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let credentials = Data("API_KEY:\(config.apiKey)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["weight": upload.weightKg ?? NSNull()]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Queue bound (HB-10)

    private func enforceQueueBound() {
        let (kept, evicted) = WeightUpload.bounded(state.pending, limit: Self.queueLimit)
        guard !evicted.isEmpty else { return }
        state.pending = kept
        let lines = evicted
            .map { "\($0.date) \($0.weightKg.map { String($0) } ?? "null")" }
            .joined(separator: "\n") + "\n"
        if let handle = try? FileHandle(forWritingTo: evictionLog) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(lines.utf8))
        } else {
            try? Data(lines.utf8).write(to: evictionLog)
        }
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: stateFile),
           let stored = try? JSONDecoder().decode(State.self, from: data) {
            state = stored
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateFile, options: .atomic)
        }
    }
}
