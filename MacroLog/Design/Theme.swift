import SwiftUI

/// Colours and shared styling, matching the attached prototype.
enum Theme {
    // Macro colours — the brand's tricolour ring.
    static let protein = Color(hex: 0x007AFF) // blue
    static let carbs   = Color(hex: 0xFF9500) // orange
    static let fat     = Color(hex: 0xAF52DE) // purple

    static let accent  = protein
    static let success = Color(hex: 0x30D158)

    static let ink       = Color(hex: 0x1C1C1E)
    static let secondary = Color(hex: 0x8E8E93)
    static let groupedBackground = Color(hex: 0xF2F2F7)
    static let card = Color.white
    /// Unfilled ring track — must stay visible on both `card` and
    /// `groupedBackground`, or a zero-macro day makes the ring vanish.
    static let ringTrack = Color(hex: 0xE3E3E8)

    /// The dark viewfinder gradient behind the camera.
    static let viewfinderTop = Color(hex: 0x3A3A40)
    static let viewfinderBottom = Color(hex: 0x0E0E11)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
