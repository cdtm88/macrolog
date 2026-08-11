import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import WidgetKit

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
    var isShowingSettings = false

    /// The entry currently in review (either a fresh pending estimate or an
    /// existing entry being edited).
    var reviewEntry: FoodEntry?

    /// The photo behind the entry in review, shown as its thumbnail. Memory
    /// only — photos are never persisted (SEC-03), so an entry recovered after
    /// relaunch or edited from the list falls back to the placeholder.
    var reviewImage: UIImage?
    private var isEditingExisting = false

    /// Portion multiplier currently applied on the review screen.
    var portionFactor: Double = 1

    /// The values the entry had when review opened. Serves two jobs: the
    /// portion multiplier scales against it (so factors don't compound), and
    /// discarding an *edit* of an existing entry restores it — steppers mutate
    /// the autosaving SwiftData model in place, so without a restore "Discard"
    /// would silently keep the edits while Health still holds the old values
    /// (D-08: local and Health must never diverge).
    private var reviewBaseline: (macros: Macros, capturedAt: Date)?

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
    // (EST-05). Not persisted — cleared once consumed (SEC-03). Both are
    // readable: the capture view shows `lastImage` as the static frame behind
    // the working overlay and the text sheet reseeds from `lastText` after a
    // failure, so nothing has to be re-captured or retyped (CAP-05).
    private(set) var lastImage: UIImage?
    private(set) var lastText: String?

    private let context: ModelContext
    private let store: EntryStore
    private let estimator = EstimationService()
    private let health = HealthKitService()

    // Outbound bridges (bridge spec P06/P07). Both are inert without their
    // config keys; neither is ever awaited on the logging path (ARCH-02).
    private let coachRelay = CoachRelay()
    private let weightBridge = WeightBridge()

    /// Executes the reminder plan. Inert until reminders are enabled in
    /// settings; its permission prompt fires only from the settings toggle.
    private let reminders = ReminderScheduler()

    /// One-time bridge hint (HB-09) — the only thing a bridge may ever say.
    var bridgeNotice: String?
    private var bridgeNoticeTask: Task<Void, Never>?

    // Readable (not private) so tests can cancel it and drive the
    // estimation-outcome handlers deterministically without network.
    private(set) var workTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var longRunTask: Task<Void, Never>?

    /// Start-of-day the last snapshot maintenance ran for. Lets foreground
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
        kickBridges()
        rearmReminders()
    }

    /// Called whenever the app returns to the foreground. iOS keeps the app
    /// resident for days, so day-boundary maintenance can't live only in
    /// `onLaunch` — after a midnight rollover this republishes the widget
    /// snapshot for the new day (WID-02). Also re-reads the
    /// Health permission state, which may have changed in Settings.
    func onBecameActive() {
        if health.isAvailable {
            healthState = health.isDenied ? .denied : .ok
        }
        kickBridges()
        // Every foreground: tops the 7-day horizon back up, clears delivered
        // banners, and refreshes suppression against today's entries.
        rearmReminders()
        let dayStart = Calendar.current.startOfDay(for: Date())
        guard dayStart != lastMaintenanceDayStart else { return }
        runDayMaintenance()
    }

    /// Foreground drain for both outbound queues (MAC-06, HB-01/05). Detached
    /// fire-and-forget: nothing here can block or delay the UI (HB-11).
    /// The confirmed-meal flag gates only the weight bridge's *first* sync,
    /// so its read-permission prompt lands after the app has proven itself
    /// rather than back-to-back with the nutrition prompt at first launch
    /// (HB-08).
    private func kickBridges() {
        Task { [coachRelay] in await coachRelay.kick() }
        let hasConfirmedMeal = !store.todaysConfirmedEntries().isEmpty
        Task { [weightBridge] in
            await weightBridge.syncOnForeground(hasConfirmedMeal: hasConfirmedMeal) { [weak self] notice in
                Task { @MainActor in self?.showBridgeNotice(notice) }
            }
        }
    }

    /// Republishes the widget snapshot for the new day. Entries are no longer
    /// purged at the boundary — history is retained for the day-paged list
    /// (2026-08-05, supersedes ENT-04).
    private func runDayMaintenance() {
        lastMaintenanceDayStart = Calendar.current.startOfDay(for: Date())
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

    /// Clears the photo-fallback prompt and any failure context when the text
    /// sheet is dismissed without submitting, so a later manual text entry
    /// starts clean.
    func textSheetDismissed() {
        if captureState != .working {
            needsTextAfterPhoto = false
            estimationError = nil
        }
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

    // Internal (not private) so tests can drive estimation outcomes without
    // touching the network.
    func handleEstimate(_ estimate: MacroEstimate, capturedAt: Date) {
        // The description served its purpose — don't let it leak into an
        // unrelated later text entry. The image stays: review shows it.
        lastText = nil

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

    func handleEstimationError(_ error: EstimationError) {
        captureState = .idle
        switch error {
        case .couldNotIdentify:
            // Prompt for a supplementary text description rather than guessing
            // (EST-04).
            needsTextAfterPhoto = true
            isShowingText = true
        default:
            // Every other failure reopens the text sheet with the cause shown
            // and the input retained: a failed photo keeps its photo (so a
            // description typed here is submitted alongside it), a failed text
            // entry reseeds the field for editing instead of a retype (EST-05).
            needsTextAfterPhoto = lastImage != nil
            estimationError = error
            isShowingText = true
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
        reviewBaseline = (entry.macros, entry.capturedAt)
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
        guard let base = reviewBaseline?.macros else { return }
        portionFactor = factor
        entry.macros = Macros(kcal: max(0, (base.kcal * factor).rounded()),
                              protein: max(0, (base.protein * factor).rounded()),
                              carbs: max(0, (base.carbs * factor).rounded()),
                              fat: max(0, (base.fat * factor).rounded()),
                              fiber: max(0, (base.fiber * factor).rounded()),
                              sodium: max(0, (base.sodium * factor).rounded()))
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

    // Internal (not private) so tests can await the full confirm path.
    func confirmAsync(_ entry: FoodEntry) async {
        guard !isWriting else { return } // a write for this tap is already in flight
        guard healthState != .unavailable else {
            healthError = .unavailable
            return
        }

        // Relay to the coach the moment the meal is confirmed (MAC-01) —
        // fire and forget, never awaited, independent of the Health write's
        // outcome (MAC-05/07). Re-confirming an edit reuses the entry ID, so
        // upstream updates rather than duplicates (MAC-03/08).
        let relayed = (id: entry.id, at: entry.capturedAt, macros: entry.macros)
        Task { [coachRelay] in
            await coachRelay.recordConfirmation(mealID: relayed.id,
                                                loggedAt: relayed.at,
                                                macros: relayed.macros)
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

            lastText = nil // the retained description can't outlive its entry
            showToast(entry.macroSummary)
            closeReviewToCapture()
            store.refreshTodaySnapshot()
            rearmReminders()
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
            // An .unwritten entry still counts toward today — suppression and
            // shortfall copy must reflect it.
            rearmReminders()
        }
    }

    /// Discards at review (REV-04). A *new* pending entry is deleted outright.
    /// An *existing* entry being edited is restored to the values review opened
    /// with — the steppers mutate the autosaving model in place, so without
    /// this restore the local copy would silently diverge from the Health
    /// sample (D-08) while the button claims nothing changed.
    func discard(_ entry: FoodEntry) {
        if isEditingExisting {
            if let baseline = reviewBaseline {
                entry.macros = baseline.macros
                entry.capturedAt = baseline.capturedAt
                try? context.save()
                // Totals shown on capture/list/widget included the edits.
                store.refreshTodaySnapshot()
                rearmReminders()
            }
        } else {
            context.delete(entry)
            try? context.save()
            if pendingEntry?.id == entry.id { pendingEntry = nil }
        }
        closeReviewToCapture()
    }

    private func closeReviewToCapture() {
        reviewEntry = nil
        reviewImage = nil
        reviewBaseline = nil
        if !isEditingExisting {
            pendingEntry = nil
            captureState = .idle
            // The photo has served its purpose once its review closes — drop
            // the few MB rather than hold it for the app's lifetime. Estimation
            // failures never reach here, so retry-after-failure (EST-05) still
            // has it. The editing branch keeps it: an unrelated estimate may
            // still be pending underneath the edit.
            lastImage = nil
        }
        isEditingExisting = false
    }

    // MARK: - Entry list edit / delete

    func beginEdit(_ entry: FoodEntry) {
        openReview(for: entry, editingExisting: true)
    }

    /// Deletes an entry and its Health correlation (ENT-02). Completes cleanly
    /// even if the sample is already gone (ENT-05).
    func delete(_ entry: FoodEntry) {
        // Only confirmed entries reach this path (pending ones go through
        // discard), so the coach heard about this meal — send the delete
        // under the same ID (MAC-03), fire and forget.
        let relayed = (id: entry.id, at: entry.capturedAt, macros: entry.macros)
        Task { [coachRelay] in
            await coachRelay.recordDeletion(mealID: relayed.id,
                                            loggedAt: relayed.at,
                                            macros: relayed.macros)
        }
        Task {
            try? await health.delete(entryID: entry.id)
            context.delete(entry)
            try? context.save()
            if pendingEntry?.id == entry.id {
                pendingEntry = nil
                captureState = .idle
            }
            store.refreshTodaySnapshot()
            rearmReminders()
        }
    }

    /// Retry a failed Health write for an unwritten entry (HK-06).
    func retryWrite(_ entry: FoodEntry) {
        Task { await confirmAsync(entry) }
    }

    // MARK: - Save as favourite

    enum FavoriteSaveResult { case saved, updated, full }

    /// Saves a logged meal's values as a one-tap favourite (swipe action on
    /// the day list). A name match (case-insensitive) updates that favourite's
    /// macros instead of duplicating it; otherwise the meal is appended,
    /// subject to `Favorite.maxCount`.
    @discardableResult
    func saveAsFavorite(_ entry: FoodEntry) -> FavoriteSaveResult {
        let favorites = (try? context.fetch(FetchDescriptor<Favorite>())) ?? []
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = favorites.first(where: {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            existing.macros = entry.macros
            try? context.save()
            return .updated
        }
        guard favorites.count < Favorite.maxCount else { return .full }
        let nextOrder = (favorites.map(\.sortOrder).max() ?? -1) + 1
        context.insert(Favorite(name: name, macros: entry.macros, sortOrder: nextOrder))
        try? context.save()
        return .saved
    }

    // MARK: - Derived data for views

    /// Writes all-history daily totals to a temp CSV and returns its URL for
    /// the settings sheet's ShareLink; nil when the write fails.
    func dailyTotalsExportURL() -> URL? {
        let csv = DailyTotalsExport.csv(days: store.allConfirmedDailyTotals())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacroLog-daily-totals.csv")
        do {
            try Data(csv.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    func todaysEntries() -> [FoodEntry] { store.todaysConfirmedEntries() }

    /// Earliest day reachable in the day-paged list.
    func earliestDayStart() -> Date { store.earliestConfirmedDayStart() }

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

    // MARK: - Bridge notice (HB-09)

    private func showBridgeNotice(_ message: String) {
        bridgeNotice = message
        bridgeNoticeTask?.cancel()
        bridgeNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.bridgeNotice = nil
        }
    }

    // MARK: - Meal reminders / settings

    /// Recomputes the pending reminder set (pure planner) and hands it to the
    /// scheduler as a detached fire-and-forget task — like the bridges, never
    /// awaited on the logging path. Covers both families: meal reminders and
    /// the daily protein check.
    private func rearmReminders() {
        let entries = store.todaysConfirmedEntries()
        let todayProtein = entries.reduce(0) { $0 + $1.protein }
        let proteinTarget = SettingsStore.proteinTarget()
        let mealPlan = ReminderPlanner.plan(
            enabled: SettingsStore.remindersEnabled(),
            times: SettingsStore.reminderTimes(),
            todayEntryTimes: entries.map(\.capturedAt),
            todayProtein: todayProtein,
            proteinTarget: proteinTarget)
        let proteinPlan = ReminderPlanner.proteinPlan(
            enabled: SettingsStore.proteinReminderEnabled(),
            timeMinutes: SettingsStore.proteinReminderTime(),
            todayProtein: todayProtein,
            proteinTarget: proteinTarget)
        Task { [reminders] in await reminders.sync(plan: mealPlan + proteinPlan) }
    }

    /// Hooked to the settings sheet's `onDismiss`: settings may have changed,
    /// so re-arm reminders and refresh the widget (it reads the protein target
    /// directly from the shared defaults).
    func settingsSheetDismissed() {
        rearmReminders()
        WidgetCenter.shared.reloadAllTimelines()
        sheetDidDismiss()
    }

    /// Turns meal reminders on. Returns whether notifications are actually
    /// authorized (drives the settings sheet's warning row).
    func enableReminders() async -> Bool {
        let authorized = await ensureReminderAuthorization()
        SettingsStore.setRemindersEnabled(true)
        if SettingsStore.reminderTimes().isEmpty {
            SettingsStore.setReminderTimes([12 * 60 + 30, 19 * 60]) // 12:30, 19:00
        }
        rearmReminders()
        return authorized
    }

    func disableReminders() {
        SettingsStore.setRemindersEnabled(false)
        rearmReminders() // empty plan → clears pending requests
    }

    /// Turns the daily protein check on — same authorization path as the meal
    /// toggle.
    func enableProteinReminder() async -> Bool {
        let authorized = await ensureReminderAuthorization()
        SettingsStore.setProteinReminderEnabled(true)
        rearmReminders()
        return authorized
    }

    func disableProteinReminder() {
        SettingsStore.setProteinReminderEnabled(false)
        rearmReminders()
    }

    /// The notification permission prompt fires here and only here — from a
    /// settings toggle, never at launch, so it can't stack onto the HealthKit
    /// prompt.
    private func ensureReminderAuthorization() async -> Bool {
        switch await reminders.authorizationStatus() {
        case .notDetermined:
            return await reminders.requestAuthorization()
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    func reminderAuthorizationStatus() async -> UNAuthorizationStatus {
        await reminders.authorizationStatus()
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
