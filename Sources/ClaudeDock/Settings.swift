import Foundation
import ClaudeDockCore

/// The owner's choices, saved in UserDefaults on this Mac only.
@MainActor
final class Settings: ObservableObject {
    private let defaults: UserDefaults

    @Published var thresholds: Thresholds { didSet { save(thresholds, "thresholds") } }
    @Published var primaryOrg: String? { didSet { defaults.set(primaryOrg, forKey: "primaryOrg") } }
    @Published var shownOrgs: [String]? { didSet { defaults.set(shownOrgs, forKey: "shownOrgs") } }
    @Published var knownOrgs: [Org] { didSet { save(knownOrgs, "knownOrgs") } }
    @Published var notifySwitch: Bool { didSet { defaults.set(notifySwitch, forKey: "notifySwitch") } }
    @Published var notifyRed: Bool { didSet { defaults.set(notifyRed, forKey: "notifyRed") } }
    @Published var demoMode: Bool { didSet { defaults.set(demoMode, forKey: "demoMode") } }
    /// Where the owner dragged the widget; nil means the bottom-right corner.
    @Published var widgetOffset: WidgetOffset? { didSet { save(widgetOffset, "widgetOffset") } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        thresholds = Self.load(Thresholds.self, "thresholds", defaults) ?? Thresholds()
        primaryOrg = defaults.string(forKey: "primaryOrg")
        shownOrgs = defaults.stringArray(forKey: "shownOrgs")
        knownOrgs = Self.load([Org].self, "knownOrgs", defaults) ?? []
        notifySwitch = defaults.object(forKey: "notifySwitch") as? Bool ?? true
        notifyRed = defaults.object(forKey: "notifyRed") as? Bool ?? true
        demoMode = defaults.bool(forKey: "demoMode")
        widgetOffset = Self.load(WidgetOffset.self, "widgetOffset", defaults)
    }

    /// The owner's picks, or by default every paid org (a free personal org has no billing type).
    func isShown(_ org: Org) -> Bool {
        shownOrgs.map { $0.contains(org.id) } ?? (org.billingType != nil)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
