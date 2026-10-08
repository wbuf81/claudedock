import AppKit

/// How far a resize drag has gone: the pointer's travel since it began, in screen points.
enum ResizePhase {
    case began
    case moved(dx: CGFloat)
    case ended
}

/// The widget window's content: the compact and full widgets stacked, each at its own size,
/// with the resize handle on top along the glass's inner edge.
final class WidgetContainer: NSView {
    /// Reports a drag on the inner edge.
    var onResize: ((ResizePhase) -> Void)? {
        get { handle.onResize }
        set { handle.onResize = newValue }
    }

    /// Where the handle sits, in window coordinates: the glass's inner edge, never the crab's band.
    var handleFrame: NSRect {
        get { handle.frame }
        set { if handle.frame != newValue { handle.frame = newValue } }
    }

    private let handle = EdgeHandle()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(handle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The handle stays above the hosts, which are added after it.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if subview !== handle, handle.superview === self {
            addSubview(handle, positioned: .above, relativeTo: nil)
        }
    }
}

/// A 6 pt strip along the glass's inner edge. Dragging it resizes the widget; it shows the
/// left-right resize cursor, even while the app is inactive (the widget never becomes key).
final class EdgeHandle: NSView {
    var onResize: ((ResizePhase) -> Void)?
    private var start = NSPoint.zero
    private var dragging = false
    private var upMonitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func cursorUpdate(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseExited(with event: NSEvent) { if !dragging { NSCursor.arrow.set() } }

    /// Right clicks go to the widget underneath, so its menu opens here too.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let type = NSApp.currentEvent?.type, type == .rightMouseDown || type == .otherMouseDown { return nil }
        return super.hitTest(point)
    }

    // Screen coordinates, so the window changing size under the pointer doesn't disturb the drag.
    override func mouseDown(with event: NSEvent) {
        start = NSEvent.mouseLocation
        dragging = true
        // Backup in case the mouse-up goes elsewhere: the drag must always end.
        upMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.finish()
            return event
        }
        onResize?(.began)
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        onResize?(.moved(dx: now.x - start.x))
    }

    override func mouseUp(with event: NSEvent) { finish() }

    private func finish() {
        if let upMonitor { NSEvent.removeMonitor(upMonitor) }
        upMonitor = nil
        guard dragging else { return }
        dragging = false
        onResize?(.ended)
        let inside = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        (inside ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
    }
}
