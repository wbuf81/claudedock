import AppKit
import SwiftUI
import ClaudeDockCore

/// Colors from the design: blue for usage, a stoplight set for state, amber for "would go unused".
enum Palette {
    static let accent = dynamic(light: 0x2A78D6, dark: 0x3987E5)
    static let good = dynamic(light: 0x0CA30C, dark: 0x0CA30C)
    static let warn = dynamic(light: 0xFAB219, dark: 0xFAB219)
    static let crit = dynamic(light: 0xD03B3B, dark: 0xD03B3B)

    static func color(for light: Light) -> Color {
        switch light {
        case .green: good
        case .yellow: warn
        case .red: crit
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// `--render` can't draw translucent materials, so it asks for a solid background instead.
private struct SolidBackgroundKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var solidBackground: Bool {
        get { self[SolidBackgroundKey.self] }
        set { self[SolidBackgroundKey.self] = newValue }
    }
}

/// The rounded, translucent card both windows use.
struct HUDBackground: ViewModifier {
    @Environment(\.solidBackground) private var solid
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        content
            .background {
                if solid {
                    shape.fill(scheme == .dark ? Color(white: 0.11) : Color(white: 0.97))
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12)))
            .clipShape(shape)
    }
}

extension View {
    func hud(radius: CGFloat) -> some View { modifier(HUDBackground(radius: radius)) }
}
