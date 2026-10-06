import AppKit
import ApplicationServices
import os
import ClaudeDockCore

/// Reads the Dock's real frame through the Accessibility API, so the widget can step out of
/// the Dock's way as apps open and the Dock grows. Needs the owner's one-time Accessibility
/// permission; it only ever reads the Dock's position and size.
@MainActor
final class DockWatcher {
    var onChange: (() -> Void)?
    /// The Dock's icon bar in screen coordinates, or nil when unknown (no permission yet).
    private(set) var frame: CGRect?

    private var timer: Timer?
    private let log = Logger(subsystem: "com.wbuf81.claudedock", category: "dock")

    var isAllowed: Bool { AXIsProcessTrusted() }

    /// Shows macOS's Accessibility prompt and opens the matching Settings pane.
    func requestAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if !AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary),
           let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(pane)
        }
    }

    func start() {
        log.notice("Accessibility access at start: \(self.isAllowed, privacy: .public)")
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        let latest = readFrame()
        guard latest != frame else { return }
        frame = latest
        log.notice("Dock frame \(latest.map(\.debugDescription) ?? "unknown", privacy: .public), access \(self.isAllowed, privacy: .public)")
        onChange?()
    }

    private func readFrame() -> CGRect? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let primary = NSScreen.screens.first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let list = children(of: app).first(where: { string($0, kAXRoleAttribute) == kAXListRole }),
              let origin = point(list), let size = size(list) else { return nil }
        return DockFit.screenFrame(fromAccessibility: CGRect(origin: origin, size: size),
                                   primaryHeight: primary.frame.height)
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private func point(_ element: AXUIElement) -> CGPoint? {
        guard let value = axValue(element, kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private func size(_ element: AXUIElement) -> CGSize? {
        guard let value = axValue(element, kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }
}
