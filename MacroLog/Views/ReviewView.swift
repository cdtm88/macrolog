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
        Field(label: "Fat", unit: "grams", keyPath: \.fat, step: 1)
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
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Spacer()
            Text("BEFORE IT HITS HEALTH")
                .font(.system(size: 11, weight: .bold))
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
                Text(entry.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text("MacroLog thinks. You decide.")
                    .font(.system(size: 12))
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            Button("Settings") { openSettings() }
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(14)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Cards

    private var ringCard: some View {
        HStack(spacing: 20) {
            MacroRing(macros: entry.macros, size: 128, lineWidth: 15, showCenter: true)
            VStack(alignment: .leading, spacing: 9) {
                legendRow("Protein", value: entry.protein, color: Theme.protein)
                legendRow("Carbs", value: entry.carbs, color: Theme.carbs)
                legendRow("Fat", value: entry.fat, color: Theme.fat)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func legendRow(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 9, height: 9)
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0x3A3A3C))
            Spacer()
            Text("\(Int(value.rounded()))g").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink)
        }
    }

    /// One-tap scaling of all four macros for portion adjustments —
    /// "ate half of it" without stepper marathons.
    private var portionCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Portion").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("Scales all four numbers").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                portionChip("½×", factor: 0.5)
                portionChip("¾×", factor: 0.75)
                portionChip("1½×", factor: 1.5)
                portionChip("2×", factor: 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func portionChip(_ label: String, factor: Double) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { model.scale(entry, by: factor) }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.groupedBackground, in: Capsule())
        }
        .accessibilityLabel("Scale portion by \(label)")
    }

    private var stepperCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(field.label).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(field.unit).font(.system(size: 11)).foregroundStyle(Theme.secondary)
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
                Text("Logged at").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("Kept at capture time, not now").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                stepButton("minus") { model.adjustTime(entry, byMinutes: -5) }
                    .accessibilityLabel("Five minutes earlier")
                Text(entry.capturedAt, format: .dateTime.hour().minute())
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .frame(minWidth: 78)
                stepButton("plus") { model.adjustTime(entry, byMinutes: 5) }
                    .accessibilityLabel("Five minutes later")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func stepper(value: Double, dec: @escaping () -> Void, inc: @escaping () -> Void, label: String) -> some View {
        HStack(spacing: 14) {
            stepButton("minus", action: dec).accessibilityLabel("Decrease \(label)")
            Text("\(Int(value.rounded()))")
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 52)
            stepButton("plus", action: inc).accessibilityLabel("Increase \(label)")
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
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
                Text("Log to Health")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(17)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(color: Theme.accent.opacity(0.28), radius: 18, y: 6)
            }
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
