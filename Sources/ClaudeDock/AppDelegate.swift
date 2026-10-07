import AppKit
import ServiceManagement
import SwiftUI
import ClaudeDockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var dock: DockController!
    private var poller: Poller!
    private let session = ClaudeWebSession()
    private let notifier = Notifier()
    private var settingsWindow: NSWindow?
    private var demo: Task<Void, Never>?
    private var clock: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = Settings(defaults: .standard)
        model = AppModel(settings: settings, store: HistoryStore(url: HistoryStore.defaultURL))
        poller = Poller(model: model, session: session, account: ClaudeCodeAccount())
        dock = DockController(model: model, actions: WidgetActions(
            tap: { [weak self] in self?.dock.togglePanel() },
            refresh: { [weak self] in Task { await self?.poller.refresh() } },
            hide: { [weak self] in self?.dock.hide(for: 3600) },
            settings: { [weak self] in self?.showSettings() },
            signInOut: { [weak self] in self?.signInOrOut() },
            quit: { NSApp.terminate(nil) },
            dragChanged: { [weak self] in self?.dock.dragChanged() },
            dragEnded: { [weak self] in self?.dock.dragEnded() },
            place: { [weak self] in self?.dock.place($0) },
            layout: { [weak self] in self?.dock.setLayout($0) },
            size: { [weak self] in self?.dock.setSize($0) },
            compact: { [weak self] in self?.dock.setCompact($0) },
            pinch: { [weak self] in self?.dock.pinch($0, ended: $1) }))

        dock.onPanelOpened = { [weak self] in
            guard let self, !self.model.settings.demoMode else { return }
            if self.model.lastUpdated.map({ Date().timeIntervalSince($0) > 30 }) ?? true {
                Task { await self.poller.refresh() }
            }
        }
        session.onSignedIn = { [weak self] in self?.poller.restartAfterSignIn() }
        notifier.onClick = { [weak self] in
            guard let self else { return }
            if self.model.signedIn { self.dock.openPanel() } else { self.session.showSignIn() }
        }
        notifier.start()
        model.onSignedOut = { [weak self] in
            self?.notifier.post("Claude Dock was signed out", "claude.ai ended the session. Click to sign in again.")
        }
        model.onAdvice = { [weak self] advice in
            guard let self, self.model.settings.notifySwitch else { return }
            self.notifier.post("Move Claude Code to \(advice.target.name)", advice.reason)
        }
        model.onRed = { [weak self] org in
            guard let self, self.model.settings.notifyRed else { return }
            self.notifier.post("\(org.name) is nearly out", "Claude Code is signed into \(org.name), which just turned red.")
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.settings.demoMode else { return }
                self.poller.start()
            }
        }
        clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.settings.demoMode else { return }
                self.model.tick()
            }
        }

        registerLoginItemOnce()
        dock.show()
        // For checking the panel without a click: CLAUDEDOCK_OPEN_PANEL=1.
        if ProcessInfo.processInfo.environment["CLAUDEDOCK_OPEN_PANEL"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.dock.openPanel() }
        }
        if settings.demoMode {
            startDemo()
        } else {
            Task {
                await poller.refresh()
                if !model.signedIn { session.showSignIn() }
                poller.start(immediately: false)
            }
        }
    }

    private func signInOrOut() {
        if model.signedIn {
            Task {
                await session.signOut()
                model.signedOut()
            }
        } else {
            session.showSignIn()
        }
    }

    private func setDemoMode(_ on: Bool) {
        model.settings.demoMode = on
        if on {
            poller.stop()
            startDemo()
        } else {
            demo?.cancel()
            model.leaveDemo()
            poller.start()
        }
    }

    private func startDemo() {
        demo?.cancel()
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

    private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(model: model, settings: model.settings,
                                    setDemoMode: { [weak self] in self?.setDemoMode($0) },
                                    signInOut: { [weak self] in self?.signInOrOut() },
                                    refresh: { [weak self] in Task { await self?.poller.refresh() } })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Claude Dock Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Claude Dock launches at login once it's installed: the first launch from an
    /// Applications folder registers it, then Settings has the switch. A copy run from the
    /// build folder doesn't, so a login item never points at a build that may be deleted.
    private func registerLoginItemOnce() {
        let path = Bundle.main.bundleURL.path
        let installed = path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
        guard Bundle.main.bundleIdentifier != nil, installed,
              !UserDefaults.standard.bool(forKey: "loginItemOffered") else { return }
        UserDefaults.standard.set(true, forKey: "loginItemOffered")
        try? SMAppService.mainApp.register()
    }
}
