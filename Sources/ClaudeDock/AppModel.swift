import Foundation
import ClaudeDockCore

/// Everything the widget and panel show: orgs, readings, and what's derived from them.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var orgs: [Org] = []
    @Published private(set) var latest: [String: Reading] = [:]
    @Published private(set) var history: [Reading] = []
    @Published private(set) var claudeCodeOrg: String?
    @Published private(set) var advice: Advice?
    @Published var signedIn = true
    @Published var lastError: String?
    @Published var now = Date()
    /// The widget's contents are drawn for a 60 pt height and scaled by this to match the
    /// Dock's icon size; the widget itself is `widgetHeight` tall, matching the Dock bar.
    @Published var widgetScale: CGFloat = 1
    @Published var widgetHeight: CGFloat = 60

    let settings: Settings
    let formatting = Formatting()
    var onAdvice: ((Advice) -> Void)?
    var onRed: ((Org) -> Void)?

    private let store: HistoryStore
    private var gate = AdviceGate()
    private var primaryOverride: String?
    private static let keep: TimeInterval = 35 * 24 * 3600

    init(settings: Settings, store: HistoryStore) {
        self.settings = settings
        self.store = store
        try? store.prune(olderThan: Date().addingTimeInterval(-Self.keep))
        history = store.load()
    }

    var lastUpdated: Date? { latest.values.map(\.time).max() }

    /// Signed out, or nothing newer than 10 minutes.
    var isStale: Bool { !signedIn || (lastUpdated.map { now.timeIntervalSince($0) > 600 } ?? true) }

    func role(of org: Org) -> Role { org.id == (primaryOverride ?? settings.primaryOrg) ? .primary : .overflow }
    func reading(for org: Org) -> Reading? { latest[org.id]?.adjusted(to: now) }
    func forecast(for org: Org) -> WeekForecast? {
        reading(for: org).flatMap { Pace.forecast($0, history: history, now: now) }
    }
    func light(for org: Org) -> Light? {
        reading(for: org).map { Stoplight.light($0, forecast(for: org), settings.thresholds) }
    }

    var statuses: [OrgStatus] {
        orgs.compactMap { org in
            guard let r = reading(for: org), let l = light(for: org) else { return nil }
            return OrgStatus(org: org, role: role(of: org), reading: r, light: l)
        }
    }

    var statusLine: String {
        SwitchAdvisor.statusLine(statuses, claudeCodeOrg: claudeCodeOrg, advice: advice, now: now,
                                 formatting: formatting, settings.thresholds)
    }

    /// The org list from claude.ai: show the selected orgs, primary first. The first time,
    /// the org Claude Code is signed into becomes the primary org.
    func setAvailableOrgs(_ all: [Org], claudeCodeOrg: String?) {
        settings.knownOrgs = all
        let shown = all.filter { settings.isShown($0) }
        if !shown.contains(where: { $0.id == settings.primaryOrg }) {
            settings.primaryOrg = shown.first(where: { $0.id == claudeCodeOrg })?.id ?? shown.first?.id
        }
        orgs = DisplayNames.short(shown).sorted { role(of: $0) == .primary && role(of: $1) != .primary }
    }

    func ingest(_ readings: [Reading], claudeCodeOrg: String?, at time: Date) {
        let wasRed = currentOrgIsRed
        now = time
        self.claudeCodeOrg = claudeCodeOrg
        for r in readings { latest[r.org] = r }
        history.append(contentsOf: readings)
        try? store.append(readings)
        signedIn = true
        lastError = nil
        updateAdvice()
        if !wasRed, currentOrgIsRed, let org = orgs.first(where: { $0.id == claudeCodeOrg }) { onRed?(org) }
    }

    func setClaudeCodeOrg(_ id: String?) {
        guard id != claudeCodeOrg else { return }
        claudeCodeOrg = id
        updateAdvice()
    }

    func tick() { now = Date() }

    private var currentOrgIsRed: Bool { statuses.first { $0.org.id == claudeCodeOrg }?.light == .red }

    private func updateAdvice() {
        let candidate = SwitchAdvisor.advice(statuses, claudeCodeOrg: claudeCodeOrg, now: now,
                                             formatting: formatting, settings.thresholds)
        let previous = advice
        advice = gate.update(candidate, claudeCodeOrg: claudeCodeOrg, currentIsRed: currentOrgIsRed, now: now)
        if let advice, advice.target != previous?.target { onAdvice?(advice) }
    }

    // MARK: Demo mode

    func apply(_ scenario: DemoScenario) {
        primaryOverride = scenario.primary
        orgs = scenario.orgs
        latest = Dictionary(uniqueKeysWithValues: scenario.readings.map { ($0.org, $0) })
        history = []
        claudeCodeOrg = scenario.claudeCodeOrg
        now = scenario.now
        signedIn = true
        advice = SwitchAdvisor.advice(statuses, claudeCodeOrg: claudeCodeOrg, now: now,
                                      formatting: formatting, settings.thresholds)
    }

    func leaveDemo() {
        primaryOverride = nil
        orgs = []
        latest = [:]
        advice = nil
        history = store.load()
        now = Date()
    }
}
