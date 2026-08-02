import SwiftUI
import SwiftData

/// Creates the on-disk SwiftData store. Factored out of the App so the
/// corrupt-store path is testable against a scratch URL.
enum StoreBootstrap {
    /// Where the default configuration puts the store — the same location
    /// `ModelContainer(for:)` uses, so existing data is picked up unchanged.
    static var defaultURL: URL { ModelConfiguration().url }

    static func makeContainer(at url: URL = StoreBootstrap.defaultURL) throws -> ModelContainer {
        let schema = Schema([FoodEntry.self, Favorite.self])
        let config = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Deletes the store and its SQLite sidecar files so a corrupt store can
    /// be recreated empty. Health data is untouched — only the local store
    /// (today's list and any pending entry) is removed.
    static func reset(at url: URL = StoreBootstrap.defaultURL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}

@main
struct MacroLogApp: App {
    private enum Bootstrap {
        case ready(ModelContainer, CaptureViewModel)
        case failed(String)
    }

    @State private var bootstrap: Bootstrap

    init() {
        _bootstrap = State(initialValue: Self.boot())
    }

    /// A store that can't be opened degrades to an explicit error state with a
    /// reset path instead of a crash loop — "fail loudly" applies to launch
    /// too. Everything confirmed already lives in Apple Health; only today's
    /// local list is at stake.
    private static func boot() -> Bootstrap {
        do {
            let container = try StoreBootstrap.makeContainer()
            return .ready(container, CaptureViewModel(context: container.mainContext))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case .ready(let container, let model):
                RootView(model: model)
                    .modelContainer(container)
            case .failed(let message):
                StorageFailureView(message: message) {
                    StoreBootstrap.reset()
                    bootstrap = Self.boot()
                }
            }
        }
    }
}

/// Explicit degraded state for a store that can't be opened (HK-05's "no
/// crash" spirit at launch). Resetting clears only the local store.
private struct StorageFailureView: View {
    let message: String
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Local storage can't be opened")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Meals already confirmed are safe in Apple Health. Resetting clears only today's local list.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Reset Local Data", role: .destructive, action: onReset)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}
