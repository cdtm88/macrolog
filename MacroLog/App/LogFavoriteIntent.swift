import AppIntents
import Foundation

/// Route from App Intents to the live view model. Set once at boot; an intent
/// arriving before the store opened (boot failed) simply no-ops.
@MainActor
enum ActiveModel {
    static weak var shared: CaptureViewModel?
}

// FavoriteEntity, its query, and the widget-configuration intent live in
// MacroLogShared/FavoriteEntity.swift — the widget's edit sheet needs them
// in the extension process too.

/// "Log a favourite": opens the app straight into review pre-filled with the
/// chosen favourite. Deliberately `openAppWhenRun` — review-before-write
/// (REV-01) means a quick-log can never write Health data from outside the
/// app; the intent only gets the user to the confirm button faster.
struct LogFavoriteIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Favourite"
    static let description = IntentDescription(
        "Opens MacroLog ready to confirm one of your favourite meals.")
    static let openAppWhenRun = true

    @Parameter(title: "Favourite")
    var favorite: FavoriteEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        ActiveModel.shared?.logFavorite(id: favorite.id)
        return .result()
    }
}

struct MacroLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogFavoriteIntent(),
                    phrases: ["Log a favourite in \(.applicationName)"],
                    shortTitle: "Log favourite",
                    systemImageName: "star.fill")
    }
}
