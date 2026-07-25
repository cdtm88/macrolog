import SwiftUI
import PhotosUI

/// The default input surface: a live camera viewfinder with the running daily
/// total, a shutter, a one-tap text alternative, and a photo-library picker
/// (CAP-01/02/04). Matches the attached prototype.
struct CaptureView: View {
    @Bindable var model: CaptureViewModel
    @StateObject private var camera = CameraController()
    @State private var libraryItem: PhotosPickerItem?
    @State private var isCapturing = false

    /// True whenever the viewfinder is covered by the text sheet or review screen.
    private var cameraObscured: Bool {
        model.isShowingText || model.reviewEntry != nil
    }

    var body: some View {
        ZStack {
            Theme.groupedBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                viewfinder
                    .padding(.horizontal, 16)
                controls
            }
        }
        .onAppear { camera.configureAndStart() }
        .onDisappear { camera.stop() }
        // Pause the live feed while it's hidden behind the text sheet or the
        // review cover — no reason to hold the camera while typing/reviewing.
        .onChange(of: cameraObscured) { _, obscured in
            if obscured { camera.stop() } else { camera.resume() }
        }
        .sheet(isPresented: $model.isShowingText, onDismiss: {
            model.textSheetDismissed()
            model.sheetDidDismiss()
        }) {
            TextEntrySheet(model: model)
        }
        .sheet(isPresented: $model.isShowingList, onDismiss: { model.sheetDidDismiss() }) {
            TodayListView(model: model)
        }
        // Item-based presentation: the cover's content is unconditional, so the
        // hosting controller always lays it out full-screen (an `if let` inside
        // `fullScreenCover(isPresented:)` can leave the view floating mid-screen).
        .fullScreenCover(item: $model.reviewEntry) { entry in
            ReviewView(model: model, entry: entry)
        }
        .overlay(alignment: .top) { toast }
        .alert(item: $model.estimationError) { error in
            Alert(title: Text(error.errorTitle),
                  message: Text(error.errorDescription ?? ""),
                  primaryButton: .default(Text("Retry")) { model.retryLast() },
                  secondaryButton: .cancel(Text("Dismiss")))
        }
        .alert(item: $model.healthError) { error in
            Alert(title: Text("Health"),
                  message: Text(error.errorDescription ?? ""),
                  dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Text("MacroLog")
                .font(.system(.title3, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button { model.isShowingList = true } label: { todayPill }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var todayPill: some View {
        let totals = model.todaysTotals()
        return HStack(spacing: 9) {
            MacroRing(macros: totals, size: 30, lineWidth: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text("TODAY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondary)
                HStack(spacing: 2) {
                    Text("\(Int(totals.kcal.rounded()))")
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("kcal")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 13)
        .padding(.vertical, 6)
        .background(Theme.card, in: Capsule())
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .accessibilityLabel("Today: \(Int(totals.kcal.rounded())) kilocalories")
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(LinearGradient(colors: [Theme.viewfinderTop, Theme.viewfinderBottom],
                                     startPoint: .top, endPoint: .bottom))

            if camera.status == .ready {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 30))
            }

            reticles

            switch model.captureState {
            case .idle:
                if camera.status == .denied {
                    hintPill(text: "Camera access off — use Type or Library", dot: .orange)
                } else {
                    hintPill(text: "Point at the plate", dot: Theme.success)
                }
            case .working:
                workingOverlay
            case .ready:
                if let pending = model.pendingEntry {
                    readyPill(for: pending)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var reticles: some View {
        GeometryReader { _ in
            ForEach(0..<4, id: \.self) { corner in
                ReticleCorner(corner: corner)
            }
        }
        .padding(24)
    }

    private func hintPill(text: String, dot: Color) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(text)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .background(.black.opacity(0.4), in: Capsule())
            .padding(.bottom, 26)
        }
    }

    private var workingOverlay: some View {
        ZStack {
            Color.black.opacity(0.32)
            VStack {
                Spacer()
                HStack(spacing: 9) {
                    ProgressView().tint(.white)
                    Text(model.isTakingLong ? "Still working…" : "Reading the plate…")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(.bottom, 26)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30))
    }

    private func readyPill(for entry: FoodEntry) -> some View {
        VStack {
            Spacer()
            Button { model.openPendingReview() } label: {
                HStack(spacing: 13) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [Color(hex: 0x8A6F4F), Color(hex: 0x3A2F24)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ESTIMATE READY")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(Color(hex: 0x30A14E))
                        Text("\(entry.name) · \(Int(entry.kcal.rounded())) kcal")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("Review ›")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(14)
                .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.28), radius: 12, y: 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack {
            Button { model.isShowingText = true } label: {
                controlChip { VStack(spacing: 2) {
                    Text("Aa").font(.system(.body, weight: .heavy)).foregroundStyle(Theme.ink)
                    Text("TYPE").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.secondary)
                } }
            }
            .accessibilityLabel("Describe a meal in text")

            Spacer()

            Button { capture() } label: {
                ZStack {
                    Circle().strokeBorder(Theme.ink, lineWidth: 4).frame(width: 76, height: 76)
                    Circle().fill(Theme.ink).frame(width: 60, height: 60)
                        .scaleEffect(isCapturing ? 0.88 : 1)
                }
            }
            .disabled(camera.status != .ready || model.captureState == .working)
            .accessibilityLabel("Take a photo of your meal")

            Spacer()

            PhotosPicker(selection: $libraryItem, matching: .images) {
                controlChip { VStack(spacing: 3) {
                    Image(systemName: "photo").font(.system(.body)).foregroundStyle(Theme.ink)
                    Text("LIBRARY").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.secondary)
                } }
            }
            .accessibilityLabel("Choose a photo from your library")
        }
        .padding(.horizontal, 30)
        .padding(.top, 22)
        .padding(.bottom, 40)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task { await loadLibraryImage(item) }
        }
    }

    private func controlChip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: 56, height: 56)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    // MARK: - Actions

    private func capture() {
        guard camera.status == .ready else { return }
        isCapturing = true
        Task {
            let image = await camera.capturePhoto()
            isCapturing = false
            if let image { model.submitPhoto(image) }
        }
    }

    private func loadLibraryImage(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            model.submitPhoto(image)
        }
        libraryItem = nil
    }

    // MARK: - Toast

    @ViewBuilder private var toast: some View {
        if let toast = model.toast {
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(Theme.success).frame(width: 26, height: 26)
                    Image(systemName: "checkmark").font(.system(.caption, weight: .bold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logged")
                        .font(.system(.subheadline, weight: .bold)).foregroundStyle(.white)
                    Text(toast)
                        .font(.system(.caption)).foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            .padding(.horizontal, 16)
            .padding(.top, 60)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// One of the four corner reticles in the viewfinder.
private struct ReticleCorner: View {
    let corner: Int // 0 tl, 1 tr, 2 bl, 3 br

    var body: some View {
        GeometryReader { geo in
            let s: CGFloat = 26
            let top = corner == 0 || corner == 1
            let left = corner == 0 || corner == 2
            Path { path in
                let x: CGFloat = left ? 0 : geo.size.width - s
                let y: CGFloat = top ? 0 : geo.size.height - s
                if top {
                    path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x + s, y: y))
                } else {
                    path.move(to: CGPoint(x: x, y: y + s)); path.addLine(to: CGPoint(x: x + s, y: y + s))
                }
                let vx = left ? x : x + s
                path.move(to: CGPoint(x: vx, y: y)); path.addLine(to: CGPoint(x: vx, y: y + s))
            }
            .stroke(.white.opacity(0.7), lineWidth: 2)
        }
    }
}
