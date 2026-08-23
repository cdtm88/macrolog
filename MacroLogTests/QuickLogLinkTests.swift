import Testing
import Foundation
@testable import MacroLog

/// The quick-log deep link: the widget builds it, the app parses it — one
/// round-trippable format, junk rejected.
struct QuickLogLinkTests {

    @Test func favoriteURLRoundTrips() {
        let id = UUID()
        let url = SharedConstants.favoriteURL(id: id)
        #expect(SharedConstants.favoriteID(from: url) == id)
    }

    @Test func nonFavoriteURLsAreRejected() {
        #expect(SharedConstants.favoriteID(from: SharedConstants.captureURL) == nil)
        #expect(SharedConstants.favoriteID(from: URL(string: "macrolog://favorite/not-a-uuid")!) == nil)
        #expect(SharedConstants.favoriteID(from: URL(string: "https://favorite/\(UUID().uuidString)")!) == nil)
    }

    @Test func snapshotItemsRoundTripThroughJSON() throws {
        let items = [FavoriteSnapshotItem(id: UUID(), name: "Usual breakfast",
                                          macros: Macros(kcal: 420.4, protein: 28, carbs: 44, fat: 14,
                                                         fiber: 6, sodium: 300)),
                     FavoriteSnapshotItem(id: UUID(), name: "Shake",
                                          macros: Macros(kcal: 180, protein: 30, carbs: 8, fat: 3))]
        let data = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([FavoriteSnapshotItem].self, from: data)
        #expect(decoded == items)
    }
}
