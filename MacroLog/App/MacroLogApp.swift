import SwiftUI
import SwiftData

@main
struct MacroLogApp: App {
    private let container: ModelContainer
    @State private var model: CaptureViewModel

    init() {
        do {
            container = try ModelContainer(for: FoodEntry.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        _model = State(initialValue: CaptureViewModel(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .modelContainer(container)
    }
}
