import AppKit
import ClaudeDockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var dock: DockController!
    private var demo: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel(settings: Settings(defaults: .standard), store: HistoryStore(url: HistoryStore.defaultURL))
        dock = DockController(model: model, actions: WidgetActions(
            tap: { [weak self] in self?.dock.togglePanel() },
            hide: { [weak self] in self?.dock.hide(for: 3600) },
            quit: { NSApp.terminate(nil) }))
        dock.show()
        demo = Task { [weak self] in
            var index = 0
            while !Task.isCancelled {
                guard let self else { return }
                let scenarios = DemoData.scenarios()
                self.model.apply(scenarios[index % scenarios.count])
                index += 1
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }
}
