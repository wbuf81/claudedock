import Combine
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
    /// The side the crab perches on; `DockController` sets it with the layout.
    @Published var crabEdge: CrabEdge = .top
    /// The crab's size, and how far it sticks out of the glass (its top 58%).
    var crabSize: CGFloat { 50 * widgetScale }
    var crabDepth: CGFloat { settings.showCrab ? crabSize * 0.58 : 0 }
    /// When Claude Code last wrote a transcript; it writes every few seconds while it works.
    private(set) var claudeCodeActiveAt: Date?
    /// Live Claude Code sessions, from Claude Dock's hooks.
    @Published private(set) var crabSessions: [CrabSession] = []
    /// Claude Dock's hooks are in Claude Code's settings.
    @Published var hooksConnected = false
    /// The crab's mood in a demo scenario.
    private var demoCrab: CrabMood?
    private var crabCheck: Timer?
    /// Each org's reading before its newest, to tell whether its usage just went up.
    private var previous: [String: Reading] = [:]
    private var settingsChanges: AnyCancellable?
    private var claudeCodeQuietChecks: [Timer] = []

    let settings: Settings
    let formatting = Formatting()
    var onAdvice: ((Advice) -> Void)?
    var onRed: ((Org) -> Void)?
    /// claude.ai ended the session on its own (not a sign-out from the menu).
    var onSignedOut: (() -> Void)?

    private let store: HistoryStore
    private var gate = AdviceGate()
    private var primaryOverride: String?
    private var session = SessionWatch()
    /// Demo data is on screen: real account details must stay out of it.
    private var showingDemo: Bool { primaryOverride != nil }
    private static let keep: TimeInterval = 35 * 24 * 3600
    /// The pace looks back 3 days and the chart shows one week, so only the last 8 days are
    /// kept in memory (and filtered on every redraw); the file keeps all 35.
    private static let inMemory: TimeInterval = 8 * 24 * 3600

    init(settings: Settings, store: HistoryStore) {
        self.settings = settings
        self.store = store
        try? store.prune(olderThan: Date().addingTimeInterval(-Self.keep))
        history = Self.recent(store.load(), now: Date())
        // The widget redraws when the in-use effect or its amount changes.
        settingsChanges = settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    private static func recent(_ readings: [Reading], now: Date) -> [Reading] {
        readings.filter { now.timeIntervalSince($0.time) < inMemory }
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

    /// The crab on this org, or nil: it shows on the org Claude Code is signed into while a
    /// session is live (or, without hooks, while Claude Code is writing transcripts).
    func crabMood(for org: Org) -> CrabMood? {
        guard settings.showCrab, !isStale, org.id == claudeCodeOrg else { return nil }
        if showingDemo { return demoCrab }
        return hooksConnected
            ? Crab.mood(crabSessions, isAlive: CrabSessions.isAlive, now: now)
            : Crab.fallbackMood(claudeCodeActiveAt: claudeCodeActiveAt, now: now)
    }

    /// Whether an org is being used right now; it gets the in-use effect. Claude Code's own
    /// activity shows as the crab instead, so only a rise in usage counts on the crab's org.
    func inUse(for org: Org) -> Bool {
        InUse.isInUse(org: org.id, latest: latest[org.id], previous: previous[org.id], claudeCodeOrg: claudeCodeOrg,
                      claudeCodeActiveAt: crabMood(for: org) == nil ? claudeCodeActiveAt : nil, stale: isStale, now: now)
    }

    /// The hooks wrote, or the sessions were re-read. Redraws now and when the mood next
    /// changes by itself ("done" ending, a stuck mood resting).
    func sessionsChanged(_ sessions: [CrabSession]) {
        crabSessions = sessions
        now = Date()
        crabCheck?.invalidate()
        if let next = Crab.nextChange(sessions, now: now) {
            crabCheck = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSince(now) + 0.2, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
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
                                 hidden: showingDemo ? [] : settings.knownOrgs.filter { org in !orgs.contains { $0.id == org.id } })
    }

    /// The org list from claude.ai: show the selected orgs, primary first. The first time,
    /// the org Claude Code is signed into becomes the primary org.
    func setAvailableOrgs(_ all: [Org], claudeCodeOrg: String?) {
        settings.knownOrgs = all
        let shown = OrgFilter.shown(all, choices: settings.orgChoices)
        if !shown.contains(where: { $0.id == settings.primaryOrg }) {
            settings.primaryOrg = shown.first(where: { $0.id == claudeCodeOrg })?.id ?? shown.first?.id
        }
        guard !showingDemo else { return }
        orgs = DisplayNames.short(shown).sorted { role(of: $0) == .primary && role(of: $1) != .primary }
    }

    /// A refresh round: keeps every reading it got, and says which orgs it couldn't read.
    func ingest(_ outcome: UsageRound.Outcome, claudeCodeOrg: String?, at time: Date) {
        let wasRed = currentOrgIsRed
        now = time
        self.claudeCodeOrg = claudeCodeOrg
        for r in outcome.readings {
            if let old = latest[r.org] { previous[r.org] = old }
            latest[r.org] = r
        }
        history = Self.recent(history + outcome.readings, now: time)
        try? store.append(outcome.readings)
        signedIn = true
        session.worked()
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

    /// claude.ai says the session is over. Worth a notification only if it worked earlier in
    /// this run, not when launching signed out.
    func sessionEnded() {
        signedIn = false
        clearProblems()
        if session.ended() { onSignedOut?() }
    }

    /// The owner signed out from the menu.
    func signedOut() {
        signedIn = false
        clearProblems()
        session = SessionWatch()
    }

    /// Whether an org's reading is current; an org that stopped reading keeps its last one.
    func isFresh(_ org: Org) -> Bool { latest[org.id]?.isFresh(now: now) ?? false }

    private func clearProblems() {
        problem = nil
        orgProblems = [:]
        refreshProblem = nil
    }

    func setClaudeCodeOrg(_ id: String?) {
        guard id != claudeCodeOrg, !showingDemo else { return }
        claudeCodeOrg = id
        updateAdvice()
    }

    /// Claude Code wrote a transcript. Publishes only when that starts its org's in-use
    /// effect (writes come every second or so while it works); a check just after the quiet
    /// period ends the effect on time.
    func claudeCodeWorked(at time: Date) {
        guard !showingDemo else { return }
        let wasWorking = claudeCodeActiveAt.map { time.timeIntervalSince($0) < InUse.claudeCodeQuiet } ?? false
        claudeCodeActiveAt = time
        if !wasWorking { now = time }
        claudeCodeQuietChecks.forEach { $0.invalidate() }
        // One just after the quiet period (the crab goes from tool to done), one after the
        // fallback "done" has ended too (the crab goes).
        claudeCodeQuietChecks = [InUse.claudeCodeQuiet + 0.5, InUse.claudeCodeQuiet + Crab.doneLasts + 0.5].map { delay in
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
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
        demoCrab = scenario.crab
        clearProblems()
        orgs = scenario.orgs
        latest = Dictionary(uniqueKeysWithValues: scenario.readings.map { ($0.org, $0) })
        previous = [:]
        claudeCodeActiveAt = scenario.claudeCodeWorking ? scenario.now : nil
        history = []
        claudeCodeOrg = scenario.claudeCodeOrg
        now = scenario.now
        signedIn = true
        advice = SwitchAdvisor.advice(statuses, claudeCodeOrg: claudeCodeOrg, now: now,
                                      formatting: formatting, settings.thresholds)
    }

    func leaveDemo() {
        primaryOverride = nil
        demoCrab = nil
        clearProblems()
        orgs = []
        latest = [:]
        previous = [:]
        claudeCodeActiveAt = nil
        advice = nil
        history = Self.recent(store.load(), now: Date())
        now = Date()
    }
}
