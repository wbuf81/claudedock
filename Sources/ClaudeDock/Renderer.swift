import AppKit
import SwiftUI
import ClaudeDockCore

/// `ClaudeDock --render DIR` draws the widget and panel for every demo scenario, in dark
/// and light, as PNGs. A way to check the UI without screen-recording permission.
@MainActor
enum Renderer {
    static func renderDemo(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fixedNow = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 11, minute: 32))!
        let settings = Settings(defaults: UserDefaults(suiteName: "ClaudeDockRender")!)
        for scenario in DemoData.scenarios(now: fixedNow) {
            let model = AppModel(settings: settings, store: HistoryStore(url: dir.appendingPathComponent("render-history.jsonl")))
            model.apply(scenario)
            for scheme in [ColorScheme.dark, .light] {
                let suffix = scheme == .dark ? "dark" : "light"
                write(WidgetView(model: model, actions: .none), scheme, dir.appendingPathComponent("\(scenario.name)-widget-\(suffix).png"))
                write(WidgetView(model: model, actions: .none, compact: true), scheme,
                      dir.appendingPathComponent("\(scenario.name)-compact-\(suffix).png"))
                write(PanelView(model: model, actions: .none), scheme, dir.appendingPathComponent("\(scenario.name)-panel-\(suffix).png"))
            }
        }
        print("Rendered to \(dir.path)")
    }

    private static func write<V: View>(_ view: V, _ scheme: ColorScheme, _ url: URL) {
        let framed = view
            .environment(\.colorScheme, scheme)
            .environment(\.renderStyle, .solid)
            .padding(12)
            .background(scheme == .dark ? Color(white: 0.25) : Color(white: 0.85))
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}
