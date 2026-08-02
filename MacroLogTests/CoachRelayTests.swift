import Testing
import Foundation
@testable import MacroLog

/// The coach relay's wire contract and queue semantics (bridge spec MAC-01/02/03/08).
struct CoachRelayTests {

    private func date(hour: Int, minute: Int = 0) -> Date {
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        (parts.hour, parts.minute, parts.second) = (hour, minute, 0)
        return Calendar.current.date(from: parts)!
    }

    private func item(id: UUID = UUID(), hour: Int = 13, deleted: Bool = false) -> CoachMealItem {
        CoachMealItem(mealID: id, loggedAt: date(hour: hour),
                      kcal: 720.4, protein: 47.6, carbs: 61.2, fat: 28.1,
                      deleted: deleted)
    }

    @Test func mealTypeBucketsByLocalHour() {
        #expect(CoachMealItem.mealType(for: date(hour: 7)) == "breakfast")
        #expect(CoachMealItem.mealType(for: date(hour: 10)) == "breakfast")
        #expect(CoachMealItem.mealType(for: date(hour: 12)) == "lunch")
        #expect(CoachMealItem.mealType(for: date(hour: 15)) == "lunch")
        #expect(CoachMealItem.mealType(for: date(hour: 19)) == "dinner")
        #expect(CoachMealItem.mealType(for: date(hour: 23)) == "snack")
        #expect(CoachMealItem.mealType(for: date(hour: 3)) == "snack")
    }

    @Test func payloadCarriesExactlyTheSpecFields() throws {
        let id = UUID()
        let payload = item(id: id, hour: 13).payload()

        #expect(Set(payload.keys) == ["meal_id", "logged_at", "meal_type", "calories",
                                      "protein_g", "carbs_g", "fat_g", "deleted"])
        #expect(payload["meal_id"] as? String == id.uuidString.lowercased())
        #expect(payload["meal_type"] as? String == "lunch")
        #expect(payload["calories"] as? Int == 720)
        #expect(payload["protein_g"] as? Int == 48)
        #expect(payload["carbs_g"] as? Int == 61)
        #expect(payload["fat_g"] as? Int == 28)
        #expect(payload["deleted"] as? Bool == false)

        // Local-offset ISO 8601, parseable back to the same instant.
        let stamp = try #require(payload["logged_at"] as? String)
        #expect(CoachMealItem.timestampFormatter.date(from: stamp) != nil)

        // And it serialises — the payload must be valid JSON as-is.
        #expect(throws: Never.self) { try JSONSerialization.data(withJSONObject: payload) }
    }

    @Test func editCollapsesToOneQueuedStatePerMeal() {
        let id = UUID()
        var queue = CoachMealItem.merge([], with: item(id: id))
        var edited = item(id: id)
        edited.kcal = 900
        queue = CoachMealItem.merge(queue, with: edited)

        #expect(queue.count == 1)
        #expect(queue[0].kcal == 900)
    }

    @Test func deleteSupersedesQueuedUpsert() {
        let id = UUID()
        var queue = CoachMealItem.merge([], with: item(id: id))
        queue = CoachMealItem.merge(queue, with: item(id: id, deleted: true))

        #expect(queue.count == 1)
        #expect(queue[0].deleted)
    }

    @Test func distinctMealsQueueSeparately() {
        var queue = CoachMealItem.merge([], with: item())
        queue = CoachMealItem.merge(queue, with: item())
        // Per meal, never a daily aggregate (MAC-02).
        #expect(queue.count == 2)
    }
}
