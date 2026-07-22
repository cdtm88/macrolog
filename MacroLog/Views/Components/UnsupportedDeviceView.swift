import SwiftUI

/// Shown on a device where HealthKit is unavailable, rather than crashing
/// (HK-05).
struct UnsupportedDeviceView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 44))
                .foregroundStyle(Theme.secondary)
            Text("Apple Health isn't available")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("MacroLog writes macros to Apple Health, which this device doesn't support. Run it on an iPhone running iOS 18 or later.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.groupedBackground.ignoresSafeArea())
    }
}
