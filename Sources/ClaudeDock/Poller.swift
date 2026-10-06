import Foundation
import ClaudeDockCore

/// Reads claude.ai every 3 minutes (backing off on errors) and watches which org Claude
/// Code is signed into.
@MainActor
final class Poller {
    private let model: AppModel
    private let session: ClaudeWebSession
    private let account: ClaudeCodeAccount
    private var loop: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private var failures = 0
    private var orgsFetchedAt: Date?
    private var accountModified: Date?
    private var inFlight: Task<Void, Never>?
    private let delays: [TimeInterval] = [180, 360, 720, 900]

    init(model: AppModel, session: ClaudeWebSession, account: ClaudeCodeAccount) {
        self.model = model
        self.session = session
        self.account = account
    }

    /// Starts or restarts polling. With `immediately: false` the first refresh waits one interval.
    func start(immediately: Bool = true) {
        loop?.cancel()
        loop = Task { [weak self] in
            var refreshNow = immediately
            while !Task.isCancelled {
                guard let self else { return }
                if refreshNow { await self.refresh() }
                refreshNow = true
                try? await Task.sleep(for: .seconds(self.delays[min(self.failures, self.delays.count - 1)]))
            }
        }
        if watcher == nil {
            watcher = Task { [weak self] in
                while !Task.isCancelled {
                    self?.checkAccount()
                    try? await Task.sleep(for: .seconds(10))
                }
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Refreshes, or waits for the refresh already running (the loop, the Refresh button,
    /// opening the panel and Settings can all ask at once).
    func refresh() async {
        if let inFlight { return await inFlight.value }
        let task = Task { await refreshNow() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func refreshNow() async {
        guard !model.settings.demoMode else { return }
        do {
            if model.orgs.isEmpty || (orgsFetchedAt.map { Date().timeIntervalSince($0) > 86_400 } ?? true) {
                let all = try UsageParser.orgs(from: try await session.getJSON("/api/organizations"))
                model.setAvailableOrgs(all, claudeCodeOrg: account.currentOrg())
                orgsFetchedAt = Date()
            }
            let now = Date()
            let outcome = try await UsageRound.run(model.orgs, at: now) { [session] org in
                try await session.getJSON("/api/organizations/\(org.id)/usage")
            }
            // A JSON 403 can mean the session is gone or only that org refused; when every
            // org refused, the org list tells which.
            if outcome.readings.isEmpty, outcome.failures.contains(where: { $0.problem == .refused }),
               await sessionIsGone() {
                model.sessionEnded()
                return
            }
            model.ingest(outcome, claudeCodeOrg: account.currentOrg(), at: now)
            // Back off only when nothing worked: one org that never reads (a free plan, say)
            // mustn't slow down the others.
            failures = outcome.readings.isEmpty && !outcome.failures.isEmpty ? failures + 1 : 0
        } catch WebSessionError.signedOut {
            model.sessionEnded()
        } catch WebSessionError.forbidden {
            if await sessionIsGone() {
                model.sessionEnded()
            } else {
                failures += 1
                model.refreshFailed(.refused)
            }
        } catch {
            failures += 1
            model.refreshFailed(RefreshProblem(error))
        }
    }

    /// After a sign-in the account may be different: re-read the org list, then poll.
    func restartAfterSignIn() {
        orgsFetchedAt = nil
        start()
    }

    private func sessionIsGone() async -> Bool {
        do {
            _ = try await session.getJSON("/api/organizations")
            return false
        } catch WebSessionError.signedOut, WebSessionError.forbidden {
            return true
        } catch {
            return false
        }
    }

    private func checkAccount() {
        let modified = account.modified()
        guard modified != accountModified else { return }
        accountModified = modified
        model.setClaudeCodeOrg(account.currentOrg())
    }
}
