import Foundation
import HealthKit

enum HealthKitError: LocalizedError, Identifiable {
    var id: String { errorDescription ?? "hk" }

    /// Device has no HealthKit (e.g. iPad). Surface an explicit unsupported
    /// state rather than crashing (HK-05).
    case unavailable
    /// Write authorisation denied at the prompt. Direct the user to Settings
    /// (HK-07).
    case authorizationDenied
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "This device doesn't support Apple Health, so meals can't be logged here."
        case .authorizationDenied:
            return "MacroLog needs permission to write nutrition data. Enable it in Settings › Health › Data Access & Devices › MacroLog."
        case .writeFailed(let message):
            return "Couldn't write to Apple Health. \(message)"
        }
    }
}

/// Writes macros to Apple Health and keeps the Health record reconciled through
/// edits and deletes. Requests write access only — no read authorisation for any
/// type (SEC-02).
///
/// Reconciliation strategy: every quantity sample and the enclosing correlation
/// is tagged with the local entry's UUID in metadata. Deleting or replacing an
/// entry deletes every Health object carrying that tag. This guarantees the
/// underlying quantity samples — which are what actually sum into Whoop's daily
/// total — are removed, satisfying decision D-08, and needs no read access.
final class HealthKitService {
    static let entryIDMetadataKey = "MacroLogEntryID"

    private let store = HKHealthStore()

    private let energyType = HKQuantityType(.dietaryEnergyConsumed)
    private let proteinType = HKQuantityType(.dietaryProtein)
    private let carbsType = HKQuantityType(.dietaryCarbohydrates)
    private let fatType = HKQuantityType(.dietaryFatTotal)
    private let foodType = HKCorrelationType(.food)

    private var quantityTypes: [HKQuantityType] {
        [energyType, proteinType, carbsType, fatType]
    }

    /// Exactly the four write types the app is allowed to share (HK-01).
    private var shareTypes: Set<HKSampleType> {
        Set(quantityTypes.map { $0 as HKSampleType }) // correlation is composed of these
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    /// Requests write-only authorisation. `read:` is empty (SEC-02).
    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        try await store.requestAuthorization(toShare: shareTypes, read: [])
    }

    /// True when every write type is authorised. Used to route to the Settings
    /// path when the initial prompt was denied (HK-07).
    var isAuthorized: Bool {
        guard isAvailable else { return false }
        return quantityTypes.allSatisfy { store.authorizationStatus(for: $0) == .sharingAuthorized }
    }

    var isDenied: Bool {
        guard isAvailable else { return false }
        return quantityTypes.contains { store.authorizationStatus(for: $0) == .sharingDenied }
    }

    // MARK: - Write

    /// Writes one HKCorrelation of type `.food` containing the four quantity
    /// samples, timestamped to `capturedAt`, with the description as metadata
    /// (HK-02, HK-03, ENT-06). Reconciliation keys off the entry-ID metadata
    /// tag, so nothing needs to be returned (HK-04).
    func write(entryID: UUID, name: String, macros: Macros, capturedAt: Date) async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        guard !isDenied else { throw HealthKitError.authorizationDenied }

        let metadata: [String: Any] = [
            Self.entryIDMetadataKey: entryID.uuidString,
            HKMetadataKeyFoodType: name
        ]

        let samples: Set<HKSample> = [
            HKQuantitySample(type: energyType,
                             quantity: HKQuantity(unit: .kilocalorie(), doubleValue: macros.kcal),
                             start: capturedAt, end: capturedAt, metadata: metadata),
            HKQuantitySample(type: proteinType,
                             quantity: HKQuantity(unit: .gram(), doubleValue: macros.protein),
                             start: capturedAt, end: capturedAt, metadata: metadata),
            HKQuantitySample(type: carbsType,
                             quantity: HKQuantity(unit: .gram(), doubleValue: macros.carbs),
                             start: capturedAt, end: capturedAt, metadata: metadata),
            HKQuantitySample(type: fatType,
                             quantity: HKQuantity(unit: .gram(), doubleValue: macros.fat),
                             start: capturedAt, end: capturedAt, metadata: metadata)
        ]

        let correlation = HKCorrelation(type: foodType,
                                        start: capturedAt, end: capturedAt,
                                        objects: samples, metadata: metadata)
        do {
            try await store.save(correlation)
        } catch {
            throw HealthKitError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Delete / replace

    /// Deletes every Health object tagged with this entry's UUID: the four
    /// quantity samples and the correlation. Completes without error when
    /// nothing matches — e.g. the sample was already removed in the Health app
    /// (ENT-02, ENT-05).
    func delete(entryID: UUID) async throws {
        guard isAvailable else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.entryIDMetadataKey,
                                                    allowedValues: [entryID.uuidString])
        let types: [HKObjectType] = quantityTypes.map { $0 as HKObjectType } + [foodType as HKObjectType]
        for type in types {
            _ = try? await store.deleteObjects(of: type, predicate: predicate)
        }
    }

    /// Replaces an entry's Health record: delete the existing correlation and
    /// samples, then write fresh ones, leaving exactly one correlation for the
    /// entry (ENT-03).
    func replace(entryID: UUID, name: String, macros: Macros, capturedAt: Date) async throws {
        try await delete(entryID: entryID)
        try await write(entryID: entryID, name: name, macros: macros, capturedAt: capturedAt)
    }
}
