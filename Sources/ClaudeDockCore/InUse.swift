import Foundation

/// Whether an org is being used right now. Two signals: Claude Code writing its transcripts
/// while signed into the org (seconds behind), and the org's usage going up between two
/// readings (one poll behind, but it also sees the desktop app and the browser).
public enum InUse {
    /// Claude Code counts as working for this long after it last wrote a transcript.
    public static let claudeCodeQuiet: TimeInterval = 60
    /// A rise counts for this long after the reading that showed it: a little over one poll.
    public static let riseLasts: TimeInterval = 240
    /// Reset times this close together belong to the same window.
    static let sameWindow: TimeInterval = 60

    public static func isInUse(org: String, latest: Reading?, previous: Reading?, claudeCodeOrg: String?,
                               claudeCodeActiveAt: Date?, stale: Bool, now: Date) -> Bool {
        guard !stale else { return false }
        if org == claudeCodeOrg, let active = claudeCodeActiveAt, now.timeIntervalSince(active) < claudeCodeQuiet {
            return true
        }
        guard let latest, let previous, now.timeIntervalSince(latest.time) < riseLasts,
              latest.time.timeIntervalSince(previous.time) <= Reading.freshFor else { return false }
        return rose(from: previous, to: latest)
    }

    /// Whether usage went up between two readings of one org: more used in the same 5-hour
    /// or weekly window, or a new window that already shows use (a window opens on first
    /// use). A reset to nothing is not a rise.
    public static func rose(from previous: Reading, to latest: Reading) -> Bool {
        func rose(_ before: Double, _ beforeReset: Date?, _ after: Double, _ afterReset: Date?) -> Bool {
            guard let afterReset, after > 0 else { return false }
            guard let beforeReset, abs(afterReset.timeIntervalSince(beforeReset)) < sameWindow else { return true }
            return after > before
        }
        return rose(previous.session, previous.sessionResetsAt, latest.session, latest.sessionResetsAt)
            || rose(previous.week, previous.weekResetsAt, latest.week, latest.weekResetsAt)
    }
}
