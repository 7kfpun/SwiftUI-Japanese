import SwiftUI

/// Visual identity carried over from the RN app (see context/07-ux-ui.md):
/// near-monochrome + one teal accent; green/red reserved for answer feedback.
enum Theme {
    static let accent  = Color(red: 0.06, green: 0.69, blue: 0.75)   // iOSColors.tealBlue
    static let correct = Color(red: 0.18, green: 0.80, blue: 0.25)   // #2ECC40
    static let wrong   = Color(red: 1.00, green: 0.25, blue: 0.21)   // #FF4136

    // Semantic system colors so Dark Mode works for free.
    static let surface = Color(.systemBackground)
    static let canvas  = Color(.secondarySystemBackground)
}
