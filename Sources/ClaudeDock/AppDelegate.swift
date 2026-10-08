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
    private var claudeCodeActivity: ClaudeCodeActivity?
    private var crabSessions: CrabSessions?
    private let hookFile = ClaudeCodeHookFile()

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
            effect: { [weak self] in self?.model.settings.effectStyle = $0 },
            amount: { [weak self] in self?.model.settings.effectAmount = $0 },
            pinch: { [weak self] in self?.dock.pinch($0, ended: $1) },
            showCrab: { [weak self] in self?.model.settings.showCrab = $0 },
            connectHooks: { [weak self] in self?.setHooks($0) }))

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
                self.crabSessions?.reload()
                let connected = self.hookFile.isConnected()   // settings.json can change behind our back
                if connected != self.model.hooksConnected { self.model.hooksConnected = connected }
            }
        }

        claudeCodeActivity = ClaudeCodeActivity { [weak self] time in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.model.claudeCodeWorked(at: time) } }
        }
        claudeCodeActivity?.start()
        model.hooksConnected = hookFile.isConnected()
        crabSessions = CrabSessions { [weak self] sessions in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.model.sessionsChanged(sessions) } }
        }
        crabSessions?.start()

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

    /// Adds or removes Claude Dock's hooks, after saying what Connect will change.
    private func setHooks(_ connect: Bool) {
        if connect {
            let alert = NSAlert()
            alert.messageText = "Connect to Claude Code?"
            alert.informativeText = """
                Claude Dock will add hooks to ~/.claude/settings.json. Each writes only what \
                Claude Code is doing (thinking, using a tool, waiting for you, done) and the time \
                to a file in Claude Dock's folder. Your prompts and transcripts are never read. \
                Your other hooks stay as they are. Disconnect removes them.
                """
            alert.addButton(withTitle: "Connect")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            try connect ? hookFile.connect() : hookFile.disconnect()
        } catch HookFileError.unreadable(let why) {
            let alert = NSAlert()
            alert.messageText = connect ? "Couldn't connect to Claude Code" : "Couldn't disconnect from Claude Code"
            alert.informativeText = why
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        model.hooksConnected = hookFile.isConnected()
        crabSessions?.reload()
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
