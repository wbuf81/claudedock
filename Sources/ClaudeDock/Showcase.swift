import AppKit
import SwiftUI
import ClaudeDockCore

/// `ClaudeDock --showcase DIR` draws the README's images from the Pokémon demo data: a desktop
/// scene, every widget state, the panel in dark and light, and a social-preview card. Nothing
/// from the real screen or account can end up in them.
@MainActor
enum Showcase {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 11, minute: 32))!
        let scenarios = DemoData.scenarios(now: now)
        let settings = Settings(defaults: UserDefaults(suiteName: "ClaudeDockShowcase")!)
        let history = dir.appendingPathComponent("showcase-history.jsonl")
        func model(_ scenario: DemoScenario) -> AppModel {
            let model = AppModel(settings: settings, store: HistoryStore(url: history))
            model.apply(scenario)
            model.widgetHeight = 82
            return model
        }
        let main = model(scenarios[0])

        write(DesktopScene(model: main, dark: true), size: CGSize(width: 1180, height: 820), scheme: .dark, to: dir, "hero-dark.png")
        write(DesktopScene(model: main, dark: false), size: CGSize(width: 1180, height: 820), scheme: .light, to: dir, "hero-light.png")
        write(StatesSheet(rows: zip(captions, scenarios).map { ($0, model($1)) }),
              size: CGSize(width: 1100, height: 760), scheme: .dark, to: dir, "states.png")
        for scheme in [ColorScheme.dark, .light] {
            let name = scheme == .dark ? "panel-dark.png" : "panel-light.png"
            write(PanelOnly(model: main, dark: scheme == .dark), size: CGSize(width: 520, height: 900), scheme: scheme, to: dir, name)
        }
        write(SocialCard(model: main), size: CGSize(width: 1280, height: 640), scheme: .dark, to: dir, "social-card.png")
        let side = model(scenarios[0])
        side.vertical = true
        write(SideScene(model: side), size: CGSize(width: 1000, height: 820), scheme: .dark, to: dir, "vertical.png")
        write(CompactScene(model: main), size: CGSize(width: 1180, height: 330), scheme: .dark, to: dir, "compact.png")
        try? FileManager.default.removeItem(at: history)
        print("Showcase written to \(dir.path)")
    }

    /// One line per demo scenario, in `DemoData.scenarios` order.
    static let captions = [
        "Pikachu is green: tokens would go unused. Charizard is nearly out.",
        "Pikachu's 5-hour window is busy, so move Claude Code to Charizard and leave room for the desktop app.",
        "Charizard's week resets first, so use it before it expires.",
        "Both are low: Charizard is back first.",
        "Pikachu is on pace (yellow) but down to its last 12%, so Charizard, whose week hasn't started, goes first.",
    ]

    /// `--matrix DIR`: the widget across org counts, name lengths, layouts and sizes, and the
    /// panel with one and three orgs, in dark and light, on sheets for checking by eye.
    static func renderMatrix(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 11, minute: 32))!
        let settings = Settings(defaults: UserDefaults(suiteName: "ClaudeDockMatrix")!)
        let history = dir.appendingPathComponent("matrix-history.jsonl")
        func at(_ hours: Double) -> Date { now.addingTimeInterval(hours * 3600) }
        func reading(_ org: Org, _ week: Double, _ reset: Double, _ session: Double, _ sessionReset: Double?) -> Reading {
            Reading(time: now, org: org.id, session: session, sessionResetsAt: sessionReset.map(at),
                    week: week, weekResetsAt: at(reset), scoped: ["Fable": 20])
        }
        let pikachu = Org(id: "m-pikachu", name: "Pikachu", billingType: "x")
        let charizard = Org(id: "m-charizard", name: "Charizard", billingType: "x")
        let bulbasaur = Org(id: "m-bulbasaur", name: "Bulbasaur", billingType: "x")
        let longA = Org(id: "m-long-a", name: "Team Rocket Pikachu Research Division", billingType: "x")
        let longB = Org(id: "m-long-b", name: "Team Rocket Charizard Field Operations", billingType: "x")
        let sets: [(String, [Org], [Reading])] = [
            ("1 org", [pikachu], [reading(pikachu, 55, 64, 19, 3)]),
            ("2 orgs", [pikachu, charizard], [reading(pikachu, 55, 64, 19, 3), reading(charizard, 95, 33, 0, nil)]),
            ("3 orgs", [pikachu, charizard, bulbasaur],
             [reading(pikachu, 55, 64, 19, 3), reading(charizard, 95, 33, 0, nil), reading(bulbasaur, 30, 100, 82, 1)]),
            ("long names", DisplayNames.short([longA, longB]),
             [reading(longA, 55, 64, 19, 3), reading(longB, 20, 120, 5, 4)]),
            ("long, unshortened", [longA, Org(id: "m-other", name: "Squirtle Platform Engineering Group", billingType: "x")],
             [reading(longA, 55, 64, 19, 3), reading(Org(id: "m-other", name: "", billingType: nil), 20, 120, 5, 4)]),
        ]
        func model(_ set: (String, [Org], [Reading]), size: Double, vertical: Bool) -> AppModel {
            let model = AppModel(settings: settings, store: HistoryStore(url: history))
            model.apply(DemoScenario(name: set.0, orgs: set.1, primary: set.1[0].id, readings: set.2,
                                     claudeCodeOrg: set.1[0].id, now: now))
            model.widgetHeight = 82 * size
            model.widgetScale = size
            model.vertical = vertical
            return model
        }
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            var rows: [(String, AppModel, Bool)] = []
            for set in sets {
                for size in [0.8, 1.0, 1.5] { rows.append(("\(set.0) · \(Int(size * 100))%", model(set, size: size, vertical: false), false)) }
                rows.append(("\(set.0) · compact", model(set, size: 1, vertical: false), true))
            }
            write(MatrixSheet(rows: rows), size: CGSize(width: 1500, height: 2400), scheme: scheme, to: dir, "matrix-horizontal-\(suffix).png")
            let strips = sets.flatMap { [($0.0, model($0, size: 1, vertical: true), false),
                                         ("\($0.0) · compact", model($0, size: 1, vertical: true), true)] }
            write(StripSheet(strips: strips), size: CGSize(width: 1500, height: 760), scheme: scheme, to: dir, "matrix-vertical-\(suffix).png")
            write(HStack(alignment: .top, spacing: 24) {
                PanelView(model: model(sets[0], size: 1, vertical: false), actions: .none).fixedSize()
                PanelView(model: model(sets[2], size: 1, vertical: false), actions: .none).fixedSize()
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Wallpaper(dark: scheme == .dark)),
                  size: CGSize(width: 860, height: 1200), scheme: scheme, to: dir, "matrix-panels-\(suffix).png")
        }
        try? FileManager.default.removeItem(at: history)
        print("Matrix written to \(dir.path)")
    }

    private static func write<V: View>(_ view: V, size: CGSize, scheme: ColorScheme, to dir: URL, _ name: String) {
        let framed = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
            .environment(\.renderStyle, .showcase)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: dir.appendingPathComponent(name))
    }
}

