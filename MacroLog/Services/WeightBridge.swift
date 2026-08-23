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

    /// Applies one anchored-query delta and returns the day keys whose value
    /// may have changed, oldest first.
    mutating func apply(added: [(uuid: UUID, takenAt: Date, weightKg: Double)],
                        deleted: [UUID],
                        calendar: Calendar = .current) -> [String] {
        var changed = Set<String>()
        for sample in added {
            let day = BridgeDay.key(for: sample.takenAt, calendar: calendar)
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
    /// when every sample for the day has been deleted — in which case the
    /// bridge writes nothing for that day (HB-02).
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

/// One pending intervals.icu write: a day and the weight Health holds for it.
/// A day with no sample is never queued — the bridge writes nothing for it —
/// so this is always a concrete value. Collapse and bounding come from
/// `DateKeyedUpload` (HB-10).
struct WeightUpload: Codable, Equatable, DateKeyedUpload {
    var date: String
    var weightKg: Double
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
    typealias Config = IntervalsConfig

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

    init(config: Config? = IntervalsConfig.load(),
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
    /// Once asked, every foreground syncs regardless: the meal check covers
    /// today only, so mornings legitimately start with none.
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
                if let weight = state.ledger.value(forDay: day) {
                    state.pending = state.pending.merging(WeightUpload(date: day, weightKg: weight))
                } else {
                    // No sample dated that day: write nothing (HB-02), and drop
                    // any write already queued for it — a reading that was added
                    // then deleted before the queue drained.
                    state.pending.removeAll { $0.date == day }
                }
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
                BridgeFiles.appendLog(["\(upload.date) \(upload.weightKg) dropped HTTP \(status)"],
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

    /// Only days Health actually holds a sample for are ever queued (HB-02), so
    /// every write carries a real weight — the bridge never clears a day upstream.
    private func put(_ upload: WeightUpload, config: Config) async throws {
        try await IntervalsAPI.putWellness(["weight": upload.weightKg],
                                           date: upload.date,
                                           config: config,
                                           session: session)
    }

    // MARK: - Queue bound (HB-10)

    private func enforceQueueBound() {
        let (kept, evicted) = state.pending.bounded(limit: Self.queueLimit)
        guard !evicted.isEmpty else { return }
        state.pending = kept
        BridgeFiles.appendLog(evicted.map { "\($0.date) \($0.weightKg) evicted (queue bound)" },
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
