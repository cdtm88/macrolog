import Foundation

/// Where a `FoodEntry` sits in its lifecycle. Stored as a raw string in
/// SwiftData so the model stays trivially migratable.
enum EntryStatus: String, Codable, CaseIterable {
    /// Estimate returned and awaiting the user's review. Nothing has been
    /// written to Health; survives relaunches until reviewed (CAP-05).
    case pendingReview

    /// User confirmed, but the Health write failed. The entry is recoverable
    /// and offers retry; it is never silently treated as logged (HK-06).
    case unwritten

    /// Confirmed and successfully written to Apple Health as an HKCorrelation.
    case written
}
