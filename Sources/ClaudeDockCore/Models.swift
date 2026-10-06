import Foundation

/// A Claude organization the signed-in account belongs to.
public struct Org: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var billingType: String?

    public init(id: String, name: String, billingType: String? = nil) {
        self.id = id
        self.name = name
        self.billingType = billingType
    }
}

/// How the owner uses an org. The primary org is shared with the Claude desktop app.
public enum Role: String, Codable, Sendable {
    case primary, overflow
}

/// One usage snapshot for one org. Percentages are "used", 0–100.
public struct Reading: Codable, Equatable, Sendable {
    public var time: Date
    public var org: String
    public var session: Double
    /// nil when no 5-hour window is open.
    public var sessionResetsAt: Date?
    public var week: Double
    /// nil when the week hasn't started (nothing used yet).
    public var weekResetsAt: Date?
    /// Model-specific weekly limits, e.g. ["Fable": 31].
    public var scoped: [String: Double]

    public init(time: Date, org: String, session: Double, sessionResetsAt: Date?,
                week: Double, weekResetsAt: Date?, scoped: [String: Double] = [:]) {
        self.time = time
        self.org = org
        self.session = session
        self.sessionResetsAt = sessionResetsAt
        self.week = week
        self.weekResetsAt = weekResetsAt
        self.scoped = scoped
    }

    enum CodingKeys: String, CodingKey {
        case time = "t", org, session, sessionResetsAt, week, weekResetsAt, scoped
    }

    public var weekLeft: Double { 100 - week }

    /// How long a reading counts as current. Refreshes come every 3 minutes, so an older
    /// reading means its org has stopped reading.
    public static let freshFor: TimeInterval = 600

    public func isFresh(now: Date) -> Bool { now.timeIntervalSince(time) <= Self.freshFor }

    /// The reading as it stands at `now`: a window whose reset time has passed is empty again.
    public func adjusted(to now: Date) -> Reading {
        var r = self
        if let reset = r.sessionResetsAt, reset <= now {
            r.session = 0
            r.sessionResetsAt = nil
        }
        if let reset = r.weekResetsAt, reset <= now {
            r.week = 0
            r.weekResetsAt = nil
            r.scoped = r.scoped.mapValues { _ in 0 }
        }
        return r
    }

    /// How far into the current 5-hour window `now` is, 0...1; nil when no window is open.
    public func sessionElapsedFraction(now: Date) -> Double? {
        guard let reset = sessionResetsAt else { return nil }
        return min(max(1 - reset.timeIntervalSince(now) / (5 * 3600), 0), 1)
    }
}
