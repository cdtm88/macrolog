import AppIntents
import Foundation

/// A favourite as the intent system sees it — Siri's picker, Shortcuts, and
/// the widget's edit sheet. Backed by the App-Group snapshot so it resolves
/// in both processes without opening the SwiftData store. Compiled into the
/// app and the widget extension; each process resolves against the same
/// snapshot.
public struct FavoriteEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Favourite"
    public static let defaultQuery = FavoriteEntityQuery()

    public let id: UUID
    public let name: String
    public let kcal: Double

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)",
                              subtitle: "\(Int(kcal.rounded())) kcal")
    }

    public init(item: FavoriteSnapshotItem) {
        self.id = item.id
        self.name = item.name
        self.kcal = item.macros.kcal
    }
}

public struct FavoriteEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [FavoriteEntity] {
        FavoritesSnapshotStore.read()
            .filter { identifiers.contains($0.id) }
            .map(FavoriteEntity.init)
    }

    public func suggestedEntities() async throws -> [FavoriteEntity] {
        FavoritesSnapshotStore.read().map(FavoriteEntity.init)
    }

    /// A fresh widget defaults to the first favourite instead of an empty
    /// picker.
    public func defaultResult() async -> FavoriteEntity? {
        FavoritesSnapshotStore.read().first.map(FavoriteEntity.init)
    }
}

/// The quick-log widget's configuration: which favourite this instance logs.
/// Nil (never configured, or the favourite was deleted) falls back to the
/// first favourite at timeline time.
public struct SelectFavoriteIntent: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Choose Favourite"
    public static let description = IntentDescription(
        "Pick which favourite meal this widget logs.")

    @Parameter(title: "Favourite")
    public var favorite: FavoriteEntity?

    public init() {}
}
