import Foundation

/// The slice of a favourite the quick-log surfaces need: enough to render a
/// widget and resolve a Siri pick back to the real `Favorite`. Published by
/// the app into the App Group whenever favourites change. The macros here are
/// display-only — the app re-resolves from SwiftData at log time, so an
/// edited favourite is never logged with stale values.
public struct FavoriteSnapshotItem: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var macros: Macros

    public init(id: UUID, name: String, macros: Macros) {
        self.id = id
        self.name = name
        self.macros = macros
    }
}

/// Reads and writes the shared favourites list. App writes, widget and the
/// App Intent's picker read — the same App-Group handoff as `TodaySnapshot`.
public enum FavoritesSnapshotStore {
    private static let key = "favorites_snapshot_v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedConstants.appGroupID)
    }

    public static func write(_ items: [FavoriteSnapshotItem]) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }

    public static func read() -> [FavoriteSnapshotItem] {
        guard let defaults,
              let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([FavoriteSnapshotItem].self, from: data)
        else { return [] }
        return items
    }
}