private struct Wallpaper: View {
    var dark: Bool

    var body: some View {
        LinearGradient(
            colors: dark
                ? [Color(red: 0.14, green: 0.20, blue: 0.30), Color(red: 0.29, green: 0.27, blue: 0.40), Color(red: 0.66, green: 0.47, blue: 0.42)]
                : [Color(red: 0.62, green: 0.77, blue: 0.91), Color(red: 0.79, green: 0.71, blue: 0.89), Color(red: 0.95, green: 0.79, blue: 0.66)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A Dock-shaped bar of plain coloured tiles: no real app icons.
private struct FakeDock: View {
    private let tiles: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .yellow, .mint]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 11)
                    .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 48, height: 48)
            }
        }
        .padding(.horizontal, 17)
        .frame(height: 82)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
    }
}

/// The bottom-right of a desktop: Dock, widget, and the panel opened above it.
private struct DesktopScene: View {
    @ObservedObject var model: AppModel
    var dark: Bool

    var body: some View {
        ZStack {
            Wallpaper(dark: dark)
            FakeDock()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, -160)
                .padding(.bottom, 6)
            VStack(alignment: .trailing, spacing: 8) {
                PanelView(model: model, actions: .none)
                WidgetView(model: model, actions: .none)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 12)
            .padding(.bottom, 6)
        }
    }
}

/// The bottom-right of a desktop twice: the compact widget beside the Dock, and the full
/// widget it grows to when the pointer rests on it.
private struct CompactScene: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Wallpaper(dark: true)
            VStack(spacing: 40) {
                row(compact: true)
                row(compact: false)
            }
            .padding(.vertical, 30)
        }
    }

    private func row(compact: Bool) -> some View {
        ZStack {
            FakeDock()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, -160)
            WidgetView(model: model, actions: .none, compact: compact).fixedSize()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
        }
    }
}

/// The right edge of a desktop: the vertical strip with its panel opened beside it.
private struct SideScene: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Wallpaper(dark: true)
            HStack(alignment: .center, spacing: 8) {
                PanelView(model: model, actions: .none).fixedSize()
                WidgetView(model: model, actions: .none).fixedSize()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 6)
        }
    }
}

private struct MatrixSheet: View {
    var rows: [(String, AppModel, Bool)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper(dark: true)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 20) {
                        Text(row.0).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).frame(width: 190, alignment: .leading)
                        WidgetView(model: row.1, actions: .none, compact: row.2).fixedSize()
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct StripSheet: View {
    var strips: [(String, AppModel, Bool)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper(dark: true)
            HStack(alignment: .top, spacing: 26) {
                ForEach(Array(strips.enumerated()), id: \.offset) { _, strip in
                    VStack(spacing: 10) {
                        Text(strip.0).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 110).lineLimit(2).multilineTextAlignment(.center)
                        WidgetView(model: strip.1, actions: .none, compact: strip.2).fixedSize()
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct StatesSheet: View {
    var rows: [(String, AppModel)]

    var body: some View {
        ZStack {
            Wallpaper(dark: true)
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 28) {
                        WidgetView(model: row.1, actions: .none).fixedSize()
                        Text(row.0)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(40)
        }
    }
}

private struct PanelOnly: View {
    @ObservedObject var model: AppModel
    var dark: Bool

    var body: some View {
        ZStack {
            Wallpaper(dark: dark)
            PanelView(model: model, actions: .none).fixedSize()
        }
    }
}

private struct SocialCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Wallpaper(dark: true)
            VStack(spacing: 30) {
                VStack(spacing: 10) {
                    Text("Claude Dock").font(.system(size: 84, weight: .bold)).foregroundStyle(.white)
                    Text("Your Claude plan usage, always in the corner of your screen")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                WidgetView(model: model, actions: .none).fixedSize().scaleEffect(1.5)
                    .padding(.top, 20)
            }
        }
    }
}
