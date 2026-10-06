import SwiftUI
import ClaudeDockCore

/// The week ring: fill = % used, tick = how much of the week has gone by.
struct WeekRing: View {
    var used: Double
    var elapsed: Double
    var color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.26), lineWidth: 6)
            Circle().trim(from: 0, to: used / 100)
                .stroke(color, lineWidth: 6)
                .rotationEffect(.degrees(-90))
            Capsule().fill(Color.primary).frame(width: 2, height: 7)
                .offset(y: -18.5)
                .rotationEffect(.degrees(elapsed * 360))
            Text(Formatting.percent(used)).font(.system(size: 10.5, weight: .bold))
        }
        .frame(width: 36, height: 36)
        .frame(width: 48, height: 48)
    }
}

/// A thin bar: fill = % used, tick = how far through the window we are.
struct UsageBar: View {
    var used: Double
    var tick: Double?
    var color: Color
    var height: CGFloat = 6
    var off = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(off ? Color.primary.opacity(0.12) : color.opacity(0.26))
                if !off {
                    Capsule().fill(color).frame(width: used > 0 ? max(geo.size.width * used / 100, height) : 0)
                    if let tick {
                        Capsule().fill(Color.primary).frame(width: 2, height: height + 6)
                            .offset(x: geo.size.width * tick - 1)
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// The stoplight dot. Green pulses (faster when more would go unused) unless Reduce Motion is on.
/// The pulse is drawn from the clock rather than a `@State` animation: with the macOS 27 SDK
/// `@State` is a macro whose plugin the Command Line Tools don't ship.
struct StoplightDot: View {
    var light: Light
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = Palette.color(for: light)
        Circle().fill(color).frame(width: 9, height: 9)
            .overlay {
                if case .green(let pulse?) = light, !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        let seconds = context.date.timeIntervalSinceReferenceDate
                        let phase = seconds.truncatingRemainder(dividingBy: pulse.rawValue) / pulse.rawValue
                        Circle().stroke(color, lineWidth: 2)
                            .scaleEffect(1 + 1.4 * phase)
                            .opacity(0.8 * (1 - phase))
                    }
                }
            }
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

    static let none = WidgetActions()
}
