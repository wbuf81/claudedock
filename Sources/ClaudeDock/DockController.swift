import AppKit
import Combine
import SwiftUI
import ClaudeDockCore

/// Owns the two floating windows: the always-on widget and the panel it opens. The widget
/// window holds the compact and the full widget. In compact mode it shows the compact one
/// and grows to the full one while the pointer rests on it or the panel is open.
@MainActor
final class DockController {
    var onPanelOpened: (() -> Void)?

    private let model: AppModel
    // No window shadow: the Dock has none, and on glass it reads as a dark outline.
    private let widget = FloatingPanel(allowsKey: false, shadow: false)
    private let container = WidgetContainer()
    private let fullHost: NSHostingView<WidgetView>
    private let compactHost: NSHostingView<WidgetView>
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
    /// Where the compact and the full widget go, and the edges the widget grows from. With
    /// compact mode off, both are the full widget's frame.
    private var frames: (compact: NSRect, full: NSRect, anchor: GrowthAnchor)?
    /// Compact mode is showing the full widget: the pointer rests on it, or the panel is open.
    private var expanded = false
    private var pointerInside = false
    private var hoverWork: DispatchWorkItem?
    /// Counts grow and shrink animations, so one that was overtaken finishes quietly.
    private var generation = 0
    private var animating = false
    /// One level above the Dock (which draws over floating windows), for the expanded widget.
    private static let aboveDock = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)

    init(model: AppModel, actions: WidgetActions) {
        self.model = model
        fullHost = NSHostingView(rootView: WidgetView(model: model, actions: actions))
        compactHost = NSHostingView(rootView: WidgetView(model: model, actions: actions, compact: true))
        for host in [compactHost, fullHost] {
            // Only reports its size (for `fittingSize`); `arrange` sets its frame, so each keeps
            // its size (and SwiftUI doesn't re-lay it out) while the window grows and shrinks
            // around it. With no sizing options at all it would report zero.
            host.sizingOptions = [.intrinsicContentSize]
            container.addSubview(host)
        }
        widget.contentView = container
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
        container.onHover = { [weak self] inside in self?.pointerMoved(inside: inside) }
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
        // Apps that open or quit change the Dock's width.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.layout() }
            }
        }
    }

    func show() {
        hiddenUntil = nil
        layout()
        widget.orderFrontRegardless()
    }

    func hide(for seconds: TimeInterval) {
        hoverWork?.cancel()
        expanded = false
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
        hoverWork?.cancel()
        setExpanded(true)
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
        // The widget stayed full size for the panel: shrink it unless the pointer is on it.
        recheckPointer()
    }

    /// Moves the widget with the mouse. Screen coordinates, so the window moving under the
    /// pointer doesn't disturb the drag. In compact mode the compact widget is what moves.
    func dragChanged() {
        let mouse = NSEvent.mouseLocation
        if dragStart == nil {
            hoverWork?.cancel()
            collapseForDrag()
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
        if let point = WidgetPlacement.snap(frame: widget.frame, screen: screen.frame, visible: screen.visibleFrame,
                                            dockWidth: Self.dockWidth(on: screen)) {
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

    func setCompact(_ on: Bool) {
        hoverWork?.cancel()
        expanded = false
        model.settings.compact = on
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

    // MARK: Growing and shrinking

    /// The pointer came onto the widget or left it. In compact mode the widget grows once
    /// the pointer has rested on it for 0.25 s, and shrinks 0.4 s after it leaves (not while
    /// the panel is open).
    private func pointerMoved(inside: Bool) {
        pointerInside = inside
        hoverWork?.cancel()
        guard model.settings.compact, dragStart == nil, inside != expanded, inside || !panel.isVisible else { return }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.setExpanded(inside) } }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.25 : 0.4), execute: work)
    }

    /// After the widget moves, changes size or the panel closes, the pointer may be
    /// somewhere else without an enter or exit event to say so.
    private func recheckPointer() {
        pointerMoved(inside: widget.isVisible && widget.frame.contains(NSEvent.mouseLocation))
    }

    /// Grows to the full widget or shrinks back to the compact one: the window's frame
    /// animates while the two crossfade. With Reduce Motion only the crossfade runs: the
    /// window grows before it, and shrinks after it (in `layout`).
    private func setExpanded(_ expand: Bool) {
        guard model.settings.compact, expand != expanded, dragStart == nil, let frames else { return }
        expanded = expand
        generation += 1
        let current = generation
        let target = expand ? frames.full : frames.compact
        let incoming = expand ? fullHost : compactHost
        let outgoing = expand ? compactHost : fullHost
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if expand { widget.level = Self.aboveDock }
        incoming.isHidden = false
        animating = true
        // Clip both widgets to the window's rounded shape while it changes size.
        container.layer?.masksToBounds = true
        if reduceMotion, expand { widget.setFrame(target, display: true) }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0.2 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if !reduceMotion { widget.animator().setFrame(target, display: true) }
            incoming.animator().alphaValue = 1
            outgoing.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.animating = false
                self.container.layer?.masksToBounds = false
                self.layout()  // settles the frame, hides the faded widget, sets the level
                self.recheckPointer()
            }
        })
    }

    /// A drag moves the compact widget: drop to it at once, overriding any animation under
    /// way. The full widget stays in the window, transparent, until the drag ends, so a drag
    /// that started on it keeps getting events.
    private func collapseForDrag() {
        guard model.settings.compact, expanded || animating, let frames else { return }
        generation += 1
        animating = false
        expanded = false
        container.layer?.masksToBounds = false
        widget.level = .floating
        compactHost.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            widget.animator().setFrame(frames.compact, display: true)
            compactHost.animator().alphaValue = 1
            fullHost.animator().alphaValue = 0
        }
    }

    // MARK: Layout

    /// Sizes the widget to the Dock bar and places it on the primary display (the one with the
    /// menu bar; `NSScreen.main` follows keyboard focus between displays): where the owner
    /// dragged it, or the bottom-right corner beside the Dock. In compact mode the compact
    /// widget is placed and the full one grows out of it.
    private func layout() {
        guard let screen = NSScreen.screens.first else { return }
        let settings = model.settings
        let tileSize = UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "tilesize") as? Double
        // The owner's size, shrunk only if the full widget wouldn't fit on screen (size
        // measured from what's drawn now, divided back to scale 1).
        let current = fullHost.fittingSize
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
        guard dragStart == nil, !animating else { return }
        let full = fullHost.fittingSize
        let compactSize = settings.compact ? compactHost.fittingSize : full
        let origin = WidgetPlacement.origin(size: compactSize, screen: screen.frame, visible: screen.visibleFrame,
                                            spot: settings.widgetSpot, dockWidth: Self.dockWidth(on: screen))
        let compact = NSRect(origin: origin, size: compactSize)
        let anchor = WidgetPlacement.anchor(compact: compact, visible: screen.visibleFrame, spot: settings.widgetSpot)
        let grown = settings.compact
            ? WidgetPlacement.expandedFrame(compact: compact, size: full, anchor: anchor,
                                            screen: screen.frame, visible: screen.visibleFrame)
            : compact
        frames = (compact, grown, anchor)
        if !settings.compact { expanded = false }
        let showFull = !settings.compact || expanded
        let frame = showFull ? grown : compact
        if frame != widget.frame { widget.setFrame(frame, display: false) }
        arrange(in: frame)
        compactHost.isHidden = showFull
        compactHost.alphaValue = showFull ? 0 : 1
        fullHost.isHidden = !showFull
        fullHost.alphaValue = showFull ? 1 : 0
        widget.level = settings.compact && expanded ? Self.aboveDock : .floating
        if panel.isVisible { placePanel() }
    }

    /// Puts each widget at its own place inside a window at `frame`, pinned to the edges the
    /// widget grows from, so both stay put on screen while the window changes size.
    private func arrange(in frame: NSRect) {
        guard let frames else { return }
        var pin: NSView.AutoresizingMask = frames.anchor.horizontal == .right ? .minXMargin : .maxXMargin
        switch frames.anchor.vertical {
        case .bottom: pin.insert(.maxYMargin)
        case .top: pin.insert(.minYMargin)
        case .center: pin.formUnion([.minYMargin, .maxYMargin])
        }
        for (host, place) in [(compactHost, frames.compact), (fullHost, frames.full)] {
            host.autoresizingMask = pin
            host.frame = place.offsetBy(dx: -frame.minX, dy: -frame.minY)
        }
        container.layer?.cornerRadius = model.vertical ? 22 * model.widgetScale : model.widgetHeight * 0.27
    }

    /// The Dock's estimated width, from its settings and the apps running now.
    private static func dockWidth(on screen: NSScreen) -> Double? {
        let dock = UserDefaults(suiteName: "com.apple.dock")
        // Spacers and web apps have no bundle id but still take a slot.
        func apps(_ key: String) -> [String] {
            (dock?.array(forKey: key) as? [[String: Any]] ?? []).enumerated().map { index, tile in
                (tile["tile-data"] as? [String: Any])?["bundle-identifier"] as? String ?? "\(key)-\(index)"
            }
        }
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier)
        let contents = DockFit.contents(pinned: apps("persistent-apps"), recent: apps("recent-apps"), running: running,
                                        folders: dock?.array(forKey: "persistent-others")?.count ?? 0,
                                        showRecents: dock?.object(forKey: "show-recents") as? Bool ?? true)
        return DockFit.estimatedWidth(items: contents.items, dividers: contents.dividers,
                                      screen: screen.frame, visible: screen.visibleFrame)
    }

    private func placePanel() {
        guard let screen = widget.screen ?? NSScreen.screens.first else { return }
        let size = panelContent.fittingSize
        if panelContent.frame.size != size { panelContent.frame = NSRect(origin: .zero, size: size) }
        // Against where the widget is going, not where an animation has it right now.
        let resting = frames.map { expanded || !model.settings.compact ? $0.full : $0.compact } ?? widget.frame
        panel.setFrame(WidgetPlacement.panelFrame(panel: size, widget: resting, visible: screen.visibleFrame),
                       display: true)
    }
}
