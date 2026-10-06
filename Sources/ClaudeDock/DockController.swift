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
    private let panelContent: NSHostingView<PanelView>
    private var monitors: [Any] = []
    private var changes: AnyCancellable?
    private var hiddenUntil: Date?
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var pinchFactor: Double = 1
    /// The owner scale the widget is drawn at now, after fitting it on screen.
    private var appliedScale: Double = 1
    private var settingsChanges: AnyCancellable?

    init(model: AppModel, actions: WidgetActions) {
        self.model = model
        widget.contentView = NSHostingView(rootView: WidgetView(model: model, actions: actions))
        // The panel scrolls when the screen is too short for it (a 13-inch laptop, three orgs).
        panelContent = NSHostingView(rootView: PanelView(model: model, actions: actions))
        let scroll = NSScrollView()
        scroll.documentView = panelContent
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        panel.contentView = scroll
        changes = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.layout() } }
        }
        settingsChanges = model.settings.objectWillChange.sink { [weak self] _ in
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
        panelContent.scroll(.zero)
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

    /// Near one of the six snap points the widget snaps there; anywhere else it stays put.
    func dragEnded() {
        dragStart = nil
        guard let screen = NSScreen.screens.first else { return }
        if let point = WidgetPlacement.snap(frame: widget.frame, screen: screen.frame, visible: screen.visibleFrame) {
            model.settings.widgetSpot = .snapped(point)
        } else {
            model.settings.widgetSpot = .free(WidgetPlacement.offset(origin: widget.frame.origin, size: widget.frame.size,
                                                                     screen: screen.frame))
        }
        layout()
    }

    func place(_ point: SnapPoint) {
        model.settings.widgetSpot = .snapped(point)
        layout()
    }

    func setLayout(_ choice: LayoutChoice) {
        model.settings.layoutChoice = choice
        layout()
    }

    func setSize(_ scale: Double) {
        model.settings.sizeScale = WidgetLayout.clampSize(scale)
        layout()
    }

    /// Resizes live while pinching, and keeps the size when the pinch ends.
    func pinch(_ magnification: Double, ended: Bool) {
        if ended {
            pinchFactor = 1
            model.settings.sizeScale = WidgetLayout.clampSize(model.settings.sizeScale * magnification)
        } else {
            pinchFactor = WidgetLayout.clampSize(model.settings.sizeScale * magnification) / model.settings.sizeScale
        }
        layout()
    }

    /// Sizes the widget to the Dock bar and places it on the primary display (the one with the
    /// menu bar; `NSScreen.main` follows keyboard focus between displays): where the owner
    /// dragged it, or the bottom-right corner beside the Dock.
    private func layout() {
        guard let screen = NSScreen.screens.first, let content = widget.contentView else { return }
        let settings = model.settings
        let tileSize = UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "tilesize") as? Double
        // The owner's size, shrunk only if the widget wouldn't fit on screen (size measured
        // from what's drawn now, divided back to scale 1).
        let current = content.fittingSize
        let natural = CGSize(width: current.width / appliedScale, height: current.height / appliedScale)
        let ownerScale = WidgetLayout.fittedScale(settings.sizeScale * pinchFactor, natural: natural,
                                                  visible: screen.visibleFrame)
        let height = DockFit.height(screen: screen.frame, visible: screen.visibleFrame, tileSize: tileSize) * ownerScale
        let scale = DockFit.contentScale(screen: screen.frame, visible: screen.visibleFrame, tileSize: tileSize) * ownerScale
        let vertical = WidgetLayout.isVertical(spot: settings.widgetSpot, choice: settings.layoutChoice)
        if abs(model.widgetHeight - height) > 0.5 || abs(model.widgetScale - scale) > 0.001 || model.vertical != vertical {
            model.widgetHeight = height  // these changes trigger another layout with the new size
            model.widgetScale = scale
            model.vertical = vertical
            appliedScale = ownerScale
            return
        }
        guard dragStart == nil else { return }
        let origin = WidgetPlacement.origin(size: content.fittingSize, screen: screen.frame,
                                            visible: screen.visibleFrame, spot: settings.widgetSpot)
        let frame = NSRect(origin: origin, size: content.fittingSize)
        if frame != widget.frame { widget.setFrame(frame, display: true) }
        if panel.isVisible { placePanel() }
    }

    private func placePanel() {
        guard let screen = widget.screen ?? NSScreen.screens.first else { return }
        let size = panelContent.fittingSize
        if panelContent.frame.size != size { panelContent.frame = NSRect(origin: .zero, size: size) }
        panel.setFrame(WidgetPlacement.panelFrame(panel: size, widget: widget.frame, visible: screen.visibleFrame),
                       display: true)
    }
}
