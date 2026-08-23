import Foundation

/// One pending intervals.icu nutrition write: a day and its confirmed totals.
/// A day with no confirmed entries is never queued — the bridge writes nothing
/// for it — so this always carries real totals. Collapse and bounding come
/// from `DateKeyedUpload`.
struct NutritionUpload: Codable, Equatable, DateKeyedUpload {
    var date: String
    var totals: Macros
}

extension NutritionUpload {
    /// The wellness fields intervals.icu actually has (live-verified
    /// 2026-08-21): `kcalConsumed`, `protein`, `carbohydrates`, `fatTotal`.
    /// There is no fibre or sodium field, so those stay local.
    func payload() -> [String: Any] {
        ["kcalConsumed": Int(totals.kcal.rounded()),
         "protein": Int(totals.protein.rounded()),
         "carbohydrates": Int(totals.carbs.rounded()),
         "fatTotal": Int(totals.fat.rounded())]
    }
}

/// One-way daily nutrition totals sync: confirmed entries → intervals.icu
/// wellness, alongside the weight the same account already receives. Fully
/// inert until the intervals athlete ID and API key exist in the gitignored
/// config — the same pair that activates `WeightBridge`, no new keys.
///
/// Fed by the confirm/edit/delete paths (the entry's capture day is
/// recomputed and enqueued), never awaited there, with its own on-disk queue
/// draining on enqueue and on foreground launch — the CoachRelay pattern
/// (ARCH-01/02). The first launch after configuration backfills every
/// already-logged day, exactly once. The wellness PUT is a partial update,
/// so these writes never touch the weight field and vice versa.
actor NutritionBridge {
    typealias Config = IntervalsConfig

    /// Over a year of daily values queued before eviction (the HB-10 bound).
    private static let queueLimit = 366

    /// Everything persisted between launches, one JSON file: the pending
    /// queue plus the one-shot backfill marker.
    private struct State: Codable {
        var pending: [NutritionUpload] = []
        var backfilled = false
    }

    private let config: Config?
    private let session: URLSession
    private let queueFile: URL
    private let dropLog: URL

    private var state = State()
    private var loaded = false
    private var consecutiveFailures = 0
    private var retryTask: Task<Void, Never>?

    init(config: Config? = IntervalsConfig.load(),
         session: URLSession = .shared,
         queueFile: URL = BridgeFiles.url("nutrition-queue.json"),
         dropLog: URL = BridgeFiles.url("nutrition-drops.log")) {
        self.config = config
        self.session = session
        self.queueFile = queueFile
        self.dropLog = dropLog
    }

    // MARK: - Enqueue

    /// Records the current confirmed totals for one day. Idempotent per date —
    /// a re-send after an edit updates. Nil totals (the day has no confirmed
    /// entries) writes nothing upstream and drops any write already queued for
    /// the day — entries that were confirmed then deleted before the queue
    /// drained.
    func recordDay(date: String, totals: Macros?) {
        guard config != nil else { return }
        loadIfNeeded()
        if let totals {
            state.pending = state.pending.merging(NutritionUpload(date: date, totals: totals))
        } else {
            state.pending.removeAll { $0.date == date }
        }
        enforceQueueBound()
        persist()
        kick()
    }

    // MARK: - Backfill

    /// Whether the one-shot history backfill still has to run. False while
    /// unconfigured — an inert bridge must not trigger the (main-actor) store
    /// fetch that feeds `backfill`.
    func needsBackfill() -> Bool {
        guard config != nil else { return false }
        loadIfNeeded()
        return !state.backfilled
    }

    /// Enqueues every already-logged day exactly once — the first launch after
    /// the bridge is configured pushes all history, then the flag makes this a
    /// no-op forever. Oldest first; a date already queued by a confirm is
    /// replaced with the same store-derived totals, so nothing is lost.
    func backfill(_ days: [NutritionUpload]) {
        guard config != nil else { return }
        loadIfNeeded()
        guard !state.backfilled else { return }
        for day in days {
            state.pending = state.pending.merging(day)
        }
        state.backfilled = true
        enforceQueueBound()
        persist()
        kick()
    }

    // MARK: - Drain

    /// Called on foreground launch and after every enqueue. Resets any backoff
    /// wait so a fresh foreground always tries immediately.
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
        while let upload = state.pending.first {
            do {
                try await put(upload, config: config)
                state.pending.removeFirst()
                persist()
                consecutiveFailures = 0
            } catch BridgeSendError.permanent(let status) {
                // Rejected outright (bad key, wrong athlete ID, invalid
                // value) — replay can never succeed, and leaving it at the
                // head would block every later day forever. Log, drop, keep
                // draining. Still silent on the logging path.
                BridgeFiles.appendLog(["\(upload.date) \(Int(upload.totals.kcal.rounded())) kcal dropped HTTP \(status)"],
                                      to: dropLog)
                state.pending.removeFirst()
                persist()
            } catch {
                // Retryable (transport, timeout, 5xx, 408, 429): oldest-first
                // order preserved; back off and retry the whole queue later,
                // or on the next foreground kick.
                consecutiveFailures += 1
                scheduleRetry()
                return
            }
        }
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

    private func put(_ upload: NutritionUpload, config: Config) async throws {
        try await IntervalsAPI.putWellness(upload.payload(),
                                           date: upload.date,
                                           config: config,
                                           session: session)
    }

    // MARK: - Queue bound

    private func enforceQueueBound() {
        let (kept, evicted) = state.pending.bounded(limit: Self.queueLimit)
        guard !evicted.isEmpty else { return }
        state.pending = kept
        BridgeFiles.appendLog(evicted.map { "\($0.date) \(Int($0.totals.kcal.rounded())) kcal evicted (queue bound)" },
                              to: dropLog)
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: queueFile),
           let stored = try? JSONDecoder().decode(State.self, from: data) {
            state = stored
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: queueFile, options: .atomic)
        }
    }

    // MARK: - Test hooks

    func seedPending(_ uploads: [NutritionUpload]) {
        loadIfNeeded()
        state.pending = uploads
        persist()
    }

    // The queue as it would drain, oldest first.
    func queuedUploads() -> [NutritionUpload] {
        loadIfNeeded()
        return state.pending
    }
}
