import AppKit
import Combine
import SwiftUI

/// Owns the two floating windows: the always-on widget and the panel it opens.
@MainActor
final class DockController {
    var onPanelOpened: (() -> Void)?

    private let model: AppModel
    private let widget = FloatingPanel(allowsKey: false)
    private let panel = FloatingPanel(allowsKey: true)
    private var monitors: [Any] = []
    private var changes: AnyCancellable?
    private var hiddenUntil: Date?

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

    /// Bottom-right corner of the primary display (the one with the menu bar; `NSScreen.main`
    /// follows keyboard focus between displays). With the Dock at the bottom, sit beside it
    /// at the same height; otherwise stay inside the visible frame so a side Dock isn't covered.
    private func layout() {
        guard let screen = NSScreen.screens.first, let content = widget.contentView else { return }
        let size = content.fittingSize
        let full = screen.frame, visible = screen.visibleFrame
        let dockAtBottom = visible.minY > full.minY + 1
        let origin = NSPoint(x: visible.maxX - size.width - 12, y: dockAtBottom ? full.minY + 6 : visible.minY + 12)
        widget.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.isVisible { placePanel() }
    }

    private func placePanel() {
        guard let content = panel.contentView, let screen = widget.screen ?? NSScreen.screens.first else { return }
        let size = content.fittingSize
        let bottom = widget.frame.maxY + 8
        let height = min(size.height, screen.visibleFrame.maxY - bottom - 8)
        panel.setFrame(NSRect(x: widget.frame.maxX - size.width, y: bottom, width: size.width, height: height), display: true)
    }
}
