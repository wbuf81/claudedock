import Foundation

public enum UsageParserError: Error, Equatable {
    case notJSON
    case noWeeklyLimit
}

/// Turns claude.ai's JSON into models. Tolerant: unknown fields are ignored, and the
/// older `five_hour` / `seven_day` fields fill in whatever `limits` doesn't provide.
public enum UsageParser {
    public static func orgs(from data: Data) throws -> [Org] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw UsageParserError.notJSON
        }
        return list.compactMap { item in
            guard let id = item["uuid"] as? String, let name = item["name"] as? String else { return nil }
            return Org(id: id, name: name, billingType: item["billing_type"] as? String)
        }
    }

    public static func reading(from data: Data, org: String, at time: Date) throws -> Reading {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageParserError.notJSON
        }
        var session = 0.0
        var sessionResetsAt: Date?
        var week: Double?
        var weekResetsAt: Date?
        var scoped: [String: Double] = [:]

        if let fiveHour = root["five_hour"] as? [String: Any] {
            session = number(fiveHour["utilization"]) ?? 0
            sessionResetsAt = date(fiveHour["resets_at"])
        }
        if let sevenDay = root["seven_day"] as? [String: Any] {
            week = number(sevenDay["utilization"])
            weekResetsAt = date(sevenDay["resets_at"])
        }
        for limit in root["limits"] as? [[String: Any]] ?? [] {
            let percent = number(limit["percent"])
            let reset = date(limit["resets_at"])
            switch limit["kind"] as? String {
            case "session":
                session = percent ?? 0
                sessionResetsAt = reset
            case "weekly_all":
                week = percent
                weekResetsAt = reset
            case "weekly_scoped":
                let model = (limit["scope"] as? [String: Any])?["model"] as? [String: Any]
                if let name = model?["display_name"] as? String, let percent {
                    scoped[name] = clamp(percent)
                }
            default:
                break
            }
        }
        guard let week else { throw UsageParserError.noWeeklyLimit }
        return Reading(time: time, org: org, session: clamp(session), sessionResetsAt: sessionResetsAt,
                       week: clamp(week), weekResetsAt: weekResetsAt, scoped: scoped)
    }

    /// claude.ai sends microseconds ("2026-10-06T15:20:00.408772+00:00"), which
    /// ISO8601DateFormatter can't read, and the fraction drifts between requests. Drop it
    /// and round to the nearest minute so one window always has one reset time.
    public static func parseDate(_ text: String) -> Date? {
        var trimmed = text
        if let dot = trimmed.firstIndex(of: "."),
           let end = trimmed[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            trimmed.removeSubrange(dot..<end)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: trimmed) else { return nil }
        return Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
    }

    private static func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
    private static func date(_ value: Any?) -> Date? { (value as? String).flatMap(parseDate) }
    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 100) }
}
