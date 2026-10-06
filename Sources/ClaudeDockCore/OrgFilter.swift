import Foundation

/// Which orgs the widget shows.
public enum OrgFilter {
    /// Paid orgs by default (a free personal org has no billing type). An account with no
    /// paid org shows what it has, rather than nothing.
    public static func defaultShown(_ orgs: [Org]) -> [Org] {
        let paid = orgs.filter { $0.billingType != nil }
        return paid.isEmpty ? orgs : paid
    }

    /// The owner's picks from Settings, or the default; picking none falls back to the default
    /// rather than an empty widget.
    public static func shown(_ orgs: [Org], chosen: [String]?) -> [Org] {
        guard let chosen else { return defaultShown(orgs) }
        let picked = orgs.filter { chosen.contains($0.id) }
        return picked.isEmpty ? defaultShown(orgs) : picked
    }
}
