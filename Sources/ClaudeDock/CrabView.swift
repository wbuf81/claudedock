import AppKit
import SwiftUI
import ClaudeDockCore

/// The crab acting out a mood. Core Animation flips through the frames in the window server,
/// so the app does no work per frame. With Reduce Motion, and in image renders (which can't
/// draw Core Animation), it holds the mood's first frame.
struct CrabView: View {
    var mood: CrabMood
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.renderStyle) private var renderStyle

    var body: some View {
        Group {
            if reduceMotion || renderStyle != .live {
                if let first = CrabSprites.frames(mood.rawValue).first {
                    Image(decorative: first, scale: 1).resizable().interpolation(.high)
                }
            } else {
                CrabLayer(mood: mood)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CrabLayer: NSViewRepresentable {
    var mood: CrabMood
    func makeNSView(context: Context) -> CrabLayerView { CrabLayerView() }
    func updateNSView(_ view: CrabLayerView, context: Context) { view.mood = mood }
}

final class CrabLayerView: NSView {
    private let sprite = CALayer()
    var mood: CrabMood? { didSet { if mood != oldValue { restart() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        sprite.contentsGravity = .resizeAspect
        sprite.minificationFilter = .trilinear
        layer?.addSublayer(sprite)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = bounds
        CATransaction.commit()
    }

    private func restart() {
        sprite.removeAllAnimations()
        guard let mood else { return }
        let frames = CrabSprites.frames(mood.rawValue)
        sprite.contents = frames.first
        guard frames.count > 1 else { return }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.calculationMode = .discrete
        animation.duration = CrabSprites.frameDuration * Double(frames.count)
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        sprite.add(animation, forKey: "frames")
    }
}
