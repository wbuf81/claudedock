import Foundation

/// Which orgs the widget shows.
public enum OrgFilter {
    /// Paid orgs by default (a free personal org has no billing type). An account with no
    /// paid org shows what it has, rather than nothing.
    public static func defaultShown(_ orgs: [Org]) -> [Org] {
        let paid = orgs.filter { $0.billingType != nil }
        return paid.isEmpty ? orgs : paid
    }

    /// The owner's choices from Settings (org id → shown), with the default for any org they
    /// haven't chosen for, such as one joined later. Hiding every org falls back to the
    /// default rather than an empty widget.
    public static func shown(_ orgs: [Org], choices: [String: Bool]) -> [Org] {
        let byDefault = Set(defaultShown(orgs).map(\.id))
        let picked = orgs.filter { choices[$0.id] ?? byDefault.contains($0.id) }
        return picked.isEmpty ? defaultShown(orgs) : picked
    }

    /// Earlier versions saved the list of shown orgs; every other known org was hidden.
    public static func choices(fromShown shown: [String], known: [Org]) -> [String: Bool] {
        Dictionary(known.map { ($0.id, shown.contains($0.id)) }, uniquingKeysWith: { a, _ in a })
    }
}
