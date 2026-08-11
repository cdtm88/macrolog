import Foundation
import SwiftData

/// A single logged eating occasion. This is the only entry model in the app
/// (PRD decision D-02): SwiftData retains every confirmed entry indefinitely
/// for the day-paged history (2026-08-05, superseding the original
/// today-only retention) plus any pending or unwritten items. Photos are
/// never persisted (SEC-03), so the store stays tiny.
@Model
final class FoodEntry {
    /// Stable identity, also used as the local <-> Health reconciliation key in
    /// logs.
    @Attribute(.unique) var id: UUID

    /// Free-text meal description. Shown in the entry list and attached to the
    /// Health correlation as metadata (HK-03).
    var name: String

    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// Grams. Defaults keep pre-fibre/sodium stores migrating cleanly.
    var fiber: Double = 0
    /// Milligrams.
    var sodium: Double = 0

    /// Moment the meal was captured — photo taken or text submitted — NOT the
    /// moment of review confirmation. This is what the Health sample is
    /// timestamped to (ENT-06, decision D-11), so a late dinner confirmed after
    /// midnight still lands on the capture day.
    var capturedAt: Date

    /// Raw value of `EntryStatus`.
    var statusRaw: String

    /// Count of consecutive failed Health writes, used to escalate to a
    /// "check Health permissions" path after two failures (HK-08).
    ///
    /// Note: Health reconciliation (HK-04, ENT-02/03) keys off this entry's
    /// `id`, tagged into every Health sample's metadata — see
    /// `HealthKitService` — so no correlation UUID needs to be stored here.
    var healthWriteFailures: Int

    init(id: UUID = UUID(),
         name: String,
         macros: Macros,
         capturedAt: Date,
         status: EntryStatus = .pendingReview) {
        self.id = id
        self.name = name
        self.kcal = macros.kcal
        self.protein = macros.protein
        self.carbs = macros.carbs
        self.fat = macros.fat
        self.fiber = macros.fiber
        self.sodium = macros.sodium
        self.capturedAt = capturedAt
        self.statusRaw = status.rawValue
        self.healthWriteFailures = 0
    }

    var status: EntryStatus {
        get { EntryStatus(rawValue: statusRaw) ?? .pendingReview }
        set { statusRaw = newValue.rawValue }
    }

    var macros: Macros {
        get { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat, fiber: fiber, sodium: sodium) }
        set {
            kcal = newValue.kcal
            protein = newValue.protein
            carbs = newValue.carbs
            fat = newValue.fat
            fiber = newValue.fiber
            sodium = newValue.sodium
        }
    }
}
