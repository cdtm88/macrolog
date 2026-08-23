import SwiftUI
import SwiftData

/// Bottom sheet for describing a meal in text — an equal-status alternative to
/// the camera, one tap from capture (CAP-02). Also shown when a photo could not
/// be identified (EST-04) and after any estimation failure, with the failed
/// input retained so the retry carries photo and description together (EST-05).
struct TextEntrySheet: View {
    @Bindable var model: CaptureViewModel
    @Query(sort: \Favorite.sortOrder) private var favorites: [Favorite]
    @State private var text: String
    @State private var contentHeight: CGFloat = 280
    @State private var isManagingFavorites = false
    @FocusState private var focused: Bool

    init(model: CaptureViewModel) {
        self.model = model
        // Seed the retained description at construction, not in onAppear — a
        // post-presentation state change re-measures the height detent and
        // makes the sheet visibly load in two steps (CAP-05).
        let isRetry = model.needsTextAfterPhoto || model.estimationError != nil
        _text = State(initialValue: isRetry ? (model.lastText ?? "") : "")
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            TextField("Chicken curry, rice, naan…", text: $text, axis: .vertical)
                .font(.system(.body))
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

            favoritesSection

            Button(action: submit) {
                HStack(spacing: 7) {
                    Image(systemName: failed ? "arrow.clockwise" : "sparkles")
                        .font(.system(.subheadline, weight: .semibold))
                    Text(failed ? "Retry estimate" : "Estimate it")
                        .font(.system(.body, weight: .bold))
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
        // Focus immediately so the keyboard rises with the sheet as one motion
        // rather than a second step after the content lands.
        .onAppear { focused = true }
        .sheet(isPresented: $isManagingFavorites, onDismiss: {
            // Edits in the sheet write straight to SwiftData; republish the
            // App-Group snapshot so the quick-log widget and Siri picker match.
            model.publishFavoritesSnapshot()
        }) {
            FavoritesView()
        }
    }

    // MARK: - Header

    /// Adapts to why the sheet is up: a fresh text entry, an unidentifiable
    /// photo, or a failed estimate whose cause is shown with the input kept —
    /// each failure names itself explicitly (D-10). The thumbnail confirms a
    /// retained photo will be re-sent with the description.
    private var header: some View {
        HStack(spacing: 12) {
            if model.needsTextAfterPhoto, let photo = model.lastImage {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ZStack {
                    Circle()
                        .fill(failed ? Color.orange.opacity(0.14) : Theme.accent.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: headerIcon)
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(failed ? .orange : Theme.accent)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(.title3, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(headerSubtitle)
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var failed: Bool { model.estimationError != nil }

    private var headerIcon: String {
        if failed { return "exclamationmark.triangle" }
        return model.needsTextAfterPhoto ? "camera.metering.unknown" : "square.and.pencil"
    }

    private var headerTitle: String {
        if let error = model.estimationError { return error.errorTitle }
        return model.needsTextAfterPhoto ? "Couldn't read the plate" : "Describe it instead"
    }

    private var headerSubtitle: String {
        if let error = model.estimationError {
            let keep = model.needsTextAfterPhoto ? " Your photo is kept and resent with it." : ""
            return (error.errorDescription ?? "") + keep
        }
        return model.needsTextAfterPhoto
            ? "Describe it and we'll estimate from your words."
            : "Say what you ate — oils and sauces count."
    }

    // MARK: - Favourites

    /// One-tap chips for preconfigured meals — straight to review with the
    /// preset values, no AI estimate.
    @ViewBuilder private var favoritesSection: some View {
        if favorites.isEmpty {
            Button { isManagingFavorites = true } label: {
                Label("Add favourites for one-tap logging", systemImage: "star")
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("FAVOURITES")
                        .font(.system(.caption2, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("Edit") { isManagingFavorites = true }
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(favorites) { favorite in
                            favoriteChip(favorite)
                        }
                    }
                }
            }
        }
    }

    private func favoriteChip(_ favorite: Favorite) -> some View {
        Button {
            model.submitFavorite(name: favorite.name, macros: favorite.macros)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(favorite.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(Int(favorite.kcal.rounded())) kcal")
                    .font(.system(.caption2))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func submit() {
        guard canSubmit else { return }
        model.submitText(text)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: FoodEntry.self, Favorite.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return Color.clear.sheet(isPresented: .constant(true)) {
        TextEntrySheet(model: CaptureViewModel(context: container.mainContext))
    }
    .modelContainer(container)
}
