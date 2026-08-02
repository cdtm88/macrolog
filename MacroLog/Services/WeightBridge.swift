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

    /// The ledger exists only so a deletion can recompute its day (HB-02/03);
    /// deletions arrive for recent samples, not multi-year history. Dropping
    /// samples older than the cutoff keeps the state file from growing — and
    /// being fully re-encoded — forever. A deletion of an already-pruned
    /// sample is simply unknown: no day recomputes, the upstream value stands.
    mutating func prune(olderThan cutoff: Date) {
        samples = samples.filter { $0.value.takenAt >= cutoff }
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

    /// Ledger retention: comfortably beyond the queue bound, so any day that
    /// could still be pending an upload can also still be recomputed.
    private static let ledgerRetentionDays = 400

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

    /// HB-08 gate, pure for testability: the read-permission prompt must
    /// arrive in context, not at first launch. HB-12 forbids any weight UI,
    /// so the only context this app has is proven use — the first-ever sync
    /// (the one that asks) waits until at least one meal has been confirmed.
    /// Once asked, every foreground syncs regardless: the local store purges
    /// written entries daily, so mornings legitimately start with none.
    static func shouldSync(authRequested: Bool, hasConfirmedMeal: Bool) -> Bool {
        authRequested || hasConfirmedMeal
    }

    /// The whole cycle: authorize (once, in context), read the delta, requeue
    /// changed days, drain. `onNotice` delivers the single HB-09 hint — the
    /// only thing this bridge ever says to the user.
    func syncOnForeground(hasConfirmedMeal: Bool,
                          onNotice: @escaping @Sendable (String) -> Void) async {
        guard config != nil, HKHealthStore.isHealthDataAvailable(), !syncing else { return }
        loadIfNeeded()
        guard Self.shouldSync(authRequested: state.authRequested,
                              hasConfirmedMeal: hasConfirmedMeal) else { return }
        syncing = true
        defer { syncing = false }

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
            state.ledger.prune(olderThan: Date(timeIntervalSinceNow:
                -Double(Self.ledgerRetentionDays) * 24 * 3600))
            enforceQueueBound()
            state.anchor = try? NSKeyedArchiver.archivedData(withRootObject: result.newAnchor,
                                                             requiringSecureCoding: true)
            persist()
            surfaceEmptyHintIfWarranted(onNotice: onNotice)
        } catch {
            // Read failures are silent; the anchor is unchanged so the next
            // foreground retries the same delta (HB-11).
        }

        await drain()
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

    /// HB-09 decision, pure for testability: whether to surface the notice
    /// and the flag's next value. An empty ledger after auth earns exactly
    /// one notice; seeing samples re-arms the flag, so a later revocation —
    /// whose silent empty reads drain the ledger via pruning — earns exactly
    /// one more, once per episode, never a nag.
    static func emptyHintTransition(authRequested: Bool, hintShown: Bool, ledgerEmpty: Bool)
        -> (notice: Bool, hintShown: Bool) {
        guard authRequested else { return (false, hintShown) }
        guard ledgerEmpty else { return (false, false) }
        return hintShown ? (false, true) : (true, true)
    }

    /// HealthKit hides read denial behind an empty result (the permission
    /// trap). If the ledger is empty when it shouldn't be, say so once per
    /// episode — one visible state change, never a repeated prompt (HB-09).
    private func surfaceEmptyHintIfWarranted(onNotice: @escaping @Sendable (String) -> Void) {
        let (notice, flag) = Self.emptyHintTransition(authRequested: state.authRequested,
                                                      hintShown: state.emptyHintShown,
                                                      ledgerEmpty: state.ledger.samples.isEmpty)
        if flag != state.emptyHintShown {
            state.emptyHintShown = flag
            persist()
        }
        guard notice else { return }
        onNotice("No weight readable from Health. If you use a smart scale, check MacroLog's read access under Settings › Health.")
    }

    // MARK: - Drain

    // Internal (not private) so tests can drive the drain deterministically
    // against a stubbed session, without going through HealthKit.
    func drain() async {
        guard let config else { return }
        loadIfNeeded()
        while let upload = state.pending.first {
            do {
                try await put(upload, config: config)
                state.pending.removeFirst()
                persist()
            } catch BridgeSendError.permanent(let status) {
                // Rejected outright (bad key, wrong athlete ID, invalid
                // value) — replay can never succeed, and leaving it at the
                // head would block every later weight forever. Log, drop,
                // keep draining. Still silent (HB-11).
                BridgeFiles.appendLog(["\(upload.date) \(upload.weightKg.map { String($0) } ?? "clear") dropped HTTP \(status)"],
                                      to: evictionLog)
                state.pending.removeFirst()
                persist()
            } catch {
                // Retryable (transport, timeout, 5xx, 408, 429): oldest-first
                // order preserved; drains next foreground (HB-05).
                return
            }
        }
    }

    /// `PUT /api/v1/athlete/{id}/wellness/{date}` with `weight` in kg, basic
    /// auth with the literal username `API_KEY` (HB-04). Idempotent per date.
    ///
    /// Clearing (every sample of a day deleted, HB-02) sends `-1`: verified
    /// against the live API on 2026-08-02 — `null` returns 200 but silently
    /// leaves the stored value unchanged, `0` is rejected with 422, and `-1`
    /// returns 200 and clears the field.
    private func put(_ upload: WeightUpload, config: Config) async throws {
        let url = URL(string: "https://intervals.icu/api/v1")!
            .appending(path: "athlete/\(config.athleteID)/wellness/\(upload.date)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let credentials = Data("API_KEY:\(config.apiKey)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["weight": upload.weightKg ?? -1]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw BridgeSendError.classify(status: http.statusCode)
        }
    }

    // MARK: - Queue bound (HB-10)

    private func enforceQueueBound() {
        let (kept, evicted) = WeightUpload.bounded(state.pending, limit: Self.queueLimit)
        guard !evicted.isEmpty else { return }
        state.pending = kept
        BridgeFiles.appendLog(evicted.map { "\($0.date) \($0.weightKg.map { String($0) } ?? "clear") evicted (queue bound)" },
                              to: evictionLog)
    }

    // MARK: - Test hooks

    func seedPending(_ uploads: [WeightUpload]) {
        loadIfNeeded()
        state.pending = uploads
        persist()
    }

    func pendingUploads() -> [WeightUpload] {
        loadIfNeeded()
        return state.pending
    }

    func hasRequestedAuthorization() -> Bool {
        loadIfNeeded()
        return state.authRequested
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
