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
    /// Where the owner put the widget; nil means the bottom-right corner.
    @Published var widgetSpot: WidgetSpot? { didSet { save(widgetSpot, "widgetSpot") } }
    @Published var layoutChoice: LayoutChoice { didSet { defaults.set(layoutChoice.rawValue, forKey: "layoutChoice") } }
    /// A multiple of the Dock-matched size, 0.6...2.
    @Published var sizeScale: Double { didSet { defaults.set(sizeScale, forKey: "sizeScale") } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        thresholds = Self.load(Thresholds.self, "thresholds", defaults) ?? Thresholds()
        primaryOrg = defaults.string(forKey: "primaryOrg")
        shownOrgs = defaults.stringArray(forKey: "shownOrgs")
        knownOrgs = Self.load([Org].self, "knownOrgs", defaults) ?? []
        notifySwitch = defaults.object(forKey: "notifySwitch") as? Bool ?? true
        notifyRed = defaults.object(forKey: "notifyRed") as? Bool ?? true
        demoMode = defaults.bool(forKey: "demoMode")
        // Earlier versions saved only a dragged-to offset.
        widgetSpot = Self.load(WidgetSpot.self, "widgetSpot", defaults)
            ?? Self.load(WidgetOffset.self, "widgetOffset", defaults).map { .free($0) }
        layoutChoice = LayoutChoice(rawValue: defaults.string(forKey: "layoutChoice") ?? "") ?? .automatic
        sizeScale = WidgetLayout.clampSize(defaults.object(forKey: "sizeScale") as? Double ?? 1)
    }

    /// Whether an org is shown: the owner's picks, or by default every paid org (or every org,
    /// for an account with none).
    func isShown(_ org: Org) -> Bool {
        OrgFilter.shown(knownOrgs, chosen: shownOrgs).contains { $0.id == org.id }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
