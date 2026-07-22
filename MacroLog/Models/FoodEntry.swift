import Foundation
import SwiftData

/// A single logged eating occasion. This is the only persisted model in the app
/// (PRD decision D-02): SwiftData holds today's entries plus any pending or
/// unwritten items, and nothing else.
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

    /// Moment the meal was captured — photo taken or text submitted — NOT the
    /// moment of review confirmation. This is what the Health sample is
    /// timestamped to (ENT-06, decision D-11), so a late dinner confirmed after
    /// midnight still lands on the capture day.
    var capturedAt: Date

    /// Raw value of `EntryStatus`.
    var statusRaw: String

    /// UUID of the HKCorrelation once written, so the sample can later be
    /// deleted or replaced (HK-04, ENT-02, ENT-03). Nil until a successful
    /// write.
    var healthCorrelationID: UUID?

    /// Count of consecutive failed Health writes, used to escalate to a
    /// "check Health permissions" path after two failures (HK-08).
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
        self.capturedAt = capturedAt
        self.statusRaw = status.rawValue
        self.healthCorrelationID = nil
        self.healthWriteFailures = 0
    }

    var status: EntryStatus {
        get { EntryStatus(rawValue: statusRaw) ?? .pendingReview }
        set { statusRaw = newValue.rawValue }
    }

    var macros: Macros {
        get { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
        set {
            kcal = newValue.kcal
            protein = newValue.protein
            carbs = newValue.carbs
            fat = newValue.fat
        }
    }
}
