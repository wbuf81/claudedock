import AppKit
import SwiftUI
import ClaudeDockCore

/// The week ring: fill = % used, tick = how much of the week has gone by.
struct WeekRing: View {
    var used: Double
    var elapsed: Double
    var color: Color
    /// Outer size; the design is drawn at 48 pt.
    var size: CGFloat = 48

    var body: some View {
        let k = size / 48
        ZStack {
            Circle().stroke(color.opacity(0.26), lineWidth: 6 * k)
            Circle().trim(from: 0, to: used / 100)
                .stroke(color, lineWidth: 6 * k)
                .rotationEffect(.degrees(-90))
            Capsule().fill(Color.primary).frame(width: 2 * k, height: 6 * k)
                .offset(y: -19.5 * k)
                .rotationEffect(.degrees(elapsed * 360))
            Text(Formatting.percent(used)).font(.system(size: max(10.5 * k, 9.5), weight: .bold))
        }
        .frame(width: 36 * k, height: 36 * k)
        .frame(width: size, height: size)
    }
}

/// A thin bar: fill = % used, tick = how far through the window we are (none when no
/// window is open). Every bar uses the same track, so idle and busy bars look alike.
struct UsageBar: View {
    var used: Double
    var tick: Double?
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            // The track sets the size; the fill and the (taller) tick are overlays, so they can
            // never make one bar taller than another.
            Capsule().fill(color.opacity(0.26))
                .frame(width: width, height: height)
                .overlay(alignment: .leading) {
                    Capsule().fill(color)
                        .frame(width: used > 0 ? max(width * used / 100, height) : 0, height: height)
                }
                .overlay(alignment: .leading) {
                    if let tick {
                        Capsule().fill(Color.primary)
                            .frame(width: 2, height: height * 2)
                            .offset(x: width * tick - 1)
                    }
                }
        }
        .frame(height: height)
    }
}

/// The stoplight dot. Steady: an org that's in use gets particles instead (`InUseEffect`).
struct StoplightDot: View {
    var light: Light
    var size: CGFloat = 9

    var body: some View {
        Circle().fill(Palette.color(for: light)).frame(width: size, height: size)
            .accessibilityLabel(label)
    }

    private var label: String {
        switch light {
        case .green: "Use it"
        case .yellow: "On pace"
        case .red: "Nearly out"
        }
    }
}

/// What the widget's and panel's buttons and menu items do.
struct WidgetActions {
    var tap: () -> Void = {}
    var refresh: () -> Void = {}
    var hide: () -> Void = {}
    var settings: () -> Void = {}
    var signInOut: () -> Void = {}
    var quit: () -> Void = {}
    var dragChanged: () -> Void = {}
    var dragEnded: () -> Void = {}
    var place: (SnapPoint) -> Void = { _ in }
    var layout: (LayoutChoice) -> Void = { _ in }
    var size: (Double) -> Void = { _ in }
    /// Turns Shrink until hovered on or off.
    var compact: (Bool) -> Void = { _ in }
    var effect: (EffectStyle) -> Void = { _ in }
    var amount: (EffectAmount) -> Void = { _ in }
    /// A trackpad pinch: the magnification so far, and whether the pinch has ended.
    var pinch: (Double, Bool) -> Void = { _, _ in }
    /// Shows or hides the crab.
    var showCrab: (Bool) -> Void = { _ in }
    /// Connects (true) or disconnects (false) Claude Dock's hooks.
    var connectHooks: (Bool) -> Void = { _ in }

    static let none = WidgetActions()
}
