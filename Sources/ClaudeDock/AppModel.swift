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
    /// What went wrong on the last refresh, for the panel; nil when it all worked.
    @Published private(set) var problem: String?
    /// Why an org has no reading, for the widget's caption.
    @Published private(set) var orgProblems: [String: RefreshProblem] = [:]
    /// Why nothing could be read at all, for the widget's placeholder.
    @Published private(set) var refreshProblem: RefreshProblem?
    @Published var now = Date()
    /// The widget's contents are drawn for a 60 pt height and scaled by this to match the
    /// Dock's icon size; the widget itself is `widgetHeight` tall, matching the Dock bar.
    @Published var widgetScale: CGFloat = 1
    @Published var widgetHeight: CGFloat = 60
    /// Stacked as a narrow strip, for the left and right edges.
    @Published var vertical = false

    let settings: Settings
    let formatting = Formatting()
    var onAdvice: ((Advice) -> Void)?
    var onRed: ((Org) -> Void)?
    /// claude.ai ended the session on its own (not a sign-out from the menu).
    var onSignedOut: (() -> Void)?

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
                                 formatting: formatting, settings.thresholds,
                                 hidden: settings.knownOrgs.filter { org in !orgs.contains { $0.id == org.id } })
    }

    /// The org list from claude.ai: show the selected orgs, primary first. The first time,
    /// the org Claude Code is signed into becomes the primary org.
    func setAvailableOrgs(_ all: [Org], claudeCodeOrg: String?) {
        settings.knownOrgs = all
        let shown = OrgFilter.shown(all, choices: settings.orgChoices)
        if !shown.contains(where: { $0.id == settings.primaryOrg }) {
            settings.primaryOrg = shown.first(where: { $0.id == claudeCodeOrg })?.id ?? shown.first?.id
        }
        orgs = DisplayNames.short(shown).sorted { role(of: $0) == .primary && role(of: $1) != .primary }
    }

    /// A refresh round: keeps every reading it got, and says which orgs it couldn't read.
    func ingest(_ outcome: UsageRound.Outcome, claudeCodeOrg: String?, at time: Date) {
        let wasRed = currentOrgIsRed
        now = time
        self.claudeCodeOrg = claudeCodeOrg
        for r in outcome.readings { latest[r.org] = r }
        history.append(contentsOf: outcome.readings)
        try? store.append(outcome.readings)
        signedIn = true
        problem = Copy.problem(outcome.failures, shown: orgs.count)
        orgProblems = Dictionary(outcome.failures.map { ($0.org.id, $0.problem) }, uniquingKeysWith: { a, _ in a })
        refreshProblem = outcome.readings.isEmpty ? outcome.failures.first?.problem : nil
        updateAdvice()
        if !wasRed, currentOrgIsRed, let org = orgs.first(where: { $0.id == claudeCodeOrg }) { onRed?(org) }
    }

    /// Nothing could be read this time (not even the org list).
    func refreshFailed(_ problem: RefreshProblem) {
        self.problem = Copy.problem(problem)
        refreshProblem = problem
    }

    /// claude.ai says the session is over.
    func sessionEnded() {
        guard signedIn else { return }
        signedIn = false
        onSignedOut?()
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
