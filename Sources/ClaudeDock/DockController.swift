import AppKit
import Combine
import SwiftUI
import ClaudeDockCore

/// Owns the two floating windows: the always-on widget and the panel it opens.
@MainActor
final class DockController {
    var onPanelOpened: (() -> Void)?

    private let model: AppModel
    // No window shadow: the Dock has none, and on glass it reads as a dark outline.
    private let widget = FloatingPanel(allowsKey: false, shadow: false)
    private let panel = FloatingPanel(allowsKey: true)
    private var monitors: [Any] = []
    private var changes: AnyCancellable?
    private var hiddenUntil: Date?
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    init(model: AppModel, actions: WidgetActions) {
        self.model = model
        widget.contentView = NSHostingView(rootView: WidgetView(model: model, actions: actions))
        panel.contentView = NSHostingView(rootView: PanelView(model: model, actions: actions))
        changes = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.layout() } }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    func show() {
        hiddenUntil = nil
        layout()
        widget.orderFrontRegardless()
    }

    func hide(for seconds: TimeInterval) {
        closePanel()
        widget.orderOut(nil)
        let until = Date().addingTimeInterval(seconds)
        hiddenUntil = until
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated { if self?.hiddenUntil == until { self?.show() } }
        }
    }

    func togglePanel() { panel.isVisible ? closePanel() : openPanel() }

    func openPanel() {
        guard !panel.isVisible else { return }
        placePanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        onPanelOpened?()
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }) { monitors.append(outside) }
        if let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.closePanel() }
            return nil
        }) { monitors.append(escape) }
    }

    func closePanel() {
        panel.orderOut(nil)
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// Moves the widget with the mouse. Screen coordinates, so the window moving under the
    /// pointer doesn't disturb the drag.
    func dragChanged() {
        let mouse = NSEvent.mouseLocation
        if dragStart == nil {
            dragStart = (mouse, widget.frame.origin)
            closePanel()
        }
        guard let start = dragStart else { return }
        widget.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
    }

    func dragEnded() {
        dragStart = nil
        guard let screen = NSScreen.screens.first else { return }
        model.settings.widgetOffset = WidgetPlacement.offset(origin: widget.frame.origin, size: widget.frame.size, screen: screen.frame)
        layout()
    }

    func snapBack() {
        model.settings.widgetOffset = nil
        layout()
    }

    /// Sizes the widget to the Dock bar and places it on the primary display (the one with the
    /// menu bar; `NSScreen.main` follows keyboard focus between displays): where the owner
    /// dragged it, or the bottom-right corner beside the Dock.
    private func layout() {
        guard let screen = NSScreen.screens.first, let content = widget.contentView else { return }
        let tileSize = UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "tilesize") as? Double
        let height = DockFit.height(screen: screen.frame, visible: screen.visibleFrame, tileSize: tileSize)
        let scale = DockFit.contentScale(tileSize: tileSize)
        if abs(model.widgetHeight - height) > 0.5 || abs(model.widgetScale - scale) > 0.001 {
            model.widgetHeight = height  // these changes trigger another layout with the new size
            model.widgetScale = scale
            return
        }
        guard dragStart == nil else { return }
        let size = content.fittingSize
        let origin = WidgetPlacement.origin(size: size, screen: screen.frame, visible: screen.visibleFrame,
                                            saved: model.settings.widgetOffset)
        let frame = NSRect(origin: origin, size: size)
        if frame != widget.frame { widget.setFrame(frame, display: true) }
        if panel.isVisible { placePanel() }
    }

    private func placePanel() {
        guard let content = panel.contentView, let screen = widget.screen ?? NSScreen.screens.first else { return }
        panel.setFrame(WidgetPlacement.panelFrame(panel: content.fittingSize, widget: widget.frame,
                                                  visible: screen.visibleFrame), display: true)
    }
}
