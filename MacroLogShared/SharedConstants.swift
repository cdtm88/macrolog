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
}
