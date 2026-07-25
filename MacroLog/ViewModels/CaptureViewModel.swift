import SwiftUI
import SwiftData
import UIKit

/// Drives the whole logging flow: capture → estimate → review → write to Health,
/// plus the entry list's edit and delete. One instance lives for the app's
/// lifetime, created in `RootView`.
@MainActor
@Observable
final class CaptureViewModel {

    enum CaptureState { case idle, working, ready }
    enum HealthState { case ok, unavailable, denied }

    // Flow
    var captureState: CaptureState = .idle
    var isShowingText = false
    var isShowingList = false

    /// The entry currently in review (either a fresh pending estimate or an
    /// existing entry being edited).
    var reviewEntry: FoodEntry?

    /// The photo behind the entry in review, shown as its thumbnail. Memory
    /// only — photos are never persisted (SEC-03), so an entry recovered after
    /// relaunch or edited from the list falls back to the placeholder.
    var reviewImage: UIImage?
    private var isEditingExisting = false

    /// Portion multiplier currently applied on the review screen, and the
    /// numbers it multiplies — frozen when review opens so factors don't
    /// compound (1× restores the original estimate).
    var portionFactor: Double = 1
    private var portionBaseline: Macros?

    // Pending estimate awaiting review, surfaced on the capture view (REV-03).
    var pendingEntry: FoodEntry?

    // Feedback
    var estimationError: EstimationError?
    var healthError: HealthKitError?
    var toast: String?

    /// True while a Health write is in flight. Guards the confirm button
    /// against double-taps racing two replace() calls into duplicate
    /// correlations (ENT-03).
    var isWriting = false
    var isTakingLong = false            // PERF-03: >20s still-working hint
    var needsTextAfterPhoto = false     // EST-04 prompt

    // Permissions / support
    var healthState: HealthState = .ok

    // Retained input so a failed estimate can be retried without re-capture
    // (EST-05). Not persisted — cleared once consumed (SEC-03).
    private var lastImage: UIImage?
    private var lastText: String?

    private let context: ModelContext
    private let store: EntryStore
    private let estimator = EstimationService()
    private let health = HealthKitService()

    private var workTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var longRunTask: Task<Void, Never>?

    /// Start-of-day the last purge/snapshot maintenance ran for. Lets foreground
    /// activation detect a midnight rollover without a cold launch.
    private var lastMaintenanceDayStart: Date?

    init(context: ModelContext) {
        self.context = context
        self.store = EntryStore(context: context)
    }

    // MARK: - Lifecycle

    func onLaunch() async {
        await requestHealthAuthorization()
        runDayMaintenance()
        recoverPendingEntry()
    }

    /// Called whenever the app returns to the foreground. iOS keeps the app
    /// resident for days, so day-boundary maintenance can't live only in
    /// `onLaunch` — after a midnight rollover this re-runs the purge and
    /// republishes the widget snapshot (ENT-04, WID-02). Also re-reads the
    /// Health permission state, which may have changed in Settings.
    func onBecameActive() {
        if health.isAvailable {
            healthState = health.isDenied ? .denied : .ok
        }
        let dayStart = Calendar.current.startOfDay(for: Date())
        guard dayStart != lastMaintenanceDayStart else { return }
        runDayMaintenance()
    }

    private func runDayMaintenance() {
        lastMaintenanceDayStart = Calendar.current.startOfDay(for: Date())
        store.purgeOldWrittenEntries()
        store.refreshTodaySnapshot()
    }

    private func requestHealthAuthorization() async {
        guard health.isAvailable else {
            healthState = .unavailable // HK-05
            return
        }
        do {
            try await health.requestAuthorization()
            healthState = health.isDenied ? .denied : .ok // HK-07
        } catch {
            healthState = health.isDenied ? .denied : .ok
        }
    }

    /// Recovers an estimate that was awaiting review when the app was last
    /// closed (CAP-05).
    private func recoverPendingEntry() {
        if let pending = store.pendingReviewEntry() {
            pendingEntry = pending
            captureState = .ready
        }
    }

    // MARK: - Capture / submit

    /// Submits a captured or library photo. Returns control immediately; the
    /// estimate resolves in the background (CAP-03, PERF-02).
    func submitPhoto(_ image: UIImage) {
        lastImage = image
        lastText = nil
        beginWork(capturedAt: Date()) { [estimator] in
            try await estimator.estimate(image: image)
        }
    }

