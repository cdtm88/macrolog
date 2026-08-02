import SwiftUI
import SwiftData

/// Today's confirmed entries with description, time, and macros (ENT-01).
/// Tap to edit, swipe to delete — both reconcile the Health sample.
/// Unwritten entries surface a retry (HK-06).
struct TodayListView: View {
    @Bindable var model: CaptureViewModel
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [FoodEntry]

    init(model: CaptureViewModel) {
        self.model = model
        let dayStart = Calendar.current.startOfDay(for: .now)
        let pending = EntryStatus.pendingReview.rawValue
        _entries = Query(
            filter: #Predicate { $0.statusRaw != pending && $0.capturedAt >= dayStart },
            sort: \.capturedAt,
            order: .reverse
        )
    }

    private var totals: Macros {
        entries.reduce(Macros.zero) { $0 + $1.macros }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 20) {
                        MacroRing(macros: totals, size: 92, lineWidth: 12, showCenter: true)
                        VStack(alignment: .leading, spacing: 8) {
                            totalRow("Protein", totals.protein, unit: "g", Theme.protein, percent: totals.proteinPercent)
                            totalRow("Carbs", totals.carbs, unit: "g", Theme.carbs, percent: totals.carbsPercent)
                            totalRow("Fat", totals.fat, unit: "g", Theme.fat, percent: totals.fatPercent)
                            totalRow("Fibre", totals.fiber, unit: "g", Theme.secondary)
                            totalRow("Sodium", totals.sodium, unit: "mg", Theme.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }

                if entries.isEmpty {
                    Section {
                        Text("Nothing logged yet today.")
                            .font(.system(.subheadline))
                            .foregroundStyle(Theme.secondary)
                    }
                } else {
                    Section("Meals") {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ entry: FoodEntry) -> some View {
        Button { model.beginEdit(entry) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.name)
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(entry.capturedAt, format: .dateTime.hour().minute())
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                }
                HStack(spacing: 12) {
                    macroTag("\(Int(entry.kcal.rounded())) kcal", Theme.ink)
                    macroTag("\(Int(entry.protein.rounded()))P", Theme.protein)
                    macroTag("\(Int(entry.carbs.rounded()))C", Theme.carbs)
                    macroTag("\(Int(entry.fat.rounded()))F", Theme.fat)
                }
                if entry.status == .unwritten {
                    Button {
                        model.retryWrite(entry)
                    } label: {
                        Label("Not in Health — retry", systemImage: "exclamationmark.arrow.circlepath")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func macroTag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(.caption, weight: .medium))
            .foregroundStyle(color)
    }

    /// `percent` is the macro's share of today's calories (4/4/9 weighting) —
    /// shown only for the three calorie-bearing macros.
    private func totalRow(_ label: String, _ value: Double, unit: String,
                          _ color: Color, percent: Int? = nil) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 9, height: 9)
            Text(label).font(.system(.footnote, weight: .medium)).foregroundStyle(Color(hex: 0x3A3A3C))
            Spacer()
            if let percent {
                Text("\(percent)%")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .monospacedDigit()
            }
            Text("\(Int(value.rounded()))\(unit)")
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            model.delete(entries[index])
        }
    }
}
