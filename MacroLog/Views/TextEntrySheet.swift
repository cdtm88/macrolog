import SwiftUI

/// Bottom sheet for describing a meal in text — an equal-status alternative to
/// the camera, one tap from capture (CAP-02). Also shown when a photo could not
/// be identified (EST-04).
struct TextEntrySheet: View {
    @Bindable var model: CaptureViewModel
    @State private var text = ""
    @FocusState private var focused: Bool

    private let chips = ["2 eggs, sourdough, butter",
                         "Chicken curry, rice, naan",
                         "Protein shake & banana"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(Color(hex: 0xD1D1D6))
                    .frame(width: 38, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 18)

                if model.needsTextAfterPhoto {
                    Text("Couldn't read the plate")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Describe it and we'll estimate from your words.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .padding(.bottom, 16)
                } else {
                    Text("Describe it instead")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Say what you ate. Include the oil and butter — it counts.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .padding(.bottom, 16)
                }

                TextField("e.g. chicken curry, rice, naan", text: $text, axis: .vertical)
                    .font(.system(size: 16))
                    .focused($focused)
                    .padding(15)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    .submitLabel(.go)
                    .onSubmit(submit)

                FlowChips(chips: chips) { text = $0 }
                    .padding(.top, 12)

                Button(action: submit) {
                    Text("Estimate it")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Theme.groupedBackground)
        .onAppear { focused = true }
    }

    private func submit() {
        model.submitText(text)
    }
}

/// Simple wrapping row of tappable suggestion chips.
private struct FlowChips: View {
    let chips: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chips, id: \.self) { chip in
                Button { onTap(chip) } label: {
                    Text(chip)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x3A3A3C))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(Theme.card, in: Capsule())
                }
            }
        }
    }
}
