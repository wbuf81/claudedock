import Foundation
@testable import ClaudeDockCore

/// Tests run in New York time so day names and midnights are deterministic.
let newYork: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

/// A New York local time, e.g. `local(2026, 10, 6, 11, 32)`.
func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

/// The moment the design was drawn: Tuesday Oct 6 2026, 11:32 AM in New York.
let designNow = local(2026, 10, 6, 11, 32)

func reading(
    org: String = "pikachu", week: Double, weekResetsAt: Date?,
    session: Double = 0, sessionResetsAt: Date? = nil,
    at time: Date = designNow, scoped: [String: Double] = [:]
) -> Reading {
    Reading(time: time, org: org, session: session, sessionResetsAt: sessionResetsAt,
            week: week, weekResetsAt: weekResetsAt, scoped: scoped)
}

func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.05) -> Bool { abs(a - b) <= tolerance }
