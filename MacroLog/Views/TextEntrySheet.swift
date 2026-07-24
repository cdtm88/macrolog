import SwiftUI
import SwiftData

/// Bottom sheet for describing a meal in text — an equal-status alternative to
/// the camera, one tap from capture (CAP-02). Also shown when a photo could not
/// be identified (EST-04).
struct TextEntrySheet: View {
    @Bindable var model: CaptureViewModel
    @State private var text = ""
    @State private var contentHeight: CGFloat = 280
    @FocusState private var focused: Bool

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: model.needsTextAfterPhoto ? "camera.metering.unknown" : "square.and.pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if model.needsTextAfterPhoto {
                            Text("Couldn't read the plate")
                        } else {
                            Text("Describe it instead")
                        }
                    }
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Theme.ink)

                    Group {
                        if model.needsTextAfterPhoto {
                            Text("Describe it and we'll estimate from your words.")
                        } else {
                            Text("Say what you ate. Include the oil and butter — it counts.")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }

            TextField("Chicken curry, rice, naan…", text: $text, axis: .vertical)
                .font(.system(size: 17))
                .foregroundStyle(Theme.ink)
                .lineLimit(3...6)
                .focused($focused)
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(focused ? Theme.accent.opacity(0.5) : .clear, lineWidth: 1.5)
                )
                .submitLabel(.go)
                .onSubmit(submit)

            Button(action: submit) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Estimate it")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(15)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
            }
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.4)
            .animation(.easeOut(duration: 0.15), value: canSubmit)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
        .presentationBackground(Theme.groupedBackground)
        .presentationCornerRadius(28)
        .onAppear { focused = true }
    }

    private func submit() {
        guard canSubmit else { return }
        model.submitText(text)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: FoodEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return Color.clear.sheet(isPresented: .constant(true)) {
        TextEntrySheet(model: CaptureViewModel(context: container.mainContext))
    }
    .modelContainer(container)
}
