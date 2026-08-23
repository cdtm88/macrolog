import WidgetKit
import SwiftUI
import AppIntents

/// Quick-log widget: one favourite per instance, chosen in the widget's edit
/// sheet (`SelectFavoriteIntent`); unconfigured instances fall back to the
/// first favourite. A tap deep-links into the app's review screen with that
/// favourite pre-filled — the widget never writes anything itself
/// (review-before-write, REV-01). Neutrals are semantic so the widget follows
/// the Home Screen appearance.
struct FavoritesEntry: TimelineEntry {
    let date: Date
    let favorite: FavoriteSnapshotItem?
}

struct FavoritesProvider: AppIntentTimelineProvider {
    static let placeholderItem = FavoriteSnapshotItem(
        id: UUID(), name: "Usual breakfast",
        macros: Macros(kcal: 420, protein: 28, carbs: 44, fat: 14))

    /// The configured favourite, re-read from the snapshot so an edited name
    /// or value shows current; a deleted one falls back to the first.
    private func resolve(_ configuration: SelectFavoriteIntent) -> FavoriteSnapshotItem? {
        let items = FavoritesSnapshotStore.read()
        if let id = configuration.favorite?.id,
           let match = items.first(where: { $0.id == id }) {
            return match
        }
        return items.first
    }

    func placeholder(in context: Context) -> FavoritesEntry {
        FavoritesEntry(date: Date(), favorite: Self.placeholderItem)
    }

    func snapshot(for configuration: SelectFavoriteIntent, in context: Context) async -> FavoritesEntry {
        let favorite = resolve(configuration) ?? (context.isPreview ? Self.placeholderItem : nil)
        return FavoritesEntry(date: Date(), favorite: favorite)
    }

    func timeline(for configuration: SelectFavoriteIntent, in context: Context) async -> Timeline<FavoritesEntry> {
        // No time-driven content: the app reloads this widget whenever the
        // favourites change.
        Timeline(entries: [FavoritesEntry(date: Date(), favorite: resolve(configuration))],
                 policy: .never)
    }
}

struct FavoritesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FavoritesEntry

    var body: some View {
        Group {
            if let favorite = entry.favorite {
                if family == .systemSmall {
                    small(favorite)
                } else {
                    medium(favorite)
                }
            } else {
                emptyState
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(entry.favorite.map { SharedConstants.favoriteURL(id: $0.id) }
                   ?? SharedConstants.captureURL)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "star")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Add favourites in MacroLog for one-tap logging.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func small(_ favorite: FavoriteSnapshotItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 6)
            Text(favorite.name)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text("\(Int(favorite.macros.kcal.rounded())) kcal")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ favorite: FavoriteSnapshotItem) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 6)
                Text(favorite.name)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text("\(Int(favorite.macros.kcal.rounded())) kcal")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                macroValue("P", favorite.macros.protein, W.protein)
                macroValue("C", favorite.macros.carbs, W.carbs)
                macroValue("F", favorite.macros.fat, W.fat)
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
            Text("QUICK LOG")
                .font(.system(size: 10, weight: .bold)).tracking(0.6)
                .foregroundStyle(.secondary)
        }
    }

    private func macroValue(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text("\(Int(value.rounded()))g")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct FavoritesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SharedConstants.favoritesWidgetKind,
                               intent: SelectFavoriteIntent.self,
                               provider: FavoritesProvider()) { entry in
            FavoritesWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Log")
        .description("One tap opens a favourite meal ready to confirm. Choose the favourite by editing the widget.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview("Medium", as: .systemMedium) {
    FavoritesWidget()
} timeline: {
    FavoritesEntry(date: .now, favorite: FavoritesProvider.placeholderItem)
}

#Preview("Small", as: .systemSmall) {
    FavoritesWidget()
} timeline: {
    FavoritesEntry(date: .now, favorite: FavoritesProvider.placeholderItem)
    FavoritesEntry(date: .now, favorite: nil)
}
