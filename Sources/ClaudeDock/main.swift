import AppKit
import Foundation

MainActor.assumeIsolated {
    let arguments = CommandLine.arguments
    if let flag = arguments.firstIndex(of: "--render"), flag + 1 < arguments.count {
        Renderer.renderDemo(to: URL(fileURLWithPath: arguments[flag + 1]))
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
