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

    // Pending estimate awaiting review, surfaced on the capture view (REV-03).
    var pendingEntry: FoodEntry?

    // Feedback
    var estimationError: EstimationError?
    var healthError: HealthKitError?
    var toast: String?
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

    init(context: ModelContext) {
        self.context = context
        self.store = EntryStore(context: context)
    }

    // MARK: - Lifecycle

    func onLaunch() async {
        await requestHealthAuthorization()
        store.purgeOldWrittenEntries()
        recoverPendingEntry()
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

    /// Submits a free-text description (CAP-02).
    func submitText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastText = trimmed
        lastImage = nil
        isShowingText = false
        beginWork(capturedAt: Date()) { [estimator] in
            try await estimator.estimate(text: trimmed)
        }
    }

    /// Retries the last input after a recoverable error (EST-05, HK failures).
    func retryLast() {
        if let image = lastImage {
            submitPhoto(image)
        } else if let text = lastText {
            submitText(text)
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
                self.finishLongRunTimer()
                self.handleEstimate(estimate, capturedAt: capturedAt)
            } catch let error as EstimationError {
                self.finishLongRunTimer()
                self.handleEstimationError(error)
            } catch {
                self.finishLongRunTimer()
                self.handleEstimationError(.api(status: 0, message: error.localizedDescription))
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

    func openReview(for entry: FoodEntry, editingExisting: Bool) {
        // The review cover, the list sheet, and the text sheet all present from
        // the same view, and UIKit allows only one presentation at a time —
        // showing review while a sheet is up (list edit, or an estimate landing
        // with a sheet open) intermittently breaks the cover's layout. Dismiss
        // any open sheet first and wait out its animation before presenting.
        if isShowingList || isShowingText {
            isShowingList = false
            isShowingText = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                presentReview(for: entry, editingExisting: editingExisting)
            }
        } else {
            presentReview(for: entry, editingExisting: editingExisting)
        }
    }

    private func presentReview(for entry: FoodEntry, editingExisting: Bool) {
        isEditingExisting = editingExisting
        reviewImage = editingExisting ? nil : lastImage
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

    func adjustTime(_ entry: FoodEntry, byMinutes minutes: Int) {
        entry.capturedAt = entry.capturedAt.addingTimeInterval(Double(minutes) * 60)
    }

    /// Confirms the estimate and writes to Apple Health. No write happens until
    /// this point (REV-01). Leaves exactly one correlation (ENT-03).
    func confirm(_ entry: FoodEntry) {
        Task { await confirmAsync(entry) }
    }

    private func confirmAsync(_ entry: FoodEntry) async {
        guard healthState != .unavailable else {
            healthError = .unavailable
            return
        }
        do {
            let uuid = try await health.replace(entryID: entry.id,
                                                name: entry.name,
                                                macros: entry.macros,
                                                capturedAt: entry.capturedAt)
            entry.healthCorrelationID = uuid
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
