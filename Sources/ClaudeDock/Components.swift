import AppKit
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
struct StoplightDot: View {
    var light: Light
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = Palette.color(for: light)
        Circle().fill(color).frame(width: 9, height: 9)
            .overlay {
                if case .green(let pulse?) = light, !reduceMotion {
                    PulseRing(color: NSColor(color), period: pulse.rawValue).frame(width: 9, height: 9)
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

/// The pulsing ring around a green dot, animated by Core Animation in the window server so
/// the app does no per-frame work. (A SwiftUI animation here re-laid out the whole widget on
/// every frame, about 5% CPU all day; `@State` animations also can't compile with the macOS 27
/// SDK on the Command Line Tools.) `--render` shows the dot without the ring.
private struct PulseRing: NSViewRepresentable {
    var color: NSColor
    var period: Double

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 9, height: 9))
        view.wantsLayer = true
        let ring = CAShapeLayer()
        ring.frame = view.bounds
        ring.path = CGPath(ellipseIn: view.bounds.insetBy(dx: 1, dy: 1), transform: nil)
        ring.fillColor = nil
        ring.lineWidth = 2
        view.layer?.addSublayer(ring)
        configure(ring)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let ring = view.layer?.sublayers?.first as? CAShapeLayer { configure(ring) }
    }

    private func configure(_ ring: CAShapeLayer) {
        ring.strokeColor = color.cgColor
        if ring.animation(forKey: "pulse")?.duration == period { return }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = 2.4
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.8
        fade.toValue = 0
        let pulse = CAAnimationGroup()
        pulse.animations = [grow, fade]
        pulse.duration = period
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulse.repeatCount = .infinity
        pulse.isRemovedOnCompletion = false
        ring.add(pulse, forKey: "pulse")
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
