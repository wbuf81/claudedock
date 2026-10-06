import ServiceManagement
import SwiftUI
import ClaudeDockCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    var setDemoMode: (Bool) -> Void
    var signInOut: () -> Void
    var dockAccessAllowed: () -> Bool
    var askDockAccess: () -> Void

    var body: some View {
        Form {
            Section("Organizations") {
                ForEach(settings.knownOrgs) { org in
                    Toggle(org.name, isOn: Binding(get: { settings.isShown(org) }, set: { show(org, $0) }))
                }
                Picker("Shared with the desktop app", selection: Binding(
                    get: { settings.primaryOrg ?? "" },
                    set: { settings.primaryOrg = $0; refreshOrgs() })) {
                    ForEach(settings.knownOrgs.filter { settings.isShown($0) }) { Text($0.name).tag($0.id) }
                }
            }
            Section("Notifications") {
                Toggle("When Claude Code should switch orgs", isOn: $settings.notifySwitch)
                Toggle("When Claude Code's org turns red", isOn: $settings.notifyRed)
            }
            Section("Thresholds") {
                threshold("Red when week left is under", \.redWeekLeft, "%")
                threshold("Red when running out this early", \.redRunsOutEarlyHours, "h")
                threshold("Red when the 5-hour window reaches", \.redSession, "%")
                threshold("Yellow when the 5-hour window reaches", \.yellowSession, "%")
                threshold("On pace when unused is under", \.onPaceUnused, "%")
                threshold("Normal pulse from unused", \.normalPulseUnused, "%")
                threshold("Fast pulse above unused", \.fastPulseUnused, "%")
                threshold("Suggest an org with week left of", \.eligibleWeekLeft, "%")
                threshold("…and its 5-hour window under", \.eligibleSessionBelow, "%")
                threshold("Desktop app buffer (week left)", \.primaryReserveWeekLeft, "%")
                Button("Reset to defaults") { settings.thresholds = Thresholds() }
            }
            Section("App") {
                // Bound straight to macOS rather than through @State, which the macOS 27 SDK
                // makes a macro the Command Line Tools can't expand.
                Toggle("Launch at login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { on in
                        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                        settings.objectWillChange.send()
                    }))
                Toggle("Demo mode (Pokémon sample data)", isOn: Binding(get: { settings.demoMode }, set: setDemoMode))
                if dockAccessAllowed() {
                    Text("Claude Dock can see the Dock's size and steps out of its way.")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Let Claude Dock see the Dock's size…", action: askDockAccess)
                }
                Button(model.signedIn ? "Sign out of claude.ai" : "Sign in to claude.ai", action: signInOut)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 640)
    }

    private func show(_ org: Org, _ on: Bool) {
        var ids = Set(settings.knownOrgs.filter { settings.isShown($0) }.map(\.id))
        if on { ids.insert(org.id) } else { ids.remove(org.id) }
        settings.shownOrgs = Array(ids)
        refreshOrgs()
    }

    private func refreshOrgs() {
        model.setAvailableOrgs(settings.knownOrgs, claudeCodeOrg: model.claudeCodeOrg)
    }

    private func threshold(_ label: String, _ key: WritableKeyPath<Thresholds, Double>, _ unit: String) -> some View {
        Stepper(value: Binding(get: { settings.thresholds[keyPath: key] },
                               set: { settings.thresholds[keyPath: key] = $0 }), in: 0...100, step: 1) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(settings.thresholds[keyPath: key]))\(unit)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}
