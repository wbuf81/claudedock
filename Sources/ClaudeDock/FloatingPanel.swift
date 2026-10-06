import AppKit

/// A borderless panel that floats on every Space, including over full-screen apps, and
/// never activates the app, so clicking it doesn't take focus from what you're doing.
final class FloatingPanel: NSPanel {
    private let allowsKey: Bool

    init(allowsKey: Bool, shadow: Bool = true) {
        self.allowsKey = allowsKey
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = shadow
        hidesOnDeactivate = false
        isMovable = false
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
