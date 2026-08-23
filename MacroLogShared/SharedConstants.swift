import Foundation

/// Identifiers shared between the app and the widget extension.
public enum SharedConstants {
    /// App Group used to hand today's running totals from the app to the widget.
    /// Must match the `com.apple.security.application-groups` entitlement in
    /// both targets.
    public static let appGroupID = "group.com.macrolog.shared"

    /// Deep-link URL the widget opens; the app routes this straight to capture
    /// (WID-03).
    public static let captureURL = URL(string: "macrolog://capture")!

    /// WidgetKit kind of the quick-log favourites widget, reloaded by the app
    /// whenever the favourites change.
    public static let favoritesWidgetKind = "MacroLogFavoritesWidget"

    /// Deep link a favourites-widget row opens; the app routes it to review
    /// pre-filled with that favourite (review-before-write still applies).
    public static func favoriteURL(id: UUID) -> URL {
        URL(string: "macrolog://favorite/\(id.uuidString)")!
    }

    /// The favourite ID carried by a quick-log deep link, nil for any other
    /// URL — the single parser both the app route and its tests use.
    public static func favoriteID(from url: URL) -> UUID? {
        guard url.scheme == "macrolog", url.host() == "favorite" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
