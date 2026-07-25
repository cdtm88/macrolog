import SwiftUI

/// Top-level routing. Sends unsupported devices to an explicit state (HK-05),
/// otherwise shows capture with a thin banner when Health write access was
/// denied (HK-07).
struct RootView: View {
    @Bindable var model: CaptureViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.healthState {
            case .unavailable:
                UnsupportedDeviceView()
            case .ok, .denied:
                VStack(spacing: 0) {
                    if model.healthState == .denied { deniedBanner }
                    CaptureView(model: model)
                }
            }
        }
        // Fonts scale with the system text size; cap at the first accessibility
        // size so the compact card/chip layouts stay usable.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .task { await model.onLaunch() }
        // Day-boundary maintenance must also run when the app foregrounds
        // across midnight without a cold launch (ENT-04, WID-02).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.onBecameActive() }
        }
        .onOpenURL { url in
            // Widget tap routes straight to capture (WID-03).
            if url == SharedConstants.captureURL {
                model.isShowingList = false
                model.isShowingText = false
            }
        }
    }

    private var deniedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.text.square").foregroundStyle(.orange)
            Text("Health write access is off. Meals can't reach Whoop until you enable it in Settings.")
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(.footnote, weight: .semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }
}
