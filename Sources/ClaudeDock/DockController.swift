import AppKit
import Combine
import SwiftUI
import ClaudeDockCore

/// Owns the two floating windows: the always-on widget and the panel it opens. The widget
/// window holds the compact and the full widget and shows one of them: the owner's choice,
/// switched from the Size menu or by dragging the widget's inner edge. Each is drawn with a
/// clear band on the crab's side, so the window is the glass plus that band.
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
    /// Where the glass of the compact and of the full widget goes, and the edges the widget
    /// grows from. The window is each glass plus the crab's band (`windowFrame`).
    private var frames: (compact: NSRect, full: NSRect, anchor: GrowthAnchor)?
    /// The glass of the size shown, at rest: what moving and snapping go by.
    private var glassFrame = NSRect.zero
    /// Where a resize drag started: the window frames of both sizes and the progress then.
    private var resizeStart: (compact: NSRect, full: NSRect, progress: CGFloat)?
    private var showingFull: Bool { !model.settings.compact }
    /// Counts grow and shrink animations, so one that was overtaken finishes quietly.
    private var generation = 0
    private var animating = false
    /// One level above the Dock (which draws over floating windows), for the full widget.
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
        container.onResize = { [weak self] phase in self?.resize(phase) }
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
        resizeStart = nil
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
            settleNow()
            dragStart = (mouse, widget.frame.origin)
            closePanel()
        }
        guard let start = dragStart else { return }
        widget.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
    }

    /// Near one of the six snap points the widget snaps there; anywhere else it stays put.
    func dragEnded() {
        guard let start = dragStart else { return }
        dragStart = nil
        guard let screen = NSScreen.screens.first, let frames else { return }
        // The glass, moved as far as the window was.
        let moved = glassFrame.offsetBy(dx: widget.frame.minX - start.origin.x, dy: widget.frame.minY - start.origin.y)
        // The spot is the compact widget's: when the full one is shown, the compact one is the
        // frame the full one grew from (this is also what `layout` places).
        let glass = showingFull
            ? WidgetPlacement.compactFrame(full: moved, size: frames.compact.size,
                                           anchor: WidgetPlacement.anchor(compact: moved, visible: screen.visibleFrame, spot: nil))
            : moved
        if let point = WidgetPlacement.snap(frame: glass, screen: screen.frame, visible: screen.visibleFrame,
                                            dockWidth: Self.dockWidth(on: screen)) {
            model.settings.widgetSpot = .snapped(point)
        } else {
            model.settings.widgetSpot = .free(WidgetPlacement.offset(origin: glass.origin, size: glass.size, screen: screen.frame))
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

    /// Shows the compact (true) or the full (false) widget, growing or shrinking to it.
    func setCompact(_ on: Bool) {
        settleNow()
        model.settings.compact = on
        animateSettle(from: widget.frame)
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

    // MARK: Resizing

    /// A drag on the inner edge. Pulling it toward the middle of the screen grows the widget:
    /// the window's frame and the crossfade between the two sizes follow the pointer. On
    /// release, past halfway is full and short of it is compact.
    private func resize(_ phase: ResizePhase) {
        switch phase {
        case .began:
            settleNow()
            guard let frames else { return }
            resizeStart = (windowFrame(frames.compact), windowFrame(frames.full), showingFull ? 1 : 0)
            fullHost.isHidden = false
            compactHost.isHidden = false
            widget.level = Self.aboveDock
        case .moved(let dx):
            guard let start = resizeStart, let frames else { return }
            let span = max(start.full.width - start.compact.width, 1)
            let pull = frames.anchor.horizontal == .right ? -dx : dx
            let progress = min(max(start.progress + pull / span, 0), 1)
            setResize(progress, frames: frames)
        case .ended:
            guard let start = resizeStart else { return }
            resizeStart = nil
            let progress = fullHost.alphaValue
            model.settings.compact = progress < 0.5   // triggers layout() via the settings sink
            animateSettle(from: Self.lerp(start.compact, start.full, progress))
        }
    }

    private func setResize(_ progress: CGFloat, frames: (compact: NSRect, full: NSRect, anchor: GrowthAnchor)) {
        let window = Self.lerp(windowFrame(frames.compact), windowFrame(frames.full), progress)
        widget.setFrame(window, display: true)
        fullHost.alphaValue = progress
        compactHost.alphaValue = 1 - progress
        placeHandle(glass: Self.lerp(frames.compact, frames.full, progress), in: window)
    }

    private static func lerp(_ a: NSRect, _ b: NSRect, _ t: CGFloat) -> NSRect {
        NSRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    /// Animates to the size the setting names: the window's frame changes while the two
    /// crossfade. With Reduce Motion only the crossfade runs: the window grows before it, and
    /// shrinks after it (in `layout`).
    private func animateSettle(from start: NSRect) {
        guard let frames else { return }
        if panel.isVisible { placePanel() }
        generation += 1
        let current = generation
        let growing = showingFull
        let target = windowFrame(growing ? frames.full : frames.compact)
        let incoming = growing ? fullHost : compactHost
        let outgoing = growing ? compactHost : fullHost
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if growing { widget.level = Self.aboveDock }
        incoming.isHidden = false
        outgoing.isHidden = false
        animating = true
        if widget.frame != start { widget.setFrame(start, display: true) }
        if reduceMotion, growing { widget.setFrame(target, display: true) }
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
                self.layout()  // settles the frame, hides the faded widget, sets the level
            }
        })
    }

    /// Cuts any animation short and puts the widget at rest at the size the setting names, so
    /// a drag starts from a settled window.
    private func settleNow() {
        guard animating else { return }
        generation += 1
        animating = false
        if let frames {
            let target = windowFrame(showingFull ? frames.full : frames.compact)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                widget.animator().setFrame(target, display: true)
                fullHost.animator().alphaValue = showingFull ? 1 : 0
                compactHost.animator().alphaValue = showingFull ? 0 : 1
            }
        }
        layout()
    }

    /// The window for a glass frame: the glass plus the crab's band.
    private func windowFrame(_ glass: NSRect) -> NSRect {
        WidgetPlacement.withCrabBand(glass, edge: model.crabEdge, depth: model.crabDepth)
    }

    // MARK: Layout

    /// Sizes the widget to the Dock bar and places it on the primary display (the one with the
    /// menu bar; `NSScreen.main` follows keyboard focus between displays): where the owner
    /// dragged it, or the bottom-right corner beside the Dock. The compact widget is placed and
    /// the full one grows out of it. All frames here are the glass; the window adds the band.
    private func layout() {
        // A resize whose mouse-up got lost would otherwise block layout for good.
        if resizeStart != nil, NSEvent.pressedMouseButtons & 1 == 0 { resize(.ended); return }
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
        guard dragStart == nil, resizeStart == nil, !animating else { return }
        let full = glassSize(fullHost), compactSize = glassSize(compactHost)
        let origin = WidgetPlacement.origin(size: compactSize, screen: screen.frame, visible: screen.visibleFrame,
                                            spot: settings.widgetSpot, dockWidth: Self.dockWidth(on: screen))
        let compact = NSRect(origin: origin, size: compactSize)
        let anchor = WidgetPlacement.anchor(compact: compact, visible: screen.visibleFrame, spot: settings.widgetSpot)
        let grown = WidgetPlacement.expandedFrame(compact: compact, size: full, anchor: anchor,
                                                  screen: screen.frame, visible: screen.visibleFrame)
        // The crab perches on the side facing the middle of the screen; the hosts re-measure
        // with the band on that side before the window is sized.
        let edge = WidgetPlacement.crabEdge(anchor: anchor, vertical: vertical)
        if model.crabEdge != edge {
            model.crabEdge = edge
            return
        }
        frames = (compact, grown, anchor)
        let showFull = showingFull
        let frame = windowFrame(showFull ? grown : compact)
        if frame != widget.frame { widget.setFrame(frame, display: false) }
        arrange(in: frame)
        compactHost.isHidden = showFull
        compactHost.alphaValue = showFull ? 0 : 1
        fullHost.isHidden = !showFull
        fullHost.alphaValue = showFull ? 1 : 0
        widget.level = showFull ? Self.aboveDock : .floating
        if panel.isVisible { placePanel() }
    }

    /// The glass of a host: its fitting size less the crab's band.
    private func glassSize(_ host: NSHostingView<WidgetView>) -> CGSize {
        var size = host.fittingSize
        switch model.crabEdge {
        case .top, .bottom: size.height -= model.crabDepth
        case .left, .right: size.width -= model.crabDepth
        }
        return size
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
        for (host, glass) in [(compactHost, frames.compact), (fullHost, frames.full)] {
            host.autoresizingMask = pin
            host.frame = windowFrame(glass).offsetBy(dx: -frame.minX, dy: -frame.minY)
        }
        glassFrame = showingFull ? frames.full : frames.compact
        placeHandle(glass: glassFrame, in: frame)
    }

    /// Puts the resize handle along the glass's inner edge (the side facing the middle of the
    /// screen), the glass's full height, and clear of the crab's band.
    private func placeHandle(glass: NSRect, in window: NSRect) {
        guard let frames else { return }
        let width: CGFloat = 6
        let x = frames.anchor.horizontal == .right ? glass.minX : glass.maxX - width
        container.handleFrame = NSRect(x: x - window.minX, y: glass.minY - window.minY, width: width, height: glass.height)
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
        let resting = frames.map { windowFrame(showingFull ? $0.full : $0.compact) } ?? widget.frame
        panel.setFrame(WidgetPlacement.panelFrame(panel: size, widget: resting, visible: screen.visibleFrame),
                       display: true)
    }
}
