import WidgetKit
import SwiftUI

// Widget brand hues (kept local — the widget target doesn't link the app's
// Theme). Only the three macro colours are fixed; every neutral is semantic so
// the widget follows the Home Screen appearance — the app's forced-light
// UIUserInterfaceStyle does not apply to an extension.
private enum W {
    static let protein = Color(red: 0.0, green: 0.478, blue: 1.0)
    static let carbs   = Color(red: 1.0, green: 0.584, blue: 0.0)
    static let fat     = Color(red: 0.686, green: 0.322, blue: 0.871)
}

struct MacroEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> MacroEntry {
        MacroEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (MacroEntry) -> Void) {
        completion(MacroEntry(date: Date(), snapshot: TodaySnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacroEntry>) -> Void) {
        let entry = MacroEntry(date: Date(), snapshot: TodaySnapshotStore.read())
        // Refresh at next local midnight so totals reset to zero for the new day
        // even if the app hasn't run (WID-04). Live updates come from the app's
        // WidgetCenter reload on each confirmed entry (WID-02).
        let nextMidnight = Calendar.current.nextDate(after: Date(),
                                                     matching: DateComponents(hour: 0, minute: 0),
                                                     matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MacroEntry

    private var totals: Macros { entry.snapshot.totals }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            default: medium
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(SharedConstants.captureURL) // tap opens capture (WID-03)
    }

    // The calorie readout lives inside the ring only — no duplicate label.
    private var small: some View {
        WidgetRing(macros: totals, size: 84, lineWidth: 11)
            .padding(12)
    }

    private var medium: some View {
        HStack(spacing: 18) {
            WidgetRing(macros: totals, size: 84, lineWidth: 11)
            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY")
                    .font(.system(size: 10, weight: .bold)).tracking(0.6)
                    .foregroundStyle(.secondary)
                macroLine("Protein", totals.protein, W.protein, percent: totals.proteinPercent)
                macroLine("Carbs", totals.carbs, W.carbs, percent: totals.carbsPercent)
                macroLine("Fat", totals.fat, W.fat, percent: totals.fatPercent)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func macroLine(_ label: String, _ value: Double, _ color: Color,
                           percent: Int?) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            if let percent {
                Text("\(percent)%")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text("\(Int(value.rounded()))g").font(.system(size: 11, weight: .bold)).foregroundStyle(.primary)
        }
    }
}

/// A compact copy of the app's macro ring for the widget.
struct WidgetRing: View {
    let macros: Macros
    let size: CGFloat
    let lineWidth: CGFloat

    private var segments: [(Double, Color)] {
        [(macros.protein * 4, W.protein), (macros.carbs * 4, W.carbs), (macros.fat * 9, W.fat)]
    }
    private var total: Double { max(segments.reduce(0) { $0 + $1.0 }, 1) }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)
            let arcs = computeArcs()
            ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                Circle()
                    .trim(from: arc.0, to: arc.1)
                    .stroke(arc.2, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text("\(Int(macros.kcal.rounded()))")
                    .font(.system(size: size * 0.24, weight: .heavy))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.6)
                Text("KCAL")
                    .font(.system(size: size * 0.09, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private func computeArcs() -> [(CGFloat, CGFloat, Color)] {
        var cursor: CGFloat = 0
        var result: [(CGFloat, CGFloat, Color)] = []
        for segment in segments {
            let fraction = CGFloat(segment.0 / total)
            let start = cursor
            let end = max(start, cursor + fraction - 0.01)
            result.append((start, end, segment.1))
            cursor += fraction
        }
        return result
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MacroLogTodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Macros")
        .description("Your running calories, protein, carbs, and fat for today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// Check both colour schemes in the canvas — the widget follows the Home Screen
// appearance, not the app's forced-light style.
#Preview("Medium", as: .systemMedium) {
    TodayWidget()
} timeline: {
    MacroEntry(date: .now,
               snapshot: TodaySnapshot(totals: Macros(kcal: 1430, protein: 96, carbs: 152, fat: 48),
                                       dayStart: Calendar.current.startOfDay(for: .now),
                                       entryCount: 3))
}

#Preview("Small", as: .systemSmall) {
    TodayWidget()
} timeline: {
    MacroEntry(date: .now,
               snapshot: TodaySnapshot(totals: Macros(kcal: 1430, protein: 96, carbs: 152, fat: 48),
                                       dayStart: Calendar.current.startOfDay(for: .now),
                                       entryCount: 3))
}
