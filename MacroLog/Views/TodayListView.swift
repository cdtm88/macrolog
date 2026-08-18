import SwiftUI
import SwiftData

/// A day of confirmed entries with description, time, and macros (ENT-01),
/// paged by day: chevrons in the title or a horizontal swipe move between
/// today and any past day, back to the earliest logged entry (day history,
/// 2026-08-05). Today keeps tap-to-edit and swipe-to-delete — both reconcile
/// the Health sample — while past days are read-only apart from the
/// Health-write retry (HK-06), which is date-safe.
struct TodayListView: View {
    @Bindable var model: CaptureViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var dayStart = Calendar.current.startOfDay(for: .now)
    @State private var earliestDay = Calendar.current.startOfDay(for: .now)
    /// Edge the incoming day slides in from — matches the travel direction of
    /// the last chevron tap or swipe.
    @State private var slideEdge: Edge = .leading

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var isToday: Bool { dayStart >= today }
    private var canGoBack: Bool { dayStart > earliestDay }

    var body: some View {
        NavigationStack {
            DayEntriesList(model: model, dayStart: dayStart, isToday: isToday)
                .id(dayStart)
                .transition(.asymmetric(
                    insertion: .move(edge: slideEdge).combined(with: .opacity),
                    removal: .move(edge: slideEdge == .leading ? .trailing : .leading)
                        .combined(with: .opacity)))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { dayHeader }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .gesture(daySwipe)
        }
        .onAppear { earliestDay = model.earliestDayStart() }
    }

    // MARK: - Day navigation

    private var dayHeader: some View {
        HStack(spacing: 0) {
            chevron("chevron.left", enabled: canGoBack, label: "Previous day") { step(-1) }
            Text(dayLabel)
                .font(.system(.headline))
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 116)
            chevron("chevron.right", enabled: !isToday, label: "Next day") { step(1) }
        }
    }

    private func chevron(_ symbol: String, enabled: Bool, label: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(enabled ? Theme.accent : Theme.secondary.opacity(0.4))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var dayLabel: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInYesterday(dayStart) { return "Yesterday" }
        return dayStart.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func step(_ delta: Int) {
        guard let target = Calendar.current.date(byAdding: .day, value: delta, to: dayStart)
        else { return }
        let clamped = min(max(target, earliestDay), today)
        guard clamped != dayStart else { return }
        slideEdge = delta < 0 ? .leading : .trailing
        withAnimation(.snappy) { dayStart = clamped }
    }

    /// Pages only on a decisively horizontal drag, so vertical scrolling and
    /// the rows' own swipe actions (which claim their touches first) are
    /// untouched.
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5
                else { return }
                step(value.translation.width > 0 ? -1 : 1)
            }
    }
}

/// One day's totals and meal rows — the identical layout for today and any
/// past day; only the interactions differ. Recreated per day via `.id` on the
/// parent so the `@Query` predicate tracks the shown day. Any day's row can be
/// swiped (leading) to save the meal as a favourite — a read of the entry, so
/// it doesn't breach past days' read-only rule.
private struct DayEntriesList: View {
    let model: CaptureViewModel
    let isToday: Bool
    @Query private var entries: [FoodEntry]

    @State private var favoritesFull = false
    /// Bumped on every successful favourite save — drives the haptic that
    /// confirms the swipe did something.
    @State private var favoriteSaves = 0