    /// Submits a free-text description (CAP-02). When the text supplements an
    /// unidentifiable photo, the photo is re-sent alongside it — it still
    /// carries portion-size signal (EST-04).
    func submitText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let image = needsTextAfterPhoto ? lastImage : nil
        lastText = trimmed
        lastImage = image
        isShowingText = false
        beginWork(capturedAt: Date()) { [estimator] in
            try await estimator.estimate(text: trimmed, image: image)
        }
    }

    /// Logs a preconfigured favourite: no AI estimate, straight to review with
    /// the preset values (review-before-write still applies, REV-01).
    func submitFavorite(name: String, macros: Macros) {
        // Supersede any estimate in flight so it can't land on top of the
        // favourite's review and clobber the pending entry.
        workTask?.cancel()
        finishLongRunTimer()
        estimationError = nil
        needsTextAfterPhoto = false
        lastImage = nil
        lastText = nil
        let entry = FoodEntry(name: name,
                              macros: macros,
                              capturedAt: Date(),
                              status: .pendingReview)
        context.insert(entry)
        try? context.save()
        pendingEntry = entry
        captureState = .ready
        openReview(for: entry, editingExisting: false)
    }

    /// Clears the photo-fallback prompt when the text sheet is dismissed
    /// without submitting, so a later manual text entry starts clean.
    func textSheetDismissed() {
        if captureState != .working { needsTextAfterPhoto = false }
    }

    /// Retries the last input after a recoverable error (EST-05, HK failures).
    func retryLast() {
        if let text = lastText {
            let image = lastImage
            beginWork(capturedAt: Date()) { [estimator] in
                try await estimator.estimate(text: text, image: image)
            }
        } else if let image = lastImage {
            submitPhoto(image)
        }
    }

    private func beginWork(capturedAt: Date,
                           _ operation: @escaping () async throws -> MacroEstimate) {
        estimationError = nil
        needsTextAfterPhoto = false
        captureState = .working
        startLongRunTimer()

        workTask?.cancel()
        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                let estimate = try await operation()
                guard !Task.isCancelled else { return } // superseded by a newer submission
                self.finishLongRunTimer()
                self.handleEstimate(estimate, capturedAt: capturedAt)
            } catch {
                // A cancelled task was superseded by a newer submission — its
                // CancellationError/URLError must not surface as an alert.
                guard !Task.isCancelled else { return }
                self.finishLongRunTimer()
                let estimationError = (error as? EstimationError)
                    ?? .api(status: 0, message: error.localizedDescription)
                self.handleEstimationError(estimationError)
            }
        }
    }

    private func handleEstimate(_ estimate: MacroEstimate, capturedAt: Date) {
        // Persist a pending-review entry immediately so it survives termination
        // (CAP-05). Timestamped to capture, not to confirmation (ENT-06/D-11).
        let entry = FoodEntry(name: estimate.name,
                              macros: estimate.macros,
                              capturedAt: capturedAt,
                              status: .pendingReview)
        context.insert(entry)
        try? context.save()

        pendingEntry = entry
        captureState = .ready
        openReview(for: entry, editingExisting: false)
    }

    private func handleEstimationError(_ error: EstimationError) {
        captureState = .idle
        switch error {
        case .couldNotIdentify:
            // Prompt for a supplementary text description rather than guessing
            // (EST-04).
            needsTextAfterPhoto = true
            isShowingText = true
        default:
            estimationError = error
        }
    }

    // MARK: - Review

    /// Review request waiting for an open sheet to finish dismissing; presented
    /// from the sheet's `onDismiss` so sequencing is deterministic rather than
    /// timer-based.
    private var deferredReview: (entry: FoodEntry, editingExisting: Bool)?

    func openReview(for entry: FoodEntry, editingExisting: Bool) {
        // The review cover, the list sheet, and the text sheet all present from
        // the same view, and UIKit allows only one presentation at a time —
        // showing review while a sheet is up (list edit, or an estimate landing
        // with a sheet open) intermittently breaks the cover's layout. Dismiss
        // any open sheet first; the sheet's onDismiss presents the review once
        // the dismissal has actually completed.
        if isShowingList || isShowingText {
            deferredReview = (entry, editingExisting)
            isShowingList = false
            isShowingText = false
        } else {
            presentReview(for: entry, editingExisting: editingExisting)
        }
    }

    /// Hooked to every sheet's `onDismiss`: presents a review that was waiting
    /// for the sheet to finish dismissing.
    func sheetDidDismiss() {
        guard let deferred = deferredReview else { return }
        deferredReview = nil
        presentReview(for: deferred.entry, editingExisting: deferred.editingExisting)
    }

    private func presentReview(for entry: FoodEntry, editingExisting: Bool) {
        isEditingExisting = editingExisting
        reviewImage = editingExisting ? nil : lastImage
        portionBaseline = entry.macros
        portionFactor = 1
        reviewEntry = entry   // item-based presentation: setting this shows review
    }

    /// Re-open the pending estimate from the capture view without navigating
    /// away from it (REV-03).
    func openPendingReview() {
        guard let pending = pendingEntry else { return }
        openReview(for: pending, editingExisting: false)
    }

    func adjust(_ entry: FoodEntry, keyPath: WritableKeyPath<Macros, Double>, by delta: Double) {
        var macros = entry.macros
        macros[keyPath: keyPath] = max(0, macros[keyPath: keyPath] + delta)
        entry.macros = macros
    }

    /// Applies an absolute portion multiplier against the numbers the review
    /// opened with — non-compounding, so 1× always restores the original
    /// estimate (REV-02 convenience).
    func setPortion(_ entry: FoodEntry, factor: Double) {
        guard let base = portionBaseline else { return }
        portionFactor = factor
        entry.macros = Macros(kcal: max(0, (base.kcal * factor).rounded()),
                              protein: max(0, (base.protein * factor).rounded()),
                              carbs: max(0, (base.carbs * factor).rounded()),
                              fat: max(0, (base.fat * factor).rounded()))
    }

    /// Steps the capture time onto the five-minute grid: 10:13 steps down to
    /// 10:10, 10:05, … and up to 10:15, 10:20, … Only the sign of `minutes`
    /// matters; once on the grid each step is a full five minutes.
    func adjustTime(_ entry: FoodEntry, byMinutes minutes: Int) {
        let grid: TimeInterval = 5 * 60
        let t = entry.capturedAt.timeIntervalSinceReferenceDate
        let down = (t / grid).rounded(.down) * grid
        let up = (t / grid).rounded(.up) * grid
        let snapped = minutes < 0
            ? (t == down ? down - grid : down)
            : (t == up ? up + grid : up)
        entry.capturedAt = Date(timeIntervalSinceReferenceDate: snapped)
    }

    /// Confirms the estimate and writes to Apple Health. No write happens until
    /// this point (REV-01). Leaves exactly one correlation (ENT-03).
    func confirm(_ entry: FoodEntry) {
        Task { await confirmAsync(entry) }
    }

    private func confirmAsync(_ entry: FoodEntry) async {
        guard !isWriting else { return } // a write for this tap is already in flight
        guard healthState != .unavailable else {
            healthError = .unavailable
            return
        }
        isWriting = true
        defer { isWriting = false }
        do {
            try await health.replace(entryID: entry.id,
                                     name: entry.name,
                                     macros: entry.macros,
                                     capturedAt: entry.capturedAt)
            entry.status = .written
            entry.healthWriteFailures = 0
            try? context.save()

            showToast(entry.macroSummary)
            closeReviewToCapture()
            store.refreshTodaySnapshot()
        } catch {
            // Never silently mark as logged (HK-06). Escalate after two
            // consecutive failures (HK-08).
            entry.status = .unwritten
            entry.healthWriteFailures += 1
            try? context.save()
            if let hkError = error as? HealthKitError, case .authorizationDenied = hkError {
                healthState = .denied
            }
            healthError = (error as? HealthKitError) ?? .writeFailed(error.localizedDescription)
            closeReviewToCapture()
            store.refreshTodaySnapshot()
        }
    }

    /// Discards the estimate at review: writes nothing to Health and removes the
    /// pending entry (REV-04).
    func discard(_ entry: FoodEntry) {
        if !isEditingExisting {
            context.delete(entry)
            try? context.save()
            if pendingEntry?.id == entry.id { pendingEntry = nil }
        }
        closeReviewToCapture()
    }

    private func closeReviewToCapture() {
        reviewEntry = nil
        reviewImage = nil
        if !isEditingExisting { pendingEntry = nil; captureState = .idle }
        isEditingExisting = false
    }

    // MARK: - Entry list edit / delete

    func beginEdit(_ entry: FoodEntry) {
        openReview(for: entry, editingExisting: true)
    }

    /// Deletes an entry and its Health correlation (ENT-02). Completes cleanly
    /// even if the sample is already gone (ENT-05).
    func delete(_ entry: FoodEntry) {
        Task {
            try? await health.delete(entryID: entry.id)
            context.delete(entry)
            try? context.save()
            if pendingEntry?.id == entry.id {
                pendingEntry = nil
                captureState = .idle
            }
            store.refreshTodaySnapshot()
        }
    }

    /// Retry a failed Health write for an unwritten entry (HK-06).
    func retryWrite(_ entry: FoodEntry) {
        Task { await confirmAsync(entry) }
    }

    // MARK: - Derived data for views

    func todaysEntries() -> [FoodEntry] { store.todaysConfirmedEntries() }

    func todaysTotals() -> Macros {
        store.todaysConfirmedEntries().reduce(Macros.zero) { $0 + $1.macros }
    }

    var showPermissionEscalation: Bool {
        healthState == .denied ||
        (reviewEntry?.healthWriteFailures ?? 0) >= 2
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            self?.toast = nil
        }
    }

    // MARK: - Long-running hint

    private func startLongRunTimer() {
        isTakingLong = false
        longRunTask?.cancel()
        longRunTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            if !Task.isCancelled { self?.isTakingLong = true }
        }
    }

    private func finishLongRunTimer() {
        longRunTask?.cancel()
        isTakingLong = false
    }
}

extension FoodEntry {
    var macroSummary: String {
        "\(name) · \(Int(protein.rounded()))p \(Int(carbs.rounded()))c \(Int(fat.rounded()))f"
    }
}
