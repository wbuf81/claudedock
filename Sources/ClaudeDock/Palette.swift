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

/// How cards are drawn. Image rendering can't draw live glass or materials, so `--render`
/// asks for solid cards and `--showcase` for see-through ones over its own scene.
enum RenderStyle {
    case live, solid, showcase
}

private struct RenderStyleKey: EnvironmentKey {
    static let defaultValue = RenderStyle.live
}

extension EnvironmentValues {
    var renderStyle: RenderStyle {
        get { self[RenderStyleKey.self] }
        set { self[RenderStyleKey.self] = newValue }
    }
}

/// The rounded card both windows use. With `glass` on macOS 26 or later it's the system's
/// clear Liquid Glass, tuned to match the Dock. Otherwise, or with Reduce Transparency or
/// Increase Contrast on, a frosted material.
struct HUDBackground: ViewModifier {
    @Environment(\.renderStyle) private var style
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var radius: CGFloat
    var glass: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        if style == .showcase {
            content
                .background(shape.fill(scheme == .dark ? Color(white: 0.08).opacity(0.55) : Color.white.opacity(0.42)))
                .overlay(shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.22 : 0.65), lineWidth: 1))
                .clipShape(shape)
        } else if style == .solid {
            content
                .background(shape.fill(scheme == .dark ? Color(white: 0.11) : Color(white: 0.97)))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12)))
                .clipShape(shape)
        } else if glass, !reduceTransparency, contrast == .standard {
            content.dockGlass(shape)
        } else {
            content.frosted(shape)
        }
    }
}

private extension View {
    /// Clear Liquid Glass at 75% with a soft light rim: side by side with the Dock this let
    /// the wallpaper through about as much and kept the same defined edge (full strength
    /// read milkier; 40-60% lost the edge). Needs the macOS 26 SDK to build and macOS 26 to
    /// run; anything older gets the frosted card.
    @ViewBuilder
    func dockGlass(_ shape: RoundedRectangle) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            clipShape(shape)
                .background { Color.clear.glassEffect(.clear, in: shape).opacity(0.75) }
                .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        } else {
            frosted(shape)
        }
        #else
        frosted(shape)
        #endif
    }

    func frosted(_ shape: RoundedRectangle) -> some View {
        background(shape.fill(.regularMaterial))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12)))
            .clipShape(shape)
    }
}

extension View {
    func hud(radius: CGFloat, glass: Bool = false) -> some View { modifier(HUDBackground(radius: radius, glass: glass)) }
}