    init(model: CaptureViewModel, dayStart: Date, isToday: Bool) {
        self.model = model
        self.isToday = isToday
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let pending = EntryStatus.pendingReview.rawValue
        _entries = Query(
            filter: #Predicate {
                $0.statusRaw != pending && $0.capturedAt >= dayStart && $0.capturedAt < dayEnd
            },
            sort: \.capturedAt,
            order: .reverse
        )
    }

    private var totals: Macros {
        entries.reduce(Macros.zero) { $0 + $1.macros }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 20) {
                    MacroRing(macros: totals, size: 92, lineWidth: 12, showCenter: true)
                    VStack(alignment: .leading, spacing: 8) {
                        // The calorie target is a ceiling, not a floor: staying
                        // at or under it is the pass, exceeding it the fail —
                        // the inverse of protein. Past days only tick when
                        // something was logged; an empty day "passing" a
                        // calorie ceiling would be noise.
                        totalRow("Calories", totals.kcal, unit: " kcal", Theme.ink,
                                 target: isToday ? SettingsStore.kcalTarget() : nil,
                                 kind: .ceiling,
                                 met: !isToday && !entries.isEmpty
                                      && totals.kcal <= SettingsStore.kcalTarget())
                        totalRow("Protein", totals.protein, unit: "g", Theme.protein,
                                 // The target is today's scalar, not history —
                                 // past days show the plain value, plus a tick
                                 // when the day met the *current* target. No
                                 // miss marker: absence is the signal, and old
                                 // days predate no particular target value.
                                 target: isToday ? SettingsStore.proteinTarget() : nil,
                                 met: !isToday && totals.protein >= SettingsStore.proteinTarget())
                        totalRow("Carbs", totals.carbs, unit: "g", Theme.carbs)
                        totalRow("Fat", totals.fat, unit: "g", Theme.fat)
                        totalRow("Fibre", totals.fiber, unit: "g", Theme.secondary,
                                 // Same treatment as protein: today shows
                                 // progress toward the current target, past
                                 // days get a tick when they met it.
                                 target: isToday ? SettingsStore.fiberTarget() : nil,
                                 met: !isToday && totals.fiber >= SettingsStore.fiberTarget())
                        totalRow("Sodium", totals.sodium, unit: "mg", Theme.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }

            if entries.isEmpty {
                Section {
                    Text(isToday ? "Nothing logged yet today." : "Nothing logged this day.")
                        .font(.system(.subheadline))
                        .foregroundStyle(Theme.secondary)
                }
            } else {
                // One section per time-of-day period, newest period first —
                // matching the query's reverse sort, so the just-logged meal
                // stays at the top. Empty periods don't render.
                ForEach(MealPeriod.displayOrder, id: \.self) { period in
                    let periodEntries = entries.filter {
                        MealPeriod.period(for: $0.capturedAt) == period
                    }
                    if !periodEntries.isEmpty {
                        Section(period.title) {
                            // Explicit swipe actions rather than .onDelete — a
                            // custom leading action disables onDelete's
                            // automatic swipe, so delete moves here too (today
                            // only; past days stay read-only).
                            ForEach(periodEntries) { entry in
                                row(entry)
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            if model.saveAsFavorite(entry) == .full {
                                                favoritesFull = true
                                            } else {
                                                favoriteSaves += 1
                                            }
                                        } label: {
                                            Label("Favourite", systemImage: "star.fill")
                                        }
                                        .tint(.yellow)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        if isToday {
                                            Button(role: .destructive) {
                                                model.delete(entry)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: favoriteSaves)
        .alert("Favourites are full", isPresented: $favoritesFull) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Up to \(Favorite.maxCount) favourites. Remove one in the text sheet's Favourites editor to save another.")
        }
    }

    /// Today's rows open the edit review; past days are read-only.
    @ViewBuilder private func row(_ entry: FoodEntry) -> some View {
        if isToday {
            Button { model.beginEdit(entry) } label: { rowContent(entry) }
                .buttonStyle(.plain)
        } else {
            rowContent(entry)
        }
    }

    private func rowContent(_ entry: FoodEntry) -> some View {
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
                // Retry stays available on past days too: the write is
                // timestamped to capturedAt, so healing an old miss is safe.
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

    private func macroTag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(.caption, weight: .medium))
            .foregroundStyle(color)
    }

    /// A floor target is met at or above the value (protein); a ceiling is
    /// met at or below it (calories).
    private enum TargetKind {
        case floor
        case ceiling
    }

    /// `target` renders the value as progress ("120 / 160g"), green once met.
    /// `met` appends a tick instead — the past-day treatment, where the full
    /// progress figure would overstate what the target meant back then.
    private func totalRow(_ label: String, _ value: Double, unit: String,
                          _ color: Color,
                          target: Double? = nil, kind: TargetKind = .floor,
                          met: Bool = false) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 9, height: 9)
            Text(label).font(.system(.footnote, weight: .medium)).foregroundStyle(Color(hex: 0x3A3A3C))
            Spacer()
            if met {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.success)
                    .accessibilityLabel("\(label) target met")
            }
            // One line always — the calories row ("1,102 / 2,500 kcal") is
            // wider than the grams rows and must scale, not wrap.
            if let target {
                Text("\(Int(value.rounded())) / \(Int(target))\(unit)")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle((kind == .ceiling ? value <= target : value >= target)
                                     ? Theme.success : Theme.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("\(Int(value.rounded()))\(unit)")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

}
