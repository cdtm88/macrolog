import SwiftUI
import SwiftData

/// The mandatory review-and-edit step. No write to Apple Health happens until
/// the user taps "Log to Health" here (REV-01). All four macros and the
/// timestamp are individually editable (REV-02, ENT-08).
struct ReviewView: View {
    @Bindable var model: CaptureViewModel
    @Bindable var entry: FoodEntry

    private struct Field {
        let label: String
        let unit: String
        let keyPath: WritableKeyPath<Macros, Double>
        let step: Double
    }

    private let fields: [Field] = [
        Field(label: "Calories", unit: "kcal", keyPath: \.kcal, step: 10),
        Field(label: "Protein", unit: "grams", keyPath: \.protein, step: 1),
        Field(label: "Carbohydrate", unit: "grams", keyPath: \.carbs, step: 1),
        Field(label: "Fat", unit: "grams", keyPath: \.fat, step: 1),
        Field(label: "Fibre", unit: "grams", keyPath: \.fiber, step: 1),
        Field(label: "Sodium", unit: "milligrams", keyPath: \.sodium, step: 50)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    mealHeader
                    if model.showPermissionEscalation { permissionBanner }
                    ringCard
                    portionCard
                    stepperCard
                    timeCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }

            confirmBar
        }
        .background(Theme.groupedBackground.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Discard") { model.discard(entry) }
                .font(.system(.callout, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Spacer()
            Text("BEFORE IT HITS HEALTH")
                .font(.system(.caption2, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color(hex: 0xC7C7CC))
            Spacer()
            // Balances the Discard button so the title stays centered. Height
            // must be pinned: a bare `Color` is greedy on both axes and would
            // stretch the header to fill the screen.
            Color.clear.frame(width: 56, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private var mealHeader: some View {
        HStack(spacing: 13) {
            Group {
                if let photo = model.reviewImage {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: 0x8A6F4F), Color(hex: 0x3A2F24)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                // Editable: the AI's name is a guess like the macros are.
                // A blanked field falls back on confirm, never reaching Health.
                TextField("Meal name", text: $entry.name)
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .submitLabel(.done)
                Text("MacroLog thinks. You decide.")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.text.square")
                .foregroundStyle(.orange)
            Text("Writes are failing. Check Health permissions in Settings › Health › Data Access & Devices › MacroLog.")
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            Button("Settings") { openSettings() }
                .font(.system(.footnote, weight: .semibold))
        }
        .padding(14)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Cards

    /// Compact summary strip: small ring plus one column per number. The exact
    /// values live in the steppers below, so no legend duplication is needed.
    private var ringCard: some View {
        HStack(spacing: 14) {
            MacroRing(macros: entry.macros, size: 56, lineWidth: 8)
            summaryColumn("\(Int(entry.kcal.rounded()))", label: "kcal", dot: nil)
            summaryColumn("\(Int(entry.protein.rounded()))g", label: "Protein", dot: Theme.protein)
            summaryColumn("\(Int(entry.carbs.rounded()))g", label: "Carbs", dot: Theme.carbs)
            summaryColumn("\(Int(entry.fat.rounded()))g", label: "Fat", dot: Theme.fat)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func summaryColumn(_ value: String, label: String, dot: Color?) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.callout, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            HStack(spacing: 4) {
                if let dot {
                    Circle().fill(dot).frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(.caption2, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// One-tap portion multiplier applied against the original estimate —
    /// absolute, not compounding, so 1× restores the AI's numbers.
    private var portionCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Portion").font(.system(.callout, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("1× is the original estimate").font(.system(.caption2)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                portionChip("½×", factor: 0.5)
                portionChip("1×", factor: 1)
                portionChip("2×", factor: 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func portionChip(_ label: String, factor: Double) -> some View {
        let selected = model.portionFactor == factor
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { model.setPortion(entry, factor: factor) }
        } label: {
            Text(label)
                .font(.system(.footnote, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(selected ? .white : Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Theme.groupedBackground, in: Capsule())
        }
        .accessibilityLabel("Set portion to \(label)")
    }

    private var stepperCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(field.label).font(.system(.callout, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(field.unit).font(.system(.caption2)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    stepper(value: entry.macros[keyPath: field.keyPath],
                            dec: { model.adjust(entry, keyPath: field.keyPath, by: -field.step) },
                            inc: { model.adjust(entry, keyPath: field.keyPath, by: field.step) },
                            label: field.label)
                }
                .padding(.vertical, 15)
                if index < fields.count - 1 {
                    Divider().overlay(Color(hex: 0x3C3C43, alpha: 0.12))
                }
            }
        }
        .padding(.horizontal, 18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var timeCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Logged at").font(.system(.callout, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("Defaults to capture time, not now").font(.system(.caption2)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            // Compact time picker instead of ±5-minute steppers: logging hours
            // late is a couple of taps, not a tap marathon. Time-of-day only —
            // the entry stays on its capture day (accepted trade-off for the
            // cleaner single-chip look) — and capped at now, a meal can't be
            // in the future.
            DatePicker("Logged at",
                       selection: $entry.capturedAt,
                       in: ...Date.now,
                       displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func stepper(value: Double, dec: @escaping () -> Void, inc: @escaping () -> Void, label: String) -> some View {
        HStack(spacing: 14) {
            stepButton("minus", action: dec).accessibilityLabel("Decrease \(label)")
            Text("\(Int(value.rounded()))")
                .font(.system(.title3, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 52)
            stepButton("plus", action: inc).accessibilityLabel("Increase \(label)")
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.groupedBackground, in: Circle())
        }
        // Hold to repeat — large adjustments without tap marathons.
        .buttonRepeatBehavior(.enabled)
    }

    private var confirmBar: some View {
        VStack(spacing: 0) {
            Button { model.confirm(entry) } label: {
                HStack(spacing: 8) {
                    if model.isWriting { ProgressView().tint(.white) }
                    Text(model.isWriting ? "Logging…" : "Log to Health")
                        .font(.system(.body, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(17)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: Theme.accent.opacity(0.28), radius: 18, y: 6)
            }
            .disabled(model.isWriting)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 40)
        .background(Theme.groupedBackground)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: FoodEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let entry = FoodEntry(name: "Protein shake & banana",
                          macros: Macros(kcal: 320, protein: 30, carbs: 38, fat: 6),
                          capturedAt: .now,
                          status: .pendingReview)
    return ReviewView(model: CaptureViewModel(context: container.mainContext), entry: entry)
        .modelContainer(container)
}
