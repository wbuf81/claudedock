import AppKit

/// The widget window's content: the compact and full widgets stacked, each at its own size.
/// Reports the pointer coming onto it and leaving, even while the app is inactive (the widget
/// never becomes key).
final class WidgetContainer: NSView {
    var onHover: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
