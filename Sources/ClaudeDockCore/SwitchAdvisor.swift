import Foundation

/// One org with everything the switch rules need.
public struct OrgStatus: Equatable, Sendable {
    public var org: Org
    public var role: Role
    public var reading: Reading
    public var light: Light

    public init(org: Org, role: Role, reading: Reading, light: Light) {
        self.org = org
        self.role = role
        self.reading = reading
        self.light = light
    }
}

/// "Move Claude Code to <target>", and why.
public struct Advice: Equatable, Sendable {
    public var target: Org
    public var reason: String

    public init(target: Org, reason: String) {
        self.target = target
        self.reason = reason
    }
}

public enum SwitchAdvisor {
    /// Enough room for Claude Code: week left above the minimum (higher for the primary org,
    /// which keeps a buffer for the desktop app) and a 5-hour window that isn't nearly full.
    public static func isEligible(_ s: OrgStatus, _ t: Thresholds) -> Bool {
        s.reading.weekLeft >= minimumWeekLeft(s.role, t) && s.reading.session < t.eligibleSessionBelow
    }

    /// The eligible org whose week resets soonest (use it or lose it); ties go to overflow.
    public static func best(_ orgs: [OrgStatus], now: Date, _ t: Thresholds) -> OrgStatus? {
        orgs.filter { isEligible($0, t) }.min { a, b in
            let resetA = a.reading.weekResetsAt ?? now.addingTimeInterval(Pace.window)
            let resetB = b.reading.weekResetsAt ?? now.addingTimeInterval(Pace.window)
            if resetA != resetB { return resetA < resetB }
            return a.role == .overflow && b.role != .overflow
        }
    }

    /// Only orgs with a current reading count: an old one can look emptier than the org is.
    public static func advice(_ orgs: [OrgStatus], claudeCodeOrg: String?, now: Date,
                              formatting: Formatting, _ t: Thresholds) -> Advice? {
        let orgs = orgs.filter { $0.reading.isFresh(now: now) }
        guard let current = orgs.first(where: { $0.org.id == claudeCodeOrg }),
              let best = best(orgs, now: now, t), best.org.id != current.org.id else { return nil }
        return Advice(target: best.org, reason: reason(current: current, best: best, now: now, formatting: formatting, t))
    }

    /// The panel's top line. `hidden` is the orgs the owner chose not to show.
    public static func statusLine(_ orgs: [OrgStatus], claudeCodeOrg: String?, advice: Advice?, now: Date,
                                  formatting: Formatting, _ t: Thresholds, hidden: [Org] = []) -> String {
        if let advice { return "Move Claude Code to \(advice.target.name): \(advice.reason)." }
        if let org = hidden.first(where: { $0.id == claudeCodeOrg }) {
            return "Claude Code is on \(org.name), which isn't shown here. Turn it on in Settings to follow it."
        }
        // One org has nothing to switch between; its dot and TODAY box say the rest.
        let orgs = orgs.filter { $0.reading.isFresh(now: now) }
        guard orgs.count > 1 else { return "" }
        if !orgs.contains(where: { isEligible($0, t) }) {
            let low = orgs.count == 2 ? "Both orgs are low." : "Every org is low."
            let back = orgs.compactMap { s -> (OrgStatus, Date)? in
                let date = s.reading.weekLeft < minimumWeekLeft(s.role, t) ? s.reading.weekResetsAt : s.reading.sessionResetsAt
                return date.map { (s, $0) }
            }.min { $0.1 < $1.1 }
            guard let (first, date) = back else { return low }
            return "\(low) \(first.org.name) is back first, \(formatting.dayTime(date, now: now))."
        }
        if let current = orgs.first(where: { $0.org.id == claudeCodeOrg }) {
            return "Claude Code is on \(current.org.name), the right place right now."
        }
        return ""
    }

    static func minimumWeekLeft(_ role: Role, _ t: Thresholds) -> Double {
        role == .primary ? max(t.eligibleWeekLeft, t.primaryReserveWeekLeft) : t.eligibleWeekLeft
    }

    static func reason(current: OrgStatus, best: OrgStatus, now: Date, formatting: Formatting, _ t: Thresholds) -> String {
        let name = current.org.name
        if current.light == .red, current.reading.weekLeft < t.eligibleWeekLeft {
            return "\(name) is nearly out"
        }
        if current.reading.session >= t.eligibleSessionBelow {
            let busy = "\(name) 5h at \(Formatting.percent(current.reading.session))"
            return current.role == .primary ? "\(busy), desktop app needs room" : busy
        }
        if current.role == .primary, current.reading.weekLeft < t.primaryReserveWeekLeft {
            return "\(name) is down to \(Formatting.percent(current.reading.weekLeft)), keep it for the desktop app"
        }
        if let reset = best.reading.weekResetsAt {
            return "\(best.org.name) has \(Formatting.percent(best.reading.weekLeft)) expiring \(formatting.dayTime(reset, now: now))"
        }
        return "\(best.org.name) has more room"
    }
}

/// Keeps switch advice from flip-flopping. A target must win two readings in a row, and
/// advice to go back to the org the owner was just moved off is held for an hour, unless
/// the org they're on now turns red.
public struct AdviceGate: Sendable {
    public private(set) var shown: Advice?
    public var hold: TimeInterval = 3600
    private var pending: Advice?
    private var movedOff: String?
    private var shownAt: Date?

    public init() {}

    public mutating func update(_ candidate: Advice?, claudeCodeOrg: String?, currentIsRed: Bool, now: Date) -> Advice? {
        guard let candidate else {
            pending = nil
            shown = nil
            return nil
        }
        if candidate.target.id == shown?.target.id {
            shown = candidate
            return shown
        }
        if let movedOff, let shownAt, candidate.target.id == movedOff,
           now.timeIntervalSince(shownAt) < hold, !currentIsRed {
            pending = nil
            shown = nil
            return nil
        }
        if pending?.target.id == candidate.target.id {
            shown = candidate
            pending = nil
            movedOff = claudeCodeOrg
            shownAt = now
        } else {
            pending = candidate
            shown = nil
        }
        return shown
    }
}
