import Foundation

/// What the crab acts out: what Claude Code is doing in a session.
public enum CrabMood: String, CaseIterable, Sendable {
    case idle, thinking, tool, permission, done

    /// With several sessions the crab shows the most urgent one.
    public var urgency: Int {
        switch self {
        case .permission: 4
        case .tool: 3
        case .thinking: 2
        case .done: 1
        case .idle: 0
        }
    }
}

/// One Claude Code session's last hook event: its process, the mood the event means, and when.
public struct CrabSession: Equatable, Sendable {
    public var pid: Int32
    public var mood: CrabMood
    public var time: Date

    public init(pid: Int32, mood: CrabMood, time: Date) {
        self.pid = pid
        self.mood = mood
        self.time = time
    }
}

/// Turns Claude Code's sessions into the crab's one mood.
public enum Crab {
    /// "Done" plays this long, then the crab rests.
    public static let doneLasts: TimeInterval = 10
    /// A working mood that hasn't changed this long was probably missed (a hook that didn't
    /// run, a killed session): rest.
    public static let stuckAfter: TimeInterval = 600
    /// Files older than this are ignored: after a reboot their pid may belong to anything.
    public static let fileExpires: TimeInterval = 12 * 3600

    /// Reads a session file: `"<mood> <unix seconds>"`.
    public static func parse(_ text: String, pid: Int32) -> CrabSession? {
        let parts = text.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, let mood = CrabMood(rawValue: String(parts[0])),
              let seconds = TimeInterval(parts[1]) else { return nil }
        return CrabSession(pid: pid, mood: mood, time: Date(timeIntervalSince1970: seconds))
    }

    /// The crab's mood for these sessions, or nil when none is live.
    public static func mood(_ sessions: [CrabSession], isAlive: (Int32) -> Bool, now: Date) -> CrabMood? {
        sessions
            .filter { now.timeIntervalSince($0.time) < fileExpires && isAlive($0.pid) }
            .map { current($0, now: now) }
            .max { $0.urgency < $1.urgency }
    }

    /// When the mood next changes with no new event (a "done" ending, a stuck mood resting),
    /// so the widget can redraw then.
    public static func nextChange(_ sessions: [CrabSession], now: Date) -> Date? {
        sessions.compactMap { session -> Date? in
            let edge: TimeInterval
            switch session.mood {
            case .idle: return nil
            case .done: edge = doneLasts
            case .thinking, .tool, .permission: edge = stuckAfter
            }
            let at = session.time.addingTimeInterval(edge)
            return at > now ? at : nil
        }.min()
    }

    /// Without hooks: "tool" while Claude Code wrote a transcript in the last minute, then
    /// "done" for a moment, then no crab.
    public static func fallbackMood(claudeCodeActiveAt: Date?, now: Date) -> CrabMood? {
        guard let active = claudeCodeActiveAt else { return nil }
        let quiet = now.timeIntervalSince(active)
        if quiet < InUse.claudeCodeQuiet { return .tool }
        if quiet < InUse.claudeCodeQuiet + doneLasts { return .done }
        return nil
    }

    private static func current(_ session: CrabSession, now: Date) -> CrabMood {
        let age = now.timeIntervalSince(session.time)
        switch session.mood {
        case .done where age >= doneLasts: return .idle
        case .thinking, .tool, .permission: return age >= stuckAfter ? .idle : session.mood
        default: return session.mood
        }
    }
}
